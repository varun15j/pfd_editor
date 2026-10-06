import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/page_store.dart';
import '../domain/models.dart';
import 'native_decode.dart';
import 'page_renderer.dart';
import 'render_queue.dart';

/// Renders previews and thumbnails on demand and memoises them per recipe, so
/// scrolling the page list or switching back to a filter is instant.
///
/// The full-resolution original is decoded once per photo, to make its
/// working copies (see [workingCopies]). Every on-screen picture is rendered
/// from those, never from the original; only export reads the original.
/// Rendered files are reused from disk after a restart.
class RenderService extends ChangeNotifier {
  RenderService(this._store, {RenderQueue? queue}) : _queue = queue ?? RenderQueue();

  final PageStore _store;
  final RenderQueue _queue;
  final _cache = <String, Future<RenderedImage>>{};
  final _working = <String, Future<WorkingCopies>>{};

  static const thumbnailSize = 480;
  static const previewSize = 1600;

  /// Long side of the small working copy. Larger than [thumbnailSize] so a
  /// cropped thumbnail still has enough pixels.
  static const smallSourceSize = 640;

  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = previewSize}) {
    final r = recipe ?? page.recipe;
    // The working preview already is the upright, uncropped page.
    if (r == const EditRecipe() && maxDimension >= previewSize) {
      return workingCopies(page).then((w) => w.preview);
    }
    final key = '${page.id}|${r.cacheKey}|$maxDimension';
    _queue.bump(key);
    return _cache
        .putIfAbsent(key, () async {
          final dir = await _store.renderDir;
          final out = p.join(dir.path, '${page.id}_${_fnv1a(key)}.jpg');
          final done = await readRendered(out);
          if (done != null) return done;
          final copies = await workingCopies(page);
          final source = maxDimension <= thumbnailSize ? copies.small : copies.preview;
          return _queue.run(
            key,
            () => renderToFile(originalPath: source.path, recipe: r, outPath: out, maxDimension: maxDimension),
          );
        })
        .catchError((Object e) {
          _cache.remove(key);
          throw e;
        });
  }

  /// The oriented, uncropped original used by the crop editor.
  Future<RenderedImage> source(ScanPage page) => render(page, recipe: const EditRecipe(), maxDimension: previewSize);

  /// The page's working copies, made from the original the first time they
  /// are needed (with the platform decoder, see [decodeUpright]) and kept
  /// next to it. Pages that share an original (a
  /// duplicate) share these too.
  Future<WorkingCopies> workingCopies(ScanPage page) {
    final original = page.originalPath;
    final key = 'working|$original';
    _queue.bump(key);
    return _working
        .putIfAbsent(original, () async {
          final previewPath = PageStore.workingPreviewPath(original);
          final smallPath = PageStore.workingSmallPath(original);
          final preview = await readRendered(previewPath);
          final small = await readRendered(smallPath);
          if (preview != null && small != null) return WorkingCopies(preview, small);
          return _queue.run(key, () async {
            try {
              final pixels = await decodeUpright(original, previewSize);
              return await writeWorkingCopies(
                rgba: pixels.bytes,
                width: pixels.width,
                height: pixels.height,
                previewPath: previewPath,
                smallPath: smallPath,
                smallSize: smallSourceSize,
              );
            } on Object {
              // A format the platform decoder refuses: decode it in Dart.
              return makeWorkingCopies(
                originalPath: original,
                previewPath: previewPath,
                smallPath: smallPath,
                previewSize: previewSize,
                smallSize: smallSourceSize,
              );
            }
          });
        })
        .catchError((Object e) {
          _working.remove(original);
          throw e;
        });
  }

  /// Makes the working copies and grid thumbnail of newly added pages in the
  /// background, so they are ready before the user scrolls to them. Pages on
  /// screen still go first, because the newest request runs first.
  void prepare(Iterable<ScanPage> pages) {
    for (final page in pages) {
      unawaited(render(page, maxDimension: thumbnailSize).then<void>((_) {}, onError: (_) {}));
    }
  }

  /// Forgets every rendered file after they were deleted (Clear cache), and
  /// tells the pictures on screen to render again.
  void evictAll() {
    _cache.clear();
    notifyListeners();
  }

  void evict(String pageId) => _cache.removeWhere((k, _) => k.startsWith('$pageId|'));

  static String _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }
}
