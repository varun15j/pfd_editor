import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/id_copy.dart';
import '../../domain/models.dart';
import '../../domain/scanner_service.dart';
import '../batch_capture/batch_camera.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';
import 'id_card_review_screen.dart';
import 'id_card_session.dart';

/// The ID card camera (ID-05): a full-screen preview with a 3 × 3 grid, a
/// card-shaped guide marked by four green corners, the side being taken
/// over it, and only Close, the shutter and Import below. After the front
/// it asks for the back, with the front still in view; once every side is
/// taken the review opens.
///
/// With [retakeSide], only that side is taken again, in place of the old
/// one, and the screen closes.
class IdCardCaptureScreen extends ConsumerStatefulWidget {
  const IdCardCaptureScreen({super.key, this.retakeSide});

  final int? retakeSide;

  @override
  ConsumerState<IdCardCaptureScreen> createState() => _IdCardCaptureScreenState();
}

enum _Status { opening, ready, blocked, failed }

class _IdCardCaptureScreenState extends ConsumerState<IdCardCaptureScreen> with WidgetsBindingObserver {
  late final BatchCamera _camera = ref.read(batchCameraProvider)();
  _Status _status = _Status.opening;
  bool _blockedPermanently = false;
  String? _failure;
  bool _busy = false;
  String? _note;
  Timer? _noteTimer;

  /// The side the shutter takes now.
  late int _side = widget.retakeSide ?? ref.read(idCopyDraftProvider)?.nextSide ?? 0;

  /// After retaking the front from the back's camera, go back to the back.
  int? _returnTo;

  /// The guide, normalized to the preview, as last laid out.
  Rect _guide = const Rect.fromLTWH(0.1, 0.3, 0.8, 0.4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteTimer?.cancel();
    unawaited(_camera.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_status != _Status.ready) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_camera.pause());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_camera.resume().then((_) => mounted ? setState(() {}) : null));
    }
  }

  Future<void> _open() async {
    setState(() {
      _status = _Status.opening;
      _failure = null;
    });
    try {
      await _camera.open(resolution: ref.read(appSettingsProvider).captureResolution);
      if (mounted) setState(() => _status = _Status.ready);
    } on ScannerPermissionDenied catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.blocked;
          _blockedPermanently = e.permanently;
        });
      }
    } on ScannerFailure catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.failed;
          _failure = e.message;
        });
      }
    }
  }

  IdCopyDraft? get _draft => ref.read(idCopyDraftProvider);

  Future<void> _shoot() async {
    if (_busy || _status != _Status.ready || !_camera.isReady) return;
    setState(() => _busy = true);
    try {
      final path = await _camera.takePicture();
      unawaited(HapticFeedback.mediumImpact());
      await _addSide(path);
    } on ScannerFailure catch (e) {
      _toast('Photo not taken: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final photos = await ref.read(photoPickerProvider).pick();
    if (photos.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      // The picked photo stays where it is; the draft gets its own copy.
      final store = ref.read(pageStoreProvider);
      final copy = p.join((await store.renderDir).path, 'import_${store.newId()}${p.extension(photos.first.path)}');
      await File(photos.first.path).copy(copy);
      await _addSide(copy);
    } on FileSystemException {
      _toast('That photo could not be read. Pick another one.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts the photo at [path] in the draft as the current side, cropped to
  /// the card found in it, or to the guide when none is found, then moves on.
  Future<void> _addSide(String path) async {
    final draft = _draft;
    if (draft == null) return;
    final controller = ref.read(scanControllerProvider.notifier);
    final replacing = _side < draft.sideIds.length ? draft.sideIds[_side] : null;
    final page = await controller.addCapture(path, replacing: replacing);
    if (page == null) {
      _toast('That photo could not be saved. Take it again.');
      return;
    }
    controller.applyDetectedCrop(page.id, await _cropFor(page));
    ref.read(idCopyDraftProvider.notifier).update((d) => d.withSide(_side, page.id));
    if (!mounted) return;
    final next = ref.read(idCopyDraftProvider)!;
    if (widget.retakeSide != null) {
      Navigator.of(context).pop(true);
    } else if (_returnTo != null) {
      setState(() {
        _side = _returnTo!;
        _returnTo = null;
      });
    } else if (!next.complete) {
      setState(() => _side = next.nextSide);
      _toast('${next.type.sideName(0)} saved. Now the ${next.type.sideName(_side).toLowerCase()}.');
    } else {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const IdCardReviewScreen()),
      );
    }
  }

  Future<CropQuad> _cropFor(ScanPage page) async {
    final guide = CropQuad(
      NormPoint(_guide.left, _guide.top),
      NormPoint(_guide.right, _guide.top),
      NormPoint(_guide.right, _guide.bottom),
      NormPoint(_guide.left, _guide.bottom),
    );
    try {
      final found = await ref.read(photoAnalyzerProvider).analyze(page.originalPath);
      if (found != null && isCardLike(found, guide)) return found;
    } on Object {
      // Fall back to the guide.
    }
    return guide;
  }

  /// A short note over the bottom of the preview. Not a snack bar, which
  /// would cover the shutter.
  void _toast(String message) {
    if (!mounted) return;
    _noteTimer?.cancel();
    setState(() => _note = message);
    _noteTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _note = null);
    });
  }

  void _retakeFront() {
    if (_busy || _side == 0) return;
    setState(() {
      _returnTo = _side;
      _side = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(idCopyDraftProvider);
    final scan = ref.watch(scanControllerProvider);
    final type = draft?.type ?? IdCopyType.idCard;
    final front = _side > 0 && draft != null && draft.sideIds.isNotEmpty ? scan.pageById(draft.sideIds.first) : null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _preview(type),
                    if (type.sides > 1)
                      Positioned(
                        top: Space.md,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _Pill('${_side + 1} of ${type.sides}'),
                        ),
                      ),
                    if (_note != null)
                      Positioned(
                        bottom: Space.md,
                        left: Space.lg,
                        right: Space.lg,
                        child: Center(child: Semantics(liveRegion: true, child: _Pill(_note!))),
                      ),
                    if (front != null)
                      Positioned(
                        top: Space.md,
                        left: Space.md,
                        child: _FrontThumbnail(page: front, onTap: _retakeFront),
                      ),
                  ],
                ),
              ),
              _Controls(
                busy: _busy,
                canShoot: _status == _Status.ready && !_busy,
                shutterLabel: 'Take ${type.sideName(_side).toLowerCase()}',
                onClose: () => Navigator.of(context).pop(),
                onShoot: _shoot,
                onImport: _import,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(IdCopyType type) => switch (_status) {
    _Status.opening => const Center(child: CircularProgressIndicator(color: Colors.white)),
    _Status.ready =>
      !_camera.isReady
          ? const SizedBox.expand()
          : ClipRect(
              child: Center(
                child: _camera.buildPreview(
                  overlay: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        _guide = cardGuide(box.biggest, type);
                        return CustomPaint(
                          painter: _GuidePainter(_guide),
                          child: Align(
                            alignment: Alignment(0, _guide.center.dy * 2 - 1),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  type.sideName(_side),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    shadows: [Shadow(blurRadius: 6)],
                                  ),
                                ),
                                const SizedBox(height: Space.xs),
                                const Text(
                                  'Fit all four corners inside the frame',
                                  style: TextStyle(color: Colors.white, fontSize: 13, shadows: [Shadow(blurRadius: 6)]),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    _Status.blocked => _Message(
      title: 'Camera access is off',
      body: 'Import a photo or allow camera access.',
      action: _blockedPermanently ? 'Open settings' : 'Allow camera',
      onAction: _blockedPermanently ? openAppSettings : _open,
      onImport: _import,
    ),
    _Status.failed => _Message(
      title: 'The camera could not start',
      body: _failure ?? 'Try again, or import a photo.',
      action: 'Try again',
      onAction: _open,
      onImport: _import,
    ),
  };
}

/// Where the card guide goes on a preview of [size], normalized to it: as
/// wide as fits with a margin, in the document's shape, a little above the
/// middle so the side's name fits under the top.
Rect cardGuide(Size size, IdCopyType type) {
  if (size.isEmpty) return const Rect.fromLTWH(0.1, 0.3, 0.8, 0.4);
  var w = size.width * (type == IdCopyType.passport ? 0.8 : 0.86);
  var h = w / type.aspect;
  final maxH = size.height * 0.7;
  if (h > maxH) {
    h = maxH;
    w = h * type.aspect;
  }
  final left = (size.width - w) / 2, top = (size.height - h) / 2;
  return Rect.fromLTWH(left / size.width, top / size.height, w / size.width, h / size.height);
}

/// Whether a page [found] in the photo is the card in the [guide], not a
/// table edge or a small label: valid, and not far smaller or larger.
bool isCardLike(CropQuad found, CropQuad guide) {
  if (!found.isValid()) return false;
  final ratio = found.area / guide.area;
  return ratio > 0.35 && ratio < 2.2;
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.guide);

  final Rect guide;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas
        ..drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), grid)
        ..drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), grid);
    }
    final r = Rect.fromLTRB(
      guide.left * size.width,
      guide.top * size.height,
      guide.right * size.width,
      guide.bottom * size.height,
    );
    final corner = Paint()
      ..color = LumaColors.scan
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final arm = r.shortestSide * 0.16;
    for (final (o, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomRight, -1.0, -1.0),
      (r.bottomLeft, 1.0, -1.0),
    ]) {
      canvas
        ..drawLine(o, o + Offset(arm * dx, 0), corner)
        ..drawLine(o, o + Offset(0, arm * dy), corner);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.guide != guide;
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
  );
}

