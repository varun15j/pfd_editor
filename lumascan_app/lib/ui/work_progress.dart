import 'dart:async';

import 'package:flutter/material.dart';

/// Progress of a long job (making a text PDF or Word file), for
/// [runWithProgress]: how many pages are done, and whether the user stopped.
class WorkProgress {
  final status = ValueNotifier<(int done, int total)>((0, 0));
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void report(int done, int total) {
    if (!_cancelled) status.value = (done, total);
  }
}

/// Runs [task] behind a dialog that shows [title], "Page 3 of 35" with a
/// bar, and a Cancel button (the back button cancels too). Returns the
/// task's value, or null when the user cancelled; a task that still
/// finishes after that has its value dropped. Other errors are rethrown.
Future<T?> runWithProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(WorkProgress progress) task,
  String unit = 'Page',
}) async {
  final progress = WorkProgress();
  final navigator = Navigator.of(context, rootNavigator: true);
  final work = Future<T>.sync(() => task(progress));
  final dialog = showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => WorkProgressDialog(
      title: title,
      unit: unit,
      progress: progress,
      done: work,
      onCancel: () => progress._cancelled = true,
    ),
  );
  try {
    final value = await work;
    await dialog;
    return progress.cancelled ? null : value;
  } on Object {
    await dialog;
    if (progress.cancelled) return null;
    rethrow;
  }
}

/// The dialog shown by [runWithProgress]. Public for widget tests.
class WorkProgressDialog extends StatefulWidget {
  const WorkProgressDialog({
    super.key,
    required this.title,
    required this.progress,
    required this.done,
    required this.onCancel,
    this.unit = 'Page',
  });

  final String title;
  final String unit;
  final WorkProgress progress;
  final Future<Object?> done;
  final VoidCallback onCancel;

  @override
  State<WorkProgressDialog> createState() => _WorkProgressDialogState();
}

class _WorkProgressDialogState extends State<WorkProgressDialog> {
  var _closed = false;

  @override
  void initState() {
    super.initState();
    // Closes itself when the work ends, whether it worked or not.
    widget.done.then<void>((_) => _close(), onError: (Object _) => _close());
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        title: Text(widget.title),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: widget.progress.status,
          builder: (context, status, _) {
            final (done, total) = status;
            final fraction = total == 0 ? null : (done / total).clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: fraction, semanticsLabel: '${widget.title} progress'),
                const SizedBox(height: 12),
                Text(
                  total == 0 ? 'Getting ready…' : '${widget.unit} ${(done + 1).clamp(1, total)} of $total',
                  style: text.bodyMedium,
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(key: const ValueKey('work-progress-cancel'), onPressed: _cancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
