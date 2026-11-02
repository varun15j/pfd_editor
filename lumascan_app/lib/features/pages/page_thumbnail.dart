import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../ui/luma_icons.dart';
import 'page_image.dart';

/// A page in a grid, list or strip. High profile: the page's picture, fading
/// in as it arrives. Low profile: a page icon with the page number, so a
/// 2 GB phone renders nothing it does not have to; the picture is shown once
/// the page is opened.
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({super.key, required this.page, required this.number, this.fit = BoxFit.contain});

  final ScanPage page;

  /// The page's number in its document, counted from 1.
  final int number;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (Motion.of(context).pageThumbnails) return PageImage(page: page, fit: fit);
    return PageIconTile(number: number);
  }
}

/// A page icon with "Page N" (or just N where there is no room): what Low
/// shows instead of a page's picture.
class PageIconTile extends StatelessWidget {
  const PageIconTile({super.key, required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final roomy = box.maxWidth >= 72 && box.maxHeight >= 72;
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LumaIcons.document, size: roomy ? 32 : 22, color: colors.muted),
                  const SizedBox(height: 2),
                  Text(
                    roomy ? 'Page $number' : '$number',
                    style: TextStyle(color: colors.muted, fontWeight: FontWeight.w600, fontSize: roomy ? 12 : 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
