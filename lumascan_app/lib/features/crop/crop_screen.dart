import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../imaging/page_renderer.dart';
import '../pages/scan_controller.dart';

/// Manual crop (S03). The platform scanner already crops to the detected
/// edges; this screen lets the user fine-tune the four corners. The corners
/// are stored in the recipe and the original image is never modified.
class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({super.key, required this.pageId});

  final String pageId;

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  late CropQuad _quad;
  late final Future<RenderedImage> _source;
  int? _activeHandle;

  @override
  void initState() {
    super.initState();
    final page = ref.read(scanControllerProvider).pageById(widget.pageId)!;
    _quad = page.recipe.crop;
    _source = ref.read(renderServiceProvider).source(page);
  }

  void _save() {
    if (!_quad.isValid()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Corners must form a four-sided shape that does not cross itself.'),
      ));
      return;
    }
    final controller = ref.read(scanControllerProvider.notifier);
    final page = ref.read(scanControllerProvider).pageById(widget.pageId);
    if (page != null && page.recipe.crop != _quad) {
      controller.updateRecipe(page.id, page.recipe.copyWith(crop: _quad));
    }
    Navigator.of(context).pop();
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
        actions: [
          TextButton(
            onPressed: () => setState(() => _quad = CropQuad.full),
            child: const Text('Full page', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: FutureBuilder<RenderedImage>(
        future: _source,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not open this page', style: TextStyle(color: Colors.white)));
          }
          final source = snap.data;
          if (source == null) return const Center(child: CircularProgressIndicator());
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: AspectRatio(
                aspectRatio: source.width / source.height,
                child: LayoutBuilder(builder: (context, box) {
                  final size = box.biggest;
                  Offset toLocal(NormPoint p) => Offset(p.x * size.width, p.y * size.height);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: Image.file(File(source.path), fit: BoxFit.fill)),
                      Positioned.fill(
                        child: CustomPaint(painter: _QuadPainter(_quad, valid: valid)),
                      ),
                      for (var i = 0; i < 4; i++)
                        Positioned(
                          left: toLocal(_quad.points[i]).dx - 24,
                          top: toLocal(_quad.points[i]).dy - 24,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => setState(() => _activeHandle = i),
                            onPanEnd: (_) => setState(() => _activeHandle = null),
                            onPanUpdate: (d) {
                              final p = _quad.points[i];
                              setState(() {
                                _quad = _quad.withPoint(
                                  i,
                                  NormPoint(p.x + d.delta.dx / size.width, p.y + d.delta.dy / size.height),
                                );
                              });
                            },
                            child: Semantics(
                              label: '${const ['Top left', 'Top right', 'Bottom right', 'Bottom left'][i]} corner',
                              child: SizedBox.square(
                                dimension: 48,
                                child: Center(
                                  child: Container(
                                    width: _activeHandle == i ? 22 : 16,
                                    height: _activeHandle == i ? 22 : 16,
                                    decoration: BoxDecoration(
                                      color: _activeHandle == i ? LumaColors.dark.warning : LumaColors.dark.accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
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
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: _save, child: const Text('Apply crop'))),
            ],
          ),
        ),
      ),
    );
  }
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
