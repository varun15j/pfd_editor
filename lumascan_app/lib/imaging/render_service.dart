import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/page_store.dart';
import '../domain/models.dart';
import 'page_renderer.dart';

/// Renders previews and thumbnails on demand and memoises them per recipe, so
/// scrolling the page list or switching back to a filter is instant.
class RenderService extends ChangeNotifier {
  RenderService(this._store);

  final PageStore _store;
  final _cache = <String, Future<RenderedImage>>{};

  static const thumbnailSize = 480;
  static const previewSize = 1600;

  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = previewSize}) {
    final r = recipe ?? page.recipe;
    final key = '${page.id}|${r.cacheKey}|$maxDimension';
    return _cache
        .putIfAbsent(key, () async {
          final dir = await _store.renderDir;
          final out = p.join(dir.path, '${page.id}_${_fnv1a(key)}.jpg');
          return renderToFile(originalPath: page.originalPath, recipe: r, outPath: out, maxDimension: maxDimension);
        })
        .catchError((Object e) {
          _cache.remove(key);
          throw e;
        });
  }

  /// The oriented, uncropped original used by the crop editor.
  Future<RenderedImage> source(ScanPage page) => render(page, recipe: const EditRecipe(), maxDimension: previewSize);

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
