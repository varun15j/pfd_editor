import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../ui/luma_icons.dart';

/// Thrown inside an open task once the user has cancelled, to stop it early.
class OpenCancelled implements Exception {
  const OpenCancelled();
}

/// What an open task is doing now, for the progress dialog.
@immutable
class OpenStatus {
  const OpenStatus(this.stage, {this.done, this.total, this.unit = OpenUnit.pages});

  /// Short words for the step, such as "Reading pages".
  final String stage;
  final int? done;
  final int? total;
  final OpenUnit unit;

  /// 0..1, or null while the amount of work is unknown.
  double? get fraction {
    final d = done, t = total;
    if (d == null || t == null || t <= 0) return null;
    return (d / t).clamp(0.0, 1.0);
  }

  /// "12 of 480 pages", "3.1 of 40 MB", or null.
  String? get detail {
    final d = done, t = total;
    if (d == null || t == null || t <= 0) return null;
    return switch (unit) {
      OpenUnit.pages => '$d of $t pages',
      OpenUnit.bytes => '${_mb(d)} of ${_mb(t)}',
    };
  }

  static String _mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
  }
}

enum OpenUnit { pages, bytes }

/// Handed to an open task: it reports progress, and checks whether the user
/// cancelled. Time spent waiting for the user (a password dialog) does not
/// count towards the "taking too long" prompt.
class OpenProgress {
  OpenProgress({String name = ''}) : name = ValueNotifier(name);

  final status = ValueNotifier<OpenStatus>(const OpenStatus('Opening'));

  /// The document's name in the dialog. A picked file's name is known only
  /// once the picker has finished copying it.
  final ValueNotifier<String> name;

  /// True while the task waits for the user; the dialog hides meanwhile so
  /// a password dialog is not drawn on top of it.
  final waiting = ValueNotifier<bool>(false);
  bool _cancelled = false;
  int _waiting = 0;

  bool get cancelled => _cancelled;

  /// The task is waiting for the user, such as for a password.
  bool get waitingForUser => _waiting > 0;

  void report(String stage, {int? done, int? total, OpenUnit unit = OpenUnit.pages}) {
    if (_cancelled) return;
    status.value = OpenStatus(stage, done: done, total: total, unit: unit);
  }

  void rename(String newName) {
    if (!_cancelled) name.value = newName;
  }

  void throwIfCancelled() {
    if (_cancelled) throw const OpenCancelled();
  }

  /// Runs [ask], such as a password dialog, with the clock stopped.
  Future<R> waitForUser<R>(Future<R> Function() ask) async {
    _waiting++;
    waiting.value = true;
    try {
      return await ask();
    } finally {
      _waiting--;
      waiting.value = _waiting > 0;
    }
  }

  void _cancel() => _cancelled = true;
}

/// Opening work runs at most once at a time, so a double tap on a document
/// does not open it twice.
bool _opening = false;

/// True while [runOpenWithProgress] is busy.
bool get isOpeningDocument => _opening;

/// Runs [task] with a progress dialog over the app. The dialog shows the
/// step and how far it got, and the user can stop it with the X, Cancel, or
/// the back button. After [slowAfter] it says the document is taking too
/// long and offers Wait or Cancel; Wait asks again after [askAgainAfter].
///
/// Returns the task's value, or null when the user cancelled or another
/// open is already running. A value that arrives after the user cancelled
/// is handed to [discard] (to close a half-opened document). Errors thrown
/// by the task, other than [OpenCancelled], are rethrown.
///
/// The dialog appears straight away (after [showAfter]); until it is up a
/// barrier blocks taps.
Future<T?> runOpenWithProgress<T>(
  BuildContext context, {
  required String name,
  required Future<T> Function(OpenProgress progress) task,
  FutureOr<void> Function(T value)? discard,
  Duration showAfter = Duration.zero,
  Duration slowAfter = const Duration(seconds: 10),
  Duration askAgainAfter = const Duration(seconds: 20),
}) async {
  if (_opening) return null;
  _opening = true;
  final progress = OpenProgress(name: name);
  final outcome = Completer<_Outcome<T>>();

  // The task starts at once; the dialog only watches it.
  unawaited(
    Future<T>.sync(() => task(progress)).then(
      (value) {
        if (outcome.isCompleted || progress.cancelled) {
          discard?.call(value);
        } else {
          outcome.complete(_Outcome.value(value));
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!outcome.isCompleted) outcome.complete(_Outcome.error(error, stack));
      },
    ),
  );

  void cancel() {
    if (outcome.isCompleted) return;
    progress._cancel();
    outcome.complete(const _Outcome.cancelled());
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = Overlay.of(context, rootOverlay: true);

  // Blocks taps until the dialog, which has its own barrier, is up. The
  // Navigator puts its routes below entries added straight to the overlay,
  // so the shield has to go once the dialog shows.
  final shield = OverlayEntry(builder: (_) => const ModalBarrier(dismissible: false));
  overlay.insert(shield);
  var shieldUp = true;
  void dropShield() {
    if (shieldUp) shield.remove();
    shieldUp = false;
  }

  Future<void>? dialogClosed;
  final showTimer = Timer(showAfter, () {
    if (outcome.isCompleted || !navigator.mounted) return;
    dropShield();
    dialogClosed = showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => OpenProgressDialog(
        name: name,
        progress: progress,
        done: outcome.future,
        onCancel: cancel,
        slowAfter: slowAfter,
        askAgainAfter: askAgainAfter,
      ),
    );
  });

  try {
    final result = await outcome.future;
    showTimer.cancel();
    // The dialog closes itself when [outcome] completes; wait for it to be
    // gone so the next screen is pushed on the screen below.
    await dialogClosed;
    switch (result) {
      case _Value<T>(:final value):
        return value;
      case _Cancelled<T>():
        return null;
      case _Error<T>(:final error, :final stack):
        if (error is OpenCancelled) return null;
        Error.throwWithStackTrace(error, stack);
    }
  } finally {
    dropShield();
    _opening = false;
  }
}