/// The accepted front, kept in view while the back is taken. Tap to take
/// the front again.
class _FrontThumbnail extends StatelessWidget {
  const _FrontThumbnail({required this.page, required this.onTap});

  final ScanPage page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Front page taken. Retake front',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 84,
            height: 54,
            decoration: BoxDecoration(border: Border.all(color: LumaColors.scan, width: 2)),
            child: PageImage(page: page),
          ),
          const SizedBox(height: 2),
          const Text('Retake front', style: TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 4)])),
        ],
      ),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.busy,
    required this.canShoot,
    required this.shutterLabel,
    required this.onClose,
    required this.onShoot,
    required this.onImport,
  });

  final bool busy;
  final bool canShoot;
  final String shutterLabel;
  final VoidCallback onClose;
  final VoidCallback onShoot;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    Widget side(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minTapTarget, minWidth: minTapTarget),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Row(
        children: [
          side(Icons.close, 'Close', onClose),
          Semantics(
            button: true,
            enabled: canShoot,
            label: shutterLabel,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: canShoot ? onShoot : null,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: LumaColors.scan,
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : null,
                ),
              ),
            ),
          ),
          side(Icons.photo_library_outlined, 'Import', onImport),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    required this.onImport,
  });

  final String title;
  final String body;
  final String action;
  final Future<Object?> Function() onAction;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white, size: 48),
          const SizedBox(height: Space.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.sm),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: Space.lg),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LumaColors.scan, foregroundColor: LumaColors.onScan),
            onPressed: onAction,
            child: Text(action),
          ),
          TextButton(
            onPressed: onImport,
            child: const Text('Import', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}
