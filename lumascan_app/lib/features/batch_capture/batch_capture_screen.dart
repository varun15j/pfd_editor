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
import '../export/export_sheet.dart';
import '../pages/scan_controller.dart';
import 'batch_camera.dart';

/// Opens Batch capture. Pages join the current draft as they are taken. When
/// the camera closes with pages taken, the draft opens; [openDraftAfter] is
/// false when the caller is already inside the draft.
Future<void> openBatchCapture(BuildContext context, WidgetRef ref, {bool openDraftAfter = true}) async {
  final before = ref.read(scanControllerProvider).pages.length;
  final exit = await Navigator.of(context).push<BatchOutcome>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => BatchCaptureScreen(returnToReview: !openDraftAfter)),
  );
  if (!context.mounted) return;
  final taken = ref.read(scanControllerProvider).pages.length != before;
  if (openDraftAfter && (taken || exit != null)) openDraft(context);
  if (exit == BatchOutcome.export && context.mounted) await showExportSheet(context);
}

/// Batch capture (BE-01): a live camera that stays open between shots. Each
/// press of the shutter saves a page to the draft and the camera is ready
/// for the next one straight away, with no review step in between. Retake
/// swaps the last photo for the next one. The thumbnail and Review open
/// Batch Review, and the camera picks up where it left off on return.
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

  _CameraStatus _status = _CameraStatus.opening;
  bool _blockedPermanently = false;
  String? _failure;

  /// Pages taken in this visit, in order. Retakes keep their place.
  final List<ScanPage> _taken = [];

  /// Photos taken but not yet in the draft.
  int _saving = 0;
  bool _shooting = false;
  int _queuedShots = 0;

  /// The page the next shot replaces, while Retake is on.
  String? _retakeId;

  bool _torch = false;
  bool _autoCrop = true;

  /// Coverage of the camera by another screen or the app going to the
  /// background; the camera is released meanwhile.
  bool _covered = false;

  /// Short confirmation after each shot, such as "Page 4 saved".
  String? _toast;
  int _toastSerial = 0;
  Timer? _toastTimer;

  /// Finds the page in each new photo, one photo at a time, in the background.
  Future<void> _cropIo = Future.value();

  @override
  void initState() {
    super.initState();
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
      if (_queuedShots < _maxQueuedShots) _queuedShots++;
      return;
    }
    final replacing = _retakeId;
    setState(() => _shooting = true);
    try {
      final path = await _camera.takePicture();
      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      setState(() {
        _saving++;
        if (replacing != null) _retakeId = null;
      });
      unawaited(_save(path, replacing));
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

  Future<void> _save(String path, String? replacing) async {
    final page = await _controller.addCapture(path, replacing: replacing);
    if (!mounted) {
      if (page != null && _autoCrop) _findPage(page);
      return;
    }
    setState(() {
      _saving--;
      if (page == null) return;
      final at = replacing == null ? -1 : _taken.indexWhere((p) => p.id == replacing);
      if (at < 0) {
        _taken.add(page);
      } else {
        _taken[at] = page;
      }
    });
    if (page == null) {
      _showToast('That photo could not be saved. Take it again.');
      return;
    }
    final number = ref.read(scanControllerProvider).pages.indexWhere((p) => p.id == page.id) + 1;
    _showToast(replacing == null ? 'Page $number saved' : 'Page $number replaced');
    if (_autoCrop) _findPage(page);
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

  void _toggleRetake() {
    if (_taken.isEmpty) return;
    setState(() => _retakeId = _retakeId == null ? _taken.last.id : null);
  }

  Future<void> _toggleTorch() async {
    final on = !_torch;
    setState(() => _torch = on);
    await _camera.setTorch(on);
  }

  /// Batch Review over the camera. The camera is released while it is open
  /// and taken back on return, unless the user finished there.
  Future<void> _review() async {
    if (widget.returnToReview) return _close();
    if (ref.read(scanControllerProvider).pages.isEmpty) return;
    setState(() {
      _covered = true;
      _retakeId = null;
    });
    await _camera.pause();
    if (!mounted) return;
    final outcome = await Navigator.of(
      context,
    ).push<BatchOutcome>(MaterialPageRoute(builder: (_) => const BatchReviewScreen(fromCamera: true)));
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

  void _close() => Navigator.of(context).pop(_taken.isEmpty ? null : BatchOutcome.review);

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
    final last = _taken.isEmpty ? null : _taken.last;
    final retakeNumber = _retakeId == null ? 0 : pages.indexWhere((p) => p.id == _retakeId) + 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                onClose: _close,
                torch: _torch,
                showTorch: _status == _CameraStatus.ready && _camera.hasTorch,
                onTorch: _toggleTorch,
                autoCrop: _autoCrop,
                onAutoCrop: () => setState(() => _autoCrop = !_autoCrop),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _preview(),
                    if (_retakeId != null)
                      Positioned(
                        top: 12,
                        left: 16,
                        right: 16,
                        child: _Banner(
                          icon: Icons.replay,
                          text: 'Retaking page $retakeNumber. Take the new photo.',
                          action: 'Cancel',
                          onAction: _toggleRetake,
                        ),
                      ),
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
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
              _BottomBar(
                count: pages.length,
                lastPage: last,
                saving: _saving > 0,
                shooting: _shooting,
                canShoot: _status == _CameraStatus.ready && !_covered,
                retaking: _retakeId != null,
                canRetake: _taken.isNotEmpty && _saving == 0,
                onShoot: _shoot,
                onRetake: _toggleRetake,
                onReview: pages.isEmpty ? null : _review,
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
      _covered || !_camera.isReady
          ? const SizedBox.expand()
          : ClipRect(child: Center(child: _camera.buildPreview())),
    _CameraStatus.blocked => _CameraMessage(
      icon: Icons.no_photography_outlined,
      title: 'Camera access needed',
      body: _blockedPermanently
          ? 'Camera access is turned off. Turn it on in Settings to scan pages. Pages stay on this device.'
          : 'Allow camera access to scan pages. Pages stay on this device.',
      action: _blockedPermanently ? 'Open Settings' : 'Try again',
      onAction: _permissionHelp,
    ),
    _CameraStatus.failed => _CameraMessage(
      icon: Icons.error_outline,
      title: 'The camera could not start',
      body: _failure ?? 'Try again, or use Scan document instead.',
      action: 'Try again',
      onAction: _open,
    ),
  };
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onClose,
    required this.torch,
    required this.showTorch,
    required this.onTorch,
    required this.autoCrop,
    required this.onAutoCrop,
  });

  final VoidCallback onClose;
  final bool torch;
  final bool showTorch;
  final VoidCallback onTorch;
  final bool autoCrop;
  final VoidCallback onAutoCrop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close camera',
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
          const Expanded(
            child: Text(
              'Batch scan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          Semantics(
            toggled: autoCrop,
            child: IconButton(
              tooltip: autoCrop ? 'Auto crop on' : 'Auto crop off',
              color: Colors.white,
              icon: Icon(autoCrop ? Icons.crop_free : Icons.crop_original),
              onPressed: onAutoCrop,
            ),
          ),
          if (showTorch)
            Semantics(
              toggled: torch,
              child: IconButton(
                tooltip: torch ? 'Torch on' : 'Torch off',
                color: Colors.white,
                icon: Icon(torch ? Icons.flash_on : Icons.flash_off),
                onPressed: onTorch,
              ),
            ),
        ],
      ),
    );
  }
}

