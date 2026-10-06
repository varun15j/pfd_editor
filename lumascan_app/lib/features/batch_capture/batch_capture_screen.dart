import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../domain/scanner_service.dart';
import '../batch_edit/batch_completion.dart';
import '../batch_edit/batch_review_screen.dart';
import '../capture/photo_import_screen.dart';
import '../export/export_sheet.dart';
import '../pages/scan_controller.dart';
import 'batch_camera.dart';

/// Opens the camera. Pages join the current draft as they are taken. When
/// the camera closes with pages taken, the draft opens; [openDraftAfter] is
/// false when the caller is already inside the draft. When camera access is
/// blocked and photo import is picked instead, that runs here.
Future<void> openBatchCapture(BuildContext context, WidgetRef ref, {bool openDraftAfter = true}) async {
  final before = ref.read(scanControllerProvider).pages;
  final exit = await Navigator.of(context).push<Object>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => BatchCaptureScreen(returnToReview: !openDraftAfter)),
  );
  if (!context.mounted) return;
  if (exit == _importPhotosInstead) {
    final added = await importPhotosFlow(context, ref);
    if (added && openDraftAfter && context.mounted) openDraft(context);
    return;
  }
  final taken = !identical(ref.read(scanControllerProvider).pages, before);
  if (openDraftAfter && (taken || exit != null)) openDraft(context);
  if (exit == BatchOutcome.export && context.mounted) await showExportSheet(context);
}

/// What the camera closes with when photo import is picked instead.
const _importPhotosInstead = #importPhotos;

/// The camera (iOS flow prototype, screen 02 "Camera preview"; BE-01). It
/// stays open between shots: each press of the shutter saves a page to the
/// draft and the camera is ready for the next one straight away, with no
/// preview or "Add page" step in between.
///
/// Over the preview: the guidance chip, camera settings (•••) and the Batch,
/// Flash and Auto crop quick controls. Below it: the page count, the capture
/// mode, and the thumbnail (opens Captured photos, where a page can be
/// retaken and the batch reviewed), the shutter, and the cross that discards
/// the photos taken in this visit.
class BatchCaptureScreen extends ConsumerStatefulWidget {
  const BatchCaptureScreen({super.key, this.returnToReview = false});

  /// Opened from Batch Review: Review goes back to it instead of opening
  /// another one.
  final bool returnToReview;

  @override
  ConsumerState<BatchCaptureScreen> createState() => _BatchCaptureScreenState();
}

enum _CameraStatus { opening, ready, blocked, failed }

class _BatchCaptureScreenState extends ConsumerState<BatchCaptureScreen> with WidgetsBindingObserver {
  /// Shutter presses made while a photo is being taken run right after it,
  /// up to this many, so quick taps are never lost.
  static const _maxQueuedShots = 2;

  late final BatchCamera _camera = ref.read(batchCameraProvider)();
  late final ScanController _controller = ref.read(scanControllerProvider.notifier);

  /// Whether the draft had no pages when the camera opened. Discarding then
  /// deletes the photo files too; otherwise only this visit's pages leave.
  bool _startedEmpty = true;

  _CameraStatus _status = _CameraStatus.opening;
  bool _blockedPermanently = false;
  String? _failure;

  /// Pages taken in this visit, in order. Retakes keep their place.
  final List<ScanPage> _taken = [];

  /// Photos taken but not yet in the draft.
  int _saving = 0;
  Future<void> _saves = Future.value();
  bool _shooting = false;
  int _queuedShots = 0;

  /// The page the next shot replaces, while a retake is on.
  String? _retakeId;

  /// Batch mode: keep capturing without review. Off, Batch Review opens
  /// after every photo.
  bool _batch = true;
  bool _torch = false;
  bool _autoCrop = true;
  bool _grid = false;

  /// Coverage of the camera by another screen or the app going to the
  /// background; the camera is released meanwhile.
  bool _covered = false;

  /// Bumped on every shot to replay the white capture flash.
  int _flashSerial = 0;

  /// Short confirmation after each shot, such as "Page 4 saved".
  String? _toast;
  int _toastSerial = 0;
  Timer? _toastTimer;

  /// Finds the page in each new photo, one photo at a time, in the background.
  Future<void> _cropIo = Future.value();