sealed class _Outcome<T> {
  const _Outcome();
  const factory _Outcome.value(T value) = _Value<T>;
  const factory _Outcome.cancelled() = _Cancelled<T>;
  const factory _Outcome.error(Object error, StackTrace stack) = _Error<T>;
}

final class _Value<T> extends _Outcome<T> {
  const _Value(this.value);
  final T value;
}

final class _Cancelled<T> extends _Outcome<T> {
  const _Cancelled();
}

final class _Error<T> extends _Outcome<T> {
  const _Error(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}

/// The dialog shown while a document opens. Public for widget tests.
class OpenProgressDialog extends StatefulWidget {
  const OpenProgressDialog({
    super.key,
    required this.name,
    required this.progress,
    required this.done,
    required this.onCancel,
    this.slowAfter = const Duration(seconds: 10),
    this.askAgainAfter = const Duration(seconds: 20),
  });

  final String name;
  final OpenProgress progress;

  /// Completes when opening ends in any way; the dialog then closes itself.
  final Future<Object?> done;
  final VoidCallback onCancel;
  final Duration slowAfter;
  final Duration askAgainAfter;

  @override
  State<OpenProgressDialog> createState() => _OpenProgressDialogState();
}

class _OpenProgressDialogState extends State<OpenProgressDialog> {
  static const _tick = Duration(milliseconds: 250);
  late final Timer _ticker;
  late Duration _askAt = widget.slowAfter;

  /// Time spent opening while the dialog is up, not counting time waiting
  /// for the user.
  Duration _elapsed = Duration.zero;
  bool _slow = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.done.whenComplete(_close);
    // Counts in small steps so the count can pause while the user types a
    // password; one Timer for the whole wait could not.
    _ticker = Timer.periodic(_tick, (_) {
      if (widget.progress.waitingForUser) return;
      _elapsed += _tick;
      if (!_slow && _elapsed >= _askAt) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  void _cancel() {
    widget.onCancel();
    _close();
  }

  void _wait() => setState(() {
    _slow = false;
    _askAt = _elapsed + widget.askAgainAfter;
  });

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final motion = Motion.of(context);
    final text = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.progress.waiting,
        builder: (context, waiting, dialog) => Offstage(offstage: waiting, child: dialog),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(_slow ? LumaIcons.hourglass : LumaIcons.file, color: _slow ? colors.warning : colors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _slow ? 'Taking too long' : 'Opening document',
                        style: text.titleMedium,
                        semanticsLabel: _slow ? 'Opening is taking too long' : 'Opening document',
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('open-progress-close'),
                      tooltip: 'Cancel opening',
                      icon: const Icon(LumaIcons.close),
                      onPressed: _cancel,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ValueListenableBuilder<String>(
                        valueListenable: widget.progress.name,
                        builder: (context, name, _) => Text(
                          name.isEmpty ? widget.name : name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: colors.muted),
                        ),
                      ),
                      AnimatedSize(
                        duration: motion.duration(const Duration(milliseconds: 200)),
                        child: _slow
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'This document is taking too long to open. It may be very large or damaged. '
                                  'You can wait or cancel.',
                                  style: text.bodyMedium,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<OpenStatus>(
                        valueListenable: widget.progress.status,
                        builder: (context, status, _) {
                          final fraction = status.fraction;
                          final detail = status.detail;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: fraction ?? (motion.animates ? null : 0),
                                  minHeight: 6,
                                  semanticsLabel: 'Opening progress',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: Text(status.stage, style: text.bodySmall)),
                                  if (detail != null) Text(detail, style: text.bodySmall),
                                  if (fraction != null) ...[
                                    const SizedBox(width: 8),
                                    Text('${(fraction * 100).round()}%', style: text.bodySmall),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: const ValueKey('open-progress-cancel'),
                            onPressed: _cancel,
                            child: const Text('Cancel'),
                          ),
                          if (_slow) ...[
                            const SizedBox(width: 8),
                            FilledButton(
                              key: const ValueKey('open-progress-wait'),
                              onPressed: _wait,
                              child: const Text('Wait'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows why a document could not be opened, as a dialog the user has to
/// close, so the reason is not missed the way a snackbar can be.
Future<void> showOpenError(BuildContext context, {required String title, required String message}) => showDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (context) => AlertDialog(
    icon: Icon(LumaIcons.error, color: LumaColors.of(context).danger),
    title: Text(title),
    content: Text(message),
    actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
  ),
);
