import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../imaging/page_renderer.dart';
import '../pages/marks_notice.dart';
import '../pages/scan_controller.dart';

const _cornerNames = ['Top left', 'Top right', 'Bottom right', 'Bottom left'];
const _edgeNames = ['Top', 'Right', 'Bottom', 'Left'];

/// Size of a handle's touch area on screen, whatever the zoom.
const _handleTouch = 48.0;
const _loupeSize = 104.0;
const _loupeMagnification = 2.5;
const _maxZoom = 6.0;

/// Manual crop (S03). The platform scanner already crops to the detected
/// edges; this screen lets the user fine-tune the corners and sides. Pinch to
/// zoom for precision: handles keep their size, and a magnifier shows the spot
/// under the finger. The crop is stored in the recipe and the original image
/// is never modified.
class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({super.key, required this.pageId});

  final String pageId;

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  final _zoom = TransformationController();
  final _contentKey = GlobalKey();
  final _viewerKey = GlobalKey();
  late CropQuad _quad;
  late final Future<RenderedImage> _source;
  late final Future<CropQuad?> _detected;
  late final String _originalPath;
  int? _activeCorner;
  int? _activeEdge;

  bool get _dragging => _activeCorner != null || _activeEdge != null;

  @override
  void initState() {
    super.initState();
    final page = ref.read(scanControllerProvider).pageById(widget.pageId)!;
    _quad = page.recipe.crop;
    _originalPath = page.originalPath;
    _source = ref.read(renderServiceProvider).source(page);
    // Looked up once, so Reset can answer straight away.
    _detected = _detect();
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<CropQuad?> _detect() async {
    try {
      return await ref.read(photoAnalyzerProvider).analyze(_originalPath);
    } on Object {
      return null;
    }
  }

  Future<void> _resetToDetected() async {
    final detected = await _detected;
    if (!mounted) return;
    if (detected == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't find the page edges. Drag the corners to set them.")));
      return;
    }
    setState(() => _quad = detected);
  }

  void _save() {
    if (!_quad.isValid()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Corners must form a four-sided shape that does not cross itself.')));
      return;
    }
    final controller = ref.read(scanControllerProvider.notifier);
    final page = ref.read(scanControllerProvider).pageById(widget.pageId);
    if (page != null && page.recipe.crop != _quad) {
      final next = page.recipe.copyWith(crop: _quad);
      final dropsMarks = controller.dropsMarks(page.id, next);
      controller.updateRecipe(page.id, next);
      if (dropsMarks) showMarksRemovedNotice(context, controller);
    }
    Navigator.of(context).pop();
  }

  void _moveCorner(int i, Offset delta, Size size) {
    final p = _quad.points[i];
    setState(() => _quad = _quad.withPoint(i, NormPoint(p.x + delta.dx / size.width, p.y + delta.dy / size.height)));
  }

  /// A side only slides across the page: the drag is reduced to the part that
  /// points away from (or towards) the opposite side.
  void _moveEdge(int edge, Offset delta, Size size) {
    final a = _quad.points[edge], b = _quad.points[(edge + 1) % 4];
    final along = Offset((b.x - a.x) * size.width, (b.y - a.y) * size.height);
    if (along.distance < 1e-6) return;
    final normal = Offset(-along.dy, along.dx) / along.distance;
    final slide = normal * (delta.dx * normal.dx + delta.dy * normal.dy);
    setState(() => _quad = _quad.translateEdge(edge, slide.dx / size.width, slide.dy / size.height));
  }

  void _endDrag() => setState(() {
    _activeCorner = null;
    _activeEdge = null;
  });

  /// The point being dragged, in the image's own 0..1 space.
  NormPoint? get _activePoint {
    final c = _activeCorner, e = _activeEdge;
    if (c != null) return _quad.points[c];
    if (e != null) {
      final a = _quad.points[e], b = _quad.points[(e + 1) % 4];
      return NormPoint((a.x + b.x) / 2, (a.y + b.y) / 2);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final valid = _quad.isValid();
    return Scaffold(
      backgroundColor: LumaColors.dark.background,
      appBar: AppBar(
        backgroundColor: LumaColors.dark.background,
        foregroundColor: Colors.white,
        title: const Text('Crop'),
      ),
      body: FutureBuilder<RenderedImage>(
        future: _source,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text('Could not open this page', style: TextStyle(color: Colors.white)),
            );
          }
          final source = snap.data;
          if (source == null) return const Center(child: CircularProgressIndicator());
          return Column(
            children: [
              Expanded(
                child: Stack(
                  key: _viewerKey,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        transformationController: _zoom,
                        maxScale: _maxZoom,
                        // A handle drag must not also pan or zoom the page.
                        panEnabled: !_dragging,
                        scaleEnabled: !_dragging,
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: source.width / source.height,
                              child: _CropArea(
                                key: _contentKey,
                                source: source,
                                quad: _quad,
                                valid: valid,
                                zoom: _zoom,
                                activeCorner: _activeCorner,
                                activeEdge: _activeEdge,
                                onCornerDown: (i) => setState(() => _activeCorner = i),
                                onEdgeDown: (i) => setState(() => _activeEdge = i),
                                onEnd: _endDrag,
                                onCornerMove: _moveCorner,
                                onEdgeMove: _moveEdge,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_activePoint case final point?)
                      _Loupe(
                        source: source,
                        point: point,
                        quad: _quad,
                        zoom: _zoom,
                        contentKey: _contentKey,
                        viewerKey: _viewerKey,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
                      onPressed: _resetToDetected,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Reset to detected'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
                      onPressed: () => setState(() => _quad = CropQuad.full),
                      icon: const Icon(Icons.crop_free),
                      label: const Text('Full page'),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Pinch to zoom. Drag a corner or a side.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: _save, child: const Text('Apply crop')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page image with its crop outline, corner handles and side handles.
class _CropArea extends StatelessWidget {
  const _CropArea({
    super.key,
    required this.source,
    required this.quad,
    required this.valid,
    required this.zoom,
    required this.activeCorner,
    required this.activeEdge,
    required this.onCornerDown,
    required this.onEdgeDown,
    required this.onEnd,
    required this.onCornerMove,
    required this.onEdgeMove,
  });

  final RenderedImage source;
  final CropQuad quad;
  final bool valid;
  final TransformationController zoom;
  final int? activeCorner;
  final int? activeEdge;
  final ValueChanged<int> onCornerDown;
  final ValueChanged<int> onEdgeDown;
  final VoidCallback onEnd;
  final void Function(int index, Offset delta, Size size) onCornerMove;
  final void Function(int index, Offset delta, Size size) onEdgeMove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        Offset toLocal(NormPoint p) => Offset(p.x * size.width, p.y * size.height);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: Image.file(File(source.path), fit: BoxFit.fill)),
            Positioned.fill(
              child: CustomPaint(painter: _QuadPainter(quad, valid: valid)),
            ),
            // Handles are laid out in image space, so they are scaled back down
            // by the zoom to stay the same size on screen.
            ListenableBuilder(
              listenable: zoom,
              builder: (context, _) {
                final scale = zoom.value.getMaxScaleOnAxis();
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < 4; i++)
                      _handle(
                        center: (toLocal(quad.points[i]) + toLocal(quad.points[(i + 1) % 4])) / 2,
                        scale: scale,
                        label: '${_edgeNames[i]} side',
                        onDown: () => onEdgeDown(i),
                        onMove: (d) => onEdgeMove(i, d, size),
                        child: _EdgeHandle(
                          active: activeEdge == i,
                          angle: math.atan2(
                            (quad.points[(i + 1) % 4].y - quad.points[i].y) * size.height,
                            (quad.points[(i + 1) % 4].x - quad.points[i].x) * size.width,
                          ),
                        ),
                      ),
                    for (var i = 0; i < 4; i++)
                      _handle(
                        center: toLocal(quad.points[i]),
                        scale: scale,
                        label: '${_cornerNames[i]} corner',
                        onDown: () => onCornerDown(i),
                        onMove: (d) => onCornerMove(i, d, size),
                        child: _CornerHandle(active: activeCorner == i),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _handle({
    required Offset center,
    required double scale,
    required String label,
    required VoidCallback onDown,
    required ValueChanged<Offset> onMove,
    required Widget child,
  }) {
    final touch = _handleTouch / scale;
    return Positioned(
      left: center.dx - touch / 2,
      top: center.dy - touch / 2,
      width: touch,
      height: touch,
      child: Listener(
        onPointerDown: (_) => onDown(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => onMove(d.delta),
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: Semantics(
            label: label,
            // Laid out at full size even when the touch box is smaller (zoomed
            // in), then scaled back down to fit it.
            child: OverflowBox(
              maxWidth: _handleTouch,
              maxHeight: _handleTouch,
              child: Transform.scale(
                scale: 1 / scale,
                child: SizedBox.square(
                  dimension: _handleTouch,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final size = active ? 22.0 : 16.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? LumaColors.dark.warning : LumaColors.dark.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}

class _EdgeHandle extends StatelessWidget {
  const _EdgeHandle({required this.active, required this.angle});

  final bool active;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 30,
        height: active ? 12 : 9,
        decoration: BoxDecoration(
          color: active ? LumaColors.dark.warning : LumaColors.dark.accent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

/// A magnifier above the finger (below it near the top of the screen) that
/// shows the image around the dragged point with a crosshair on it.
class _Loupe extends StatelessWidget {
  const _Loupe({
    required this.source,
    required this.point,
    required this.quad,
    required this.zoom,
    required this.contentKey,
    required this.viewerKey,
  });

  final RenderedImage source;
  final NormPoint point;
  final CropQuad quad;
  final TransformationController zoom;
  final GlobalKey contentKey;
  final GlobalKey viewerKey;

  @override
  Widget build(BuildContext context) {
    final content = contentKey.currentContext?.findRenderObject() as RenderBox?;
    final viewer = viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (content == null || viewer == null || !content.hasSize || !viewer.hasSize) return const SizedBox.shrink();

    // Where the point is on screen, whatever the zoom and pan.
    final onScreen = viewer.globalToLocal(
      content.localToGlobal(Offset(point.x * content.size.width, point.y * content.size.height)),
    );
    const lift = _loupeSize / 2 + 44;
    final above = onScreen.dy - lift - _loupeSize / 2 >= 0;
    final center = Offset(
      onScreen.dx.clamp(_loupeSize / 2, math.max(_loupeSize / 2, viewer.size.width - _loupeSize / 2)).toDouble(),
      above ? onScreen.dy - lift : onScreen.dy + lift,
    );

    final magnification = zoom.value.getMaxScaleOnAxis() * _loupeMagnification;
    final imageSize = Size(content.size.width * magnification, content.size.height * magnification);
    return Positioned(
      left: center.dx - _loupeSize / 2,
      top: center.dy - _loupeSize / 2,
      width: _loupeSize,
      height: _loupeSize,
      child: IgnorePointer(
        child: Semantics(
          label: 'Magnifier',
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
            ),
            child: ClipOval(
              child: Stack(
                children: [
                  Positioned(
                    left: _loupeSize / 2 - point.x * imageSize.width,
                    top: _loupeSize / 2 - point.y * imageSize.height,
                    width: imageSize.width,
                    height: imageSize.height,
                    child: Image.file(File(source.path), fit: BoxFit.fill),
                  ),
                  const Positioned.fill(child: CustomPaint(painter: _CrosshairPainter())),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = LumaColors.dark.warning
      ..strokeWidth = 1.5;
    canvas.drawLine(c - const Offset(12, 0), c + const Offset(12, 0), paint);
    canvas.drawLine(c - const Offset(0, 12), c + const Offset(0, 12), paint);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => false;
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.quad, {required this.valid});

  final CropQuad quad;
  final bool valid;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = quad.points.map((p) => Offset(p.x * size.width, p.y * size.height)).toList();
    final path = Path()..addPolygon(pts, true);
    // Dim everything outside the crop.
    final outside = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), path);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = valid ? const Color(0xFFA0E6BA) : Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.quad != quad || old.valid != valid;
}
