import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../imaging/page_renderer.dart';
import '../../imaging/render_service.dart';

/// Shows a page rendered with its recipe (or an override), rendering on a
/// background isolate and keeping the previous image visible meanwhile.
class PageImage extends ConsumerStatefulWidget {
  const PageImage({
    super.key,
    required this.page,
    this.recipe,
    this.maxDimension = RenderService.thumbnailSize,
    this.fit = BoxFit.contain,
  });

  final ScanPage page;
  final EditRecipe? recipe;
  final int maxDimension;
  final BoxFit fit;

  @override
  ConsumerState<PageImage> createState() => _PageImageState();
}

class _PageImageState extends ConsumerState<PageImage> {
  late Future<RenderedImage> _future;
  RenderedImage? _last;

  EditRecipe get _recipe => widget.recipe ?? widget.page.recipe;

  @override
  void initState() {
    super.initState();
    _start();
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
    _future = ref
        .read(renderServiceProvider)
        .render(widget.page, recipe: _recipe, maxDimension: widget.maxDimension)
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
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(image.path), fit: widget.fit, gaplessPlayback: true),
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
  }
}