  @override
  void initState() {
    super.initState();
    _startedEmpty = ref.read(scanControllerProvider).pages.isEmpty;
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastTimer?.cancel();
    unawaited(_camera.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_status != _CameraStatus.ready) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_camera.pause());
    } else if (state == AppLifecycleState.resumed && !_covered) {
      _resume();
    }
  }

  Future<void> _open() async {
    setState(() {
      _status = _CameraStatus.opening;
      _failure = null;
    });
    try {
      await _camera.open();
      if (_torch) await _camera.setTorch(true);
      if (mounted) setState(() => _status = _CameraStatus.ready);
    } on ScannerPermissionDenied catch (e) {
      if (mounted) {
        setState(() {
          _status = _CameraStatus.blocked;
          _blockedPermanently = e.permanently;
        });
      }
    } on ScannerFailure catch (e) {
      if (mounted) {
        setState(() {
          _status = _CameraStatus.failed;
          _failure = e.message;
        });
      }
    }
  }

  Future<void> _resume() async {
    try {
      await _camera.resume();
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _status = _CameraStatus.failed;
          _failure = e is ScannerFailure ? e.message : '$e';
        });
      }
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _shoot() async {
    if (_status != _CameraStatus.ready || _covered || !_camera.isReady) return;
    if (_shooting) {
      if (_batch && _queuedShots < _maxQueuedShots) _queuedShots++;
      return;
    }
    final replacing = _retakeId;
    setState(() {
      _shooting = true;
      _flashSerial++;
    });
    try {
      final path = await _camera.takePicture();
      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      setState(() {
        _saving++;
        if (replacing != null) _retakeId = null;
      });
      final saved = _save(path, replacing);
      _saves = _saves.then((_) => saved);
      if (!_batch) unawaited(saved.then((page) => page != null && mounted ? _review() : null));
    } on ScannerFailure catch (e) {
      _queuedShots = 0;
      if (mounted) _showToast('Photo not taken: ${e.message}');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
    if (_queuedShots > 0 && mounted) {
      _queuedShots--;
      unawaited(_shoot());
    }
  }

  Future<ScanPage?> _save(String path, String? replacing) async {
    final page = await _controller.addCapture(path, replacing: replacing);
    if (!mounted) {
      if (page != null && _autoCrop) _findPage(page);
      return page;
    }
    setState(() {
      _saving--;
      if (page == null) return;
      final at = replacing == null ? -1 : _taken.indexWhere((p) => p.id == replacing);
      if (at >= 0) {
        _taken[at] = page;
      } else if (replacing == null) {
        _taken.add(page);
      }
    });
    if (page == null) {
      _showToast('That photo could not be saved. Take it again.');
      return null;
    }
    final number = ref.read(scanControllerProvider).pages.indexWhere((p) => p.id == page.id) + 1;
    _showToast(replacing == null ? 'Page $number captured' : 'Page $number replaced');
    if (_autoCrop) _findPage(page);
    return page;
  }

  /// Crops the new page to the page found in it, without holding up the
  /// camera. Pages where none is found stay whole for a manual crop.
  void _findPage(ScanPage page) {
    final analyzer = ref.read(photoAnalyzerProvider);
    final controller = _controller;
    _cropIo = _cropIo.then((_) async {
      try {
        final quad = await analyzer.analyze(page.originalPath);
        if (quad != null) controller.applyDetectedCrop(page.id, quad);
      } catch (e) {
        debugPrint('Page detection failed: $e');
      }
    });
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() {
      _toast = message;
      _toastSerial++;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _retake(String pageId) => setState(() => _retakeId = pageId);

  void _cancelRetake() => setState(() => _retakeId = null);

  Future<void> _setTorch(bool on) async {
    if (!_camera.hasTorch || _status != _CameraStatus.ready) return;
    setState(() => _torch = on);
    await _camera.setTorch(on);
  }

  void _setOption(_Option option, bool on) {
    switch (option) {
      case _Option.batch:
        setState(() => _batch = on);
      case _Option.flash:
        unawaited(_setTorch(on));
      case _Option.auto:
        setState(() => _autoCrop = on);
      case _Option.grid:
        setState(() => _grid = on);
    }
  }

  bool _option(_Option option) => switch (option) {
    _Option.batch => _batch,
    _Option.flash => _torch,
    _Option.auto => _autoCrop,
    _Option.grid => _grid,
  };

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheet) => _SettingsSheet(
          value: _option,
          flashAvailable: _status == _CameraStatus.ready && _camera.hasTorch,
          onChanged: (option, on) {
            _setOption(option, on);
            setSheet(() {});
          },
        ),
      ),
    );
  }

  /// Captured photos: every page so far, numbered. Tapping one retakes it.
  Future<void> _openPhotos() async {
    final choice = await showModalBottomSheet<_PhotosChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CapturedPhotosSheet(),
    );
    if (!mounted || choice == null) return;
    if (choice.review) {
      await _review();
    } else if (choice.retakeId != null) {
      _retake(choice.retakeId!);
    }
  }

  /// Batch Review over the camera. The camera is released while it is open
  /// and taken back on return, unless the user finished there.
  Future<void> _review() async {
    if (_covered) return;
    if (widget.returnToReview) return _finish();
    if (ref.read(scanControllerProvider).pages.isEmpty) return;
    setState(() {
      _covered = true;
      _retakeId = null;
    });
    await _camera.pause();
    if (!mounted) return;
    final outcome = await Navigator.of(context)
        .push<BatchOutcome>(MaterialPageRoute(builder: (_) => const BatchReviewScreen(fromCamera: true)));
    if (!mounted) return;
    if (outcome == BatchOutcome.review || outcome == BatchOutcome.export) {
      Navigator.of(context).pop(outcome);
      return;
    }
    _covered = false;
    // Pages deleted in Batch Review leave this visit's list too.
    final ids = {for (final p in ref.read(scanControllerProvider).pages) p.id};
    _taken.removeWhere((p) => !ids.contains(p.id));
    await _resume();
  }

  /// Leaves keeping every photo.
  void _finish() => Navigator.of(context).pop(_taken.isEmpty ? null : BatchOutcome.review);

  /// The cross: leaves, and when photos were taken in this visit, asks
  /// first and then removes them.
  Future<void> _discard() async {
    if (_taken.isEmpty && _saving == 0) {
      Navigator.of(context).pop();
      return;
    }
    final sure = await showDialog<bool>(context: context, builder: (_) => const _DiscardDialog());
    if (sure != true || !mounted) return;
    setState(() => _covered = true);
    await _saves;
    if (_startedEmpty) {
      await _controller.clear();
    } else {
      _controller.removePages({for (final p in _taken) p.id});
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _permissionHelp() async {
    if (_blockedPermanently) {
      await openAppSettings();
      return;
    }
    await _open();
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(scanControllerProvider.select((s) => s.pages));
    final last = _taken.isEmpty ? (pages.isEmpty ? null : pages.last) : _taken.last;
    final retakeNumber = _retakeId == null ? 0 : pages.indexWhere((p) => p.id == _retakeId) + 1;
    final ready = _status == _CameraStatus.ready;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_discard());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _preview(),
                    if (_grid && ready) const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
                    if (ready) IgnorePointer(child: _CaptureFlash(serial: _flashSerial)),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 48),
                                Expanded(
                                  child: Center(
                                    child: _retakeId != null
                                        ? const SizedBox.shrink()
                                        : _Chip(text: ready ? 'Tap the shutter for each page' : 'Starting camera'),
                                  ),
                                ),
                                _RoundButton(
                                  tooltip: 'Camera settings',
                                  icon: Icons.more_horiz,
                                  onPressed: _openSettings,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickToggle(
                                    icon: Icons.burst_mode_outlined,
                                    title: 'Batch',
                                    on: _batch,
                                    onChanged: (on) => _setOption(_Option.batch, on),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _QuickToggle(
                                    icon: _torch ? Icons.flash_on : Icons.flash_off,
                                    title: 'Flash',
                                    on: _torch,
                                    onChanged: ready && _camera.hasTorch ? (on) => _setOption(_Option.flash, on) : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _QuickToggle(
                                    icon: Icons.crop_free,
                                    title: 'Auto crop',
                                    on: _autoCrop,
                                    onChanged: (on) => _setOption(_Option.auto, on),
                                  ),
                                ),
                              ],
                            ),
                            if (_retakeId != null) ...[
                              const SizedBox(height: 10),
                              _Banner(
                                icon: Icons.replay,
                                text: 'Retaking page $retakeNumber. Take the new photo.',
                                action: 'Cancel',
                                onAction: _cancelRetake,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: _toast == null
                              ? const SizedBox.shrink()
                              : _Toast(key: ValueKey(_toastSerial), text: _toast!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _ControlPanel(
                count: pages.length,
                showCount: _batch,
                lastPage: last,
                saving: _saving > 0,
                shooting: _shooting,
                canShoot: ready && !_covered,
                retaking: _retakeId != null,
                onShoot: _shoot,
                onPhotos: _openPhotos,
                onDiscard: _discard,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() => switch (_status) {
    _CameraStatus.opening => const Center(child: CircularProgressIndicator(color: Colors.white)),
    _CameraStatus.ready =>
      _covered || !_camera.isReady ? const SizedBox.expand() : ClipRect(child: Center(child: _camera.buildPreview())),
    _CameraStatus.blocked => _CameraMessage(
      icon: Icons.no_photography_outlined,
      title: 'Camera access needed',
      body: _blockedPermanently
          ? 'Camera access is turned off. Turn it on in Settings to scan pages. Pages stay on this device.'
          : 'Allow camera access to scan pages. Pages stay on this device.',
      action: _blockedPermanently ? 'Open Settings' : 'Try again',
      onAction: _permissionHelp,
      secondary: 'Import photos',
      onSecondary: () => Navigator.of(context).pop(_importPhotosInstead),
    ),
    _CameraStatus.failed => _CameraMessage(
      icon: Icons.error_outline,
      title: 'The camera could not start',
      body: _failure ?? 'Try again.',
      action: 'Try again',
      onAction: _open,
    ),
  };
}

enum _Option { batch, flash, auto, grid }

/// What was picked in Captured photos.
class _PhotosChoice {
  const _PhotosChoice.review() : review = true, retakeId = null;
  const _PhotosChoice.retake(String this.retakeId) : review = false;

  final bool review;
  final String? retakeId;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.72),
        foregroundColor: Colors.white,
        fixedSize: const Size(48, 48),
      ),
      icon: Icon(icon),
    );
  }
}

