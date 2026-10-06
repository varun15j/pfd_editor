import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../imaging/page_renderer.dart';
import '../../imaging/render_service.dart';
import '../pdf_editor/annotation_layer.dart';

/// Shows a page rendered with its recipe (or an override), rendering on a
/// background isolate and keeping the previous image visible meanwhile.
class PageImage extends ConsumerStatefulWidget {
  const PageImage({
    super.key,
    required this.page,
    this.recipe,
    this.maxDimension = RenderService.thumbnailSize,
    this.fit = BoxFit.contain,
    this.showMarks = true,
  });

  final ScanPage page;
  final EditRecipe? recipe;
  final int maxDimension;
  final BoxFit fit;

  /// Draws the page's pen, text and signature marks over the image. Turn off
  /// where the image is shown with a different crop or rotation than the
  /// page's own, because the marks would not line up.
  final bool showMarks;

  @override
  ConsumerState<PageImage> createState() => _PageImageState();
}

class _PageImageState extends ConsumerState<PageImage> {
  late Future<RenderedImage> _future;
  RenderedImage? _last;

  EditRecipe get _recipe => widget.recipe ?? widget.page.recipe;

  RenderService? _service;

  @override
  void initState() {
    super.initState();
    final service = ref.read(renderServiceProvider)..addListener(_onCacheCleared);
    _service = service;
    _start();
  }

  @override
  void dispose() {
    _service?.removeListener(_onCacheCleared);
    super.dispose();
  }

  /// The rendered files were deleted: drop the picture and render it again.
  void _onCacheCleared() {
    _last = null;
    setState(_start);
  }

  @override
  void didUpdateWidget(PageImage old) {
    super.didUpdateWidget(old);
    final oldRecipe = old.recipe ?? old.page.recipe;
    if (old.page.id != widget.page.id || oldRecipe != _recipe || old.maxDimension != widget.maxDimension) {
      _start();
    }
  }

  void _start() {
    _future = ref.read(renderServiceProvider).render(widget.page, recipe: _recipe, maxDimension: widget.maxDimension)
      ..then((r) => _last = r, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RenderedImage>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        final image = snap.data ?? _last;
        if (image == null) {
          return const Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final decodeWidth = _decodeWidth(image, constraints, MediaQuery.devicePixelRatioOf(context));
            Widget picture(BoxFit fit) =>
                Image.file(File(image.path), fit: fit, gaplessPlayback: true, cacheWidth: decodeWidth);
            return Stack(
              fit: StackFit.expand,
              children: [
                if (widget.showMarks && widget.page.annotations.isNotEmpty)
                  // The image and its marks share one box sized like the image,
                  // so the marks stay on the page under any fit.
                  FittedBox(
                    fit: widget.fit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: image.width.toDouble(),
                      height: image.height.toDouble(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [picture(BoxFit.fill), StaticMarks(widget.page.annotations)],
                      ),
                    ),
                  )
                else
                  picture(widget.fit),
            if (snap.connectionState != ConnectionState.done)
              const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
          ],
        );
          },
        );
      },
    );
  }

  /// The width to decode [image] at: the pixels it covers on screen, so a
  /// small grid cell never holds a larger bitmap than it shows. Null keeps
  /// the file's own size.
  int? _decodeWidth(RenderedImage image, BoxConstraints box, double pixelRatio) {
    if (!box.hasBoundedWidth || !box.hasBoundedHeight || image.width <= 0 || image.height <= 0) return null;
    final aspect = image.width / image.height;
    final shown = switch (widget.fit) {
      BoxFit.cover => math.max(box.maxWidth, box.maxHeight * aspect),
      BoxFit.contain || BoxFit.scaleDown => math.min(box.maxWidth, box.maxHeight * aspect),
      _ => box.maxWidth,
    };
    final width = (shown * pixelRatio).ceil();
    return width > 0 && width < image.width ? width : null;
  }
}
