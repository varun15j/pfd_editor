import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/photo_import.dart';
import '../pages/scan_controller.dart';

/// Picks photos, lets the user set their order, and adds them to the end of
/// the draft. Returns true when pages were added.
Future<bool> importPhotosFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final List<PickedPhoto> picked;
  try {
    picked = await ref.read(photoPickerProvider).pick();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open your photos ($e)')));
    return false;
  }
  if (picked.isEmpty || !context.mounted) return false;

  final choice = await Navigator.of(context)
      .push<_ImportChoice>(MaterialPageRoute(builder: (_) => ImportPhotosScreen(photos: picked)));
  if (choice == null || !context.mounted) return false;

  final result = await ref.read(scanControllerProvider.notifier).importPhotos(choice.photos, autoCrop: choice.autoCrop);
  if (!context.mounted) return result.added > 0;
  final added = result.added == 0 ? null : 'Added ${result.added} page${result.added == 1 ? '' : 's'}';
  final skipped = result.unreadable.isEmpty
      ? null
      : '${result.unreadable.length == 1 ? 'This photo' : '${result.unreadable.length} photos'} '
            "couldn't be read: ${result.unreadable.join(', ')}";
  messenger.showSnackBar(
    SnackBar(
      content: Text([?added, ?skipped].join('. ')),
      duration: Duration(seconds: skipped == null ? 4 : 8),
    ),
  );
  return result.added > 0;
}

class _ImportChoice {
  const _ImportChoice(this.photos, this.autoCrop);

  final List<PickedPhoto> photos;
  final bool autoCrop;
}

/// Shows the picked photos with their page numbers. Tapping a photo takes it
/// out; tapping it again puts it back as the last page, so the order is the
/// order of taps.
class ImportPhotosScreen extends StatefulWidget {
  const ImportPhotosScreen({super.key, required this.photos});

  final List<PickedPhoto> photos;

  @override
  State<ImportPhotosScreen> createState() => _ImportPhotosScreenState();
}

class _ImportPhotosScreenState extends State<ImportPhotosScreen> {
  late final List<int> _order = [for (var i = 0; i < widget.photos.length; i++) i];
  bool _autoCrop = true;

  void _toggle(int i) => setState(() => _order.contains(i) ? _order.remove(i) : _order.add(i));

  @override
  Widget build(BuildContext context) {
    final count = _order.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('$count of ${widget.photos.length} selected'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _order
                ..clear()
                ..addAll([for (var i = 0; i < widget.photos.length; i++) i]);
            }),
            child: const Text('Reset order'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xs),
            child: Text(
              'Pages follow the numbers. Tap a photo to take it out, tap again to add it as the last page.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: LumaColors.of(context).muted),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.page),
            title: const Text('Auto-crop pages'),
            subtitle: const Text('Find the page edges in each photo. You can adjust them later.'),
            value: _autoCrop,
            onChanged: (v) => setState(() => _autoCrop = v),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xl),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 3 / 4,
                mainAxisSpacing: Space.md,
                crossAxisSpacing: Space.md,
              ),
              itemCount: widget.photos.length,
              itemBuilder: (context, i) {
                final position = _order.indexOf(i);
                return _PhotoTile(
                  photo: widget.photos[i],
                  position: position < 0 ? null : position + 1,
                  onTap: () => _toggle(i),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.md),
          child: FilledButton(
            onPressed: count == 0
                ? null
                : () => Navigator.pop(context, _ImportChoice([for (final i in _order) widget.photos[i]], _autoCrop)),
            child: Text(count == 0 ? 'Select photos to add' : 'Add $count page${count == 1 ? '' : 's'}'),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.position, required this.onTap});

  final PickedPhoto photo;

  /// 1-based page number, or null when the photo is left out.
  final int? position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final selected = position != null;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '${photo.name}, page $position' : '${photo.name}, not added',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: selected ? c.accent : c.line, width: selected ? 3 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: selected ? 1 : 0.45,
                child: Image.file(
                  File(photo.path),
                  fit: BoxFit.cover,
                  cacheWidth: 320,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: c.surfaceRaised,
                    child: Icon(Icons.broken_image_outlined, color: c.muted),
                  ),
                ),
              ),
              Positioned(
                top: Space.xs,
                left: Space.xs,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                  decoration: BoxDecoration(
                    color: selected ? c.accent : c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? c.accent : c.muted),
                  ),
                  child: selected
                      ? Text('$position', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.onAccent))
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