/// One of the Batch, Flash and Auto crop chips over the preview. They stay
/// in step with the same switches in Camera settings.
class _QuickToggle extends StatelessWidget {
  const _QuickToggle({required this.icon, required this.title, required this.on, required this.onChanged});

  final IconData icon;
  final String title;
  final bool on;

  /// Null when the control is not available, such as Flash without a torch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    final enabled = onChanged != null;
    final state = !enabled ? 'Not available' : (on ? 'On' : 'Off');
    return Semantics(
      button: true,
      toggled: on,
      enabled: enabled,
      label: '$title $state',
      excludeSemantics: true,
      child: Material(
        color: on && enabled ? colors.accent.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.62),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: on && enabled ? colors.accent : Colors.white24),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!on) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: enabled ? Colors.white : Colors.white38),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        enabled ? state : 'N/A',
                        style: TextStyle(color: enabled ? Colors.white70 : Colors.white38, fontSize: 11),
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

/// Count, capture mode, then thumbnail, shutter and discard, as in the
/// prototype. The shutter stays enabled while the previous page is saved,
/// so pages can be taken back to back.
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.count,
    required this.showCount,
    required this.lastPage,
    required this.saving,
    required this.shooting,
    required this.canShoot,
    required this.retaking,
    required this.onShoot,
    required this.onPhotos,
    required this.onDiscard,
  });

  final int count;
  final bool showCount;
  final ScanPage? lastPage;
  final bool saving;
  final bool shooting;
  final bool canShoot;
  final bool retaking;
  final VoidCallback onShoot;
  final VoidCallback onPhotos;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: showCount ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: _CountPill(count: count),
                ),
              ),
              const SizedBox(height: 10),
              const _ModeStrip(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        label: count == 0
                            ? 'No captured photos yet'
                            : 'Open preview of $count captured photo${count == 1 ? '' : 's'}',
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onPhotos,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: _Thumbnail(page: lastPage, count: count, saving: saving),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Shutter(canShoot: canShoot, shooting: shooting, retaking: retaking, onShoot: onShoot),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Semantics(
                        button: true,
                        label: 'Discard all captured photos and changes',
                        excludeSemantics: true,
                        child: IconButton(
                          onPressed: onDiscard,
                          style: IconButton.styleFrom(
                            backgroundColor: colors.danger,
                            foregroundColor: Colors.white,
                            fixedSize: const Size(56, 56),
                          ),
                          icon: const Icon(Icons.close, size: 28),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    return Semantics(
      liveRegion: true,
      label: '$count page${count == 1 ? '' : 's'} captured',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(color: const Color(0xFF3C4648), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Container(
                key: ValueKey(count),
                constraints: const BoxConstraints(minWidth: 26),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onAccent, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'pages captured',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The capture mode strip. Docs is the only mode built so far; Book, Text,
/// OCR Doc, QR and Photo from the prototype wait on the custom camera work.
class _ModeStrip extends StatelessWidget {
  const _ModeStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFF3C4648), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Semantics(
            selected: true,
            label: 'Docs capture mode',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Text(
                'Docs',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.canShoot, required this.shooting, required this.retaking, required this.onShoot});

  final bool canShoot;
  final bool shooting;
  final bool retaking;
  final VoidCallback onShoot;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Semantics(
      button: true,
      enabled: canShoot,
      label: retaking ? 'Take the new photo' : 'Take photo',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: canShoot ? onShoot : null,
        child: AnimatedScale(
          scale: shooting ? 0.86 : 1,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: retaking ? colors.warning : Colors.white,
                border: Border.all(color: canShoot ? colors.ink : colors.line, width: 3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The latest page, with the page count. Drawn from a small decode of the
/// photo, so it appears straight after the shot.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.page, required this.count, required this.saving});

  final ScanPage? page;
  final int count;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: page == null
                  ? Icon(Icons.description_outlined, color: colors.muted)
                  : Image.file(
                      File(page!.originalPath),
                      key: ValueKey(page!.id),
                      fit: BoxFit.cover,
                      cacheWidth: (52 * dpr).round(),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Icon(Icons.description_outlined, color: colors.muted),
                    ),
            ),
          ),
          if (saving)
            Positioned.fill(
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.accent),
                ),
              ),
            ),
          if (count > 0)
            Positioned(
              bottom: -6,
              right: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: LumaColors.dark.accent,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: LumaColors.dark.onAccent, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The white flash over the preview when a photo is taken.
class _CaptureFlash extends StatelessWidget {
  const _CaptureFlash({required this.serial});

  final int serial;

  @override
  Widget build(BuildContext context) {
    if (serial == 0 || MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      key: ValueKey(serial),
      tween: Tween(begin: 0.6, end: 0),
      duration: const Duration(milliseconds: 220),
      builder: (_, value, _) => ColoredBox(color: Colors.white.withValues(alpha: value)),
    );
  }
}

/// The 3 × 3 alignment grid.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.value, required this.flashAvailable, required this.onChanged});

  final bool Function(_Option) value;
  final bool flashAvailable;
  final void Function(_Option, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    Widget row(_Option option, IconData icon, String title, String subtitle, {bool enabled = true}) => SwitchListTile(
      value: value(option),
      onChanged: enabled ? (on) => onChanged(option, on) : null,
      secondary: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: colors.accentSoft, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: colors.accent),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Camera settings', style: Theme.of(context).textTheme.titleLarge),
                        Text('Capture options only', style: TextStyle(color: colors.muted)),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            row(_Option.batch, Icons.burst_mode_outlined, 'Batch mode', 'Keep capturing without review'),
            row(
              _Option.flash,
              Icons.flash_on,
              'Flashlight',
              flashAvailable ? 'Continuous light while scanning' : 'Not available on this camera',
              enabled: flashAvailable,
            ),
            row(_Option.auto, Icons.crop_free, 'Auto crop', 'Find the page edges in each photo'),
            row(_Option.grid, Icons.grid_3x3, 'Alignment grid', 'Show a 3 × 3 guide'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Captured photos: every page so far, numbered, with Review all and
/// Continue scanning. Tapping a page retakes it.
class _CapturedPhotosSheet extends ConsumerWidget {
  const _CapturedPhotosSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(scanControllerProvider.select((s) => s.pages));
    final colors = LumaColors.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final count = pages.length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Captured photos', style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          count == 0
                              ? 'No captured photos yet'
                              : '$count page${count == 1 ? '' : 's'} in this scan · tap one to retake it',
                          style: TextStyle(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close captured photos',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (count > 0)
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    final page = pages[i];
                    return Semantics(
                      button: true,
                      label: 'Retake page ${i + 1}',
                      excludeSemantics: true,
                      child: Material(
                        color: colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, _PhotosChoice.retake(page.id)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Image.file(
                                  File(page.originalPath),
                                  fit: BoxFit.contain,
                                  cacheWidth: (110 * dpr).round(),
                                  errorBuilder: (_, _, _) => Icon(Icons.description_outlined, color: colors.muted),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(color: colors.ink, borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(color: colors.surface, fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: FilledButton(
                onPressed: count == 0 ? null : () => Navigator.pop(context, const _PhotosChoice.review()),
                child: Text(count == 0 ? 'Review all pages' : 'Review all $count page${count == 1 ? '' : 's'}'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Continue scanning')),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscardDialog extends StatelessWidget {
  const _DiscardDialog();

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return AlertDialog(
      icon: Icon(Icons.close, color: colors.danger),
      title: const Text('Discard the photos?'),
      content: const Text(
        'All photos captured now and their changes will be removed and cannot be restored.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.danger, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard photos'),
        ),
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep photos')),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 18, color: LumaColors.dark.success),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(color: colors.warning, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.black87),
              onPressed: onAction,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.secondary,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white70),
            const SizedBox(height: Space.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Space.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: Space.lg),
            FilledButton(onPressed: onAction, child: Text(action)),
            if (secondary != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onSecondary,
                child: Text(secondary!),
              ),
          ],
        ),
      ),
    );
  }
}
