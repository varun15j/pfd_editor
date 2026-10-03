import 'package:flutter/material.dart';

import '../../pdf_edit/annotations.dart';

/// What the user picked in the menu for a text box or signature.
enum AnnotationMenuAction { edit, larger, smaller, delete }

/// Menu shown when tapping a text box or signature in Move mode.
Future<AnnotationMenuAction?> showAnnotationMenu(BuildContext context, Annotation a) =>
    showModalBottomSheet<AnnotationMenuAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a is TextAnnotation)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit text'),
                onTap: () => Navigator.pop(context, AnnotationMenuAction.edit),
              ),
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: const Text('Larger'),
              onTap: () => Navigator.pop(context, AnnotationMenuAction.larger),
            ),
            ListTile(
              leading: const Icon(Icons.zoom_out),
              title: const Text('Smaller'),
              onTap: () => Navigator.pop(context, AnnotationMenuAction.smaller),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, AnnotationMenuAction.delete),
            ),
          ],
        ),
      ),
    );

/// [a] made 20% larger or smaller. Only text and signatures resize.
Annotation resizedAnnotation(Annotation a, {required bool larger}) {
  final f = larger ? 1.2 : 1 / 1.2;
  return switch (a) {
    TextAnnotation t => t.copyWith(fontSize: (t.fontSize * f).clamp(0.01, 0.2)),
    SignatureAnnotation s => s.copyWith(width: (s.width * f).clamp(0.08, 1.0)),
    _ => a,
  };
}

/// Asks for annotation text. Returns null when cancelled and an empty
/// string when the user chose Delete.
Future<String?> askAnnotationText(
  BuildContext context, {
  required String title,
  String initial = '',
  bool canDelete = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(title: title, initial: initial, canDelete: canDelete),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.canDelete});

  final String title;
  final String initial;
  final bool canDelete;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        decoration: const InputDecoration(hintText: 'Type here'),
      ),
      actions: [
        if (widget.canDelete) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Delete')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Done')),
      ],
    );
  }
}
