import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../domain/library.dart';

/// One saved document: thumbnail, name, when it changed, page count
/// (US-02.1). Tapping shares the PDF until the document viewer lands.
class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.document});

  final SavedDocument document;

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(document.pdfPath, mimeType: 'application/pdf')],
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final pages = '${document.pageCount} page${document.pageCount == 1 ? '' : 's'}';
    final thumb = document.thumbnailPath;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _share(context),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm / 2),
                child: Container(
                  width: 48,
                  height: 64,
                  color: c.canvas,
                  child: thumb != null && File(thumb).existsSync()
                      ? Image.file(File(thumb), fit: BoxFit.cover, excludeFromSemantics: true)
                      : Icon(Icons.picture_as_pdf_outlined, color: c.accent),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${formatModified(document.modifiedAt, DateTime.now())} · $pages', style: text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.ios_share, color: c.muted, semanticLabel: 'Share'),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Just now", "5 min ago", "Today 14:05", "Yesterday", or "3 Oct 2026".
String formatModified(DateTime t, DateTime now) {
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  String two(int v) => v.toString().padLeft(2, '0');
  if (day == today) return 'Today ${two(t.hour)}:${two(t.minute)}';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}