/// Thumbnail and count, shutter, and Retake. The shutter stays enabled
/// while the previous page is saved, so pages can be taken back to back.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.count,
    required this.lastPage,
    required this.saving,
    required this.shooting,
    required this.canShoot,
    required this.retaking,
    required this.canRetake,
    required this.onShoot,
    required this.onRetake,
    required this.onReview,
  });

  final int count;
  final ScanPage? lastPage;
  final bool saving;
  final bool shooting;
  final bool canShoot;
  final bool retaking;
  final bool canRetake;
  final VoidCallback onShoot;
  final VoidCallback onRetake;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Thumbnail(page: lastPage, count: count, saving: saving, onTap: onReview),
            ),
          ),
          Semantics(
            button: true,
            enabled: canShoot,
            label: retaking ? 'Take the new photo' : 'Take photo',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: canShoot ? onShoot : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 76,
                height: 76,
                padding: EdgeInsets.all(shooting ? 9 : 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: canShoot ? Colors.white : Colors.white38, width: 4),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !canShoot
                        ? Colors.white24
                        : retaking
                        ? colors.warning
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                      minimumSize: const Size(48, 44),
                    ),
                    onPressed: canRetake ? onRetake : null,
                    icon: Icon(retaking ? Icons.close : Icons.replay, size: 20),
                    label: Text(retaking ? 'Cancel' : 'Retake'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white38,
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: onReview,
                    child: const Text('Review'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The latest page, with the page count. Drawn from a small decode of the
/// photo, so it appears straight after the shot.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.page, required this.count, required this.saving, required this.onTap});

  final ScanPage? page;
  final int count;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.dark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      button: onTap != null,
      label: count == 0 ? 'No pages yet' : '$count page${count == 1 ? '' : 's'}. Open batch review',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white54),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: page == null
                      ? const Icon(Icons.description_outlined, color: Colors.white38)
                      : Image.file(
                          File(page!.originalPath),
                          key: ValueKey(page!.id),
                          fit: BoxFit.cover,
                          cacheWidth: (64 * dpr).round(),
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const Icon(Icons.description_outlined, color: Colors.white38),
                        ),
                ),
              ),
              if (saving)
                const Positioned.fill(
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    ),
                  ),
                ),
              if (count > 0)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onAccent, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
            Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
              child: Text(text, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
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
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
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
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: Space.lg),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
