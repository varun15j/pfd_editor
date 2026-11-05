import 'dart:isolate';
import 'dart:math' as math;

import 'render_queue.dart';

/// Thrown by [runPageJobs] once [isCancelled] says the user stopped the work.
class PageJobsCancelled implements Exception {
  const PageJobsCancelled();

  @override
  String toString() => 'Stopped';
}

/// Runs [job] on each of [items], each on its own isolate, a few at a time
/// (at most two, so two decoded pages are in memory at once), and returns
/// the results in the same order. [onProgress] is told after each one;
/// [isCancelled] is checked before each one starts.
///
/// [job] and the items are sent to the isolates, so [job] must be a
/// top-level function, or a closure made in a top-level function from plain
/// values. A closure written inside a method or a widget can carry that
/// scope's other variables along (the screen's State, a Future), which an
/// isolate cannot take.
Future<List<R>> runPageJobs<T, R>(
  List<T> items,
  R Function(T item) job, {
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  int? concurrency,
}) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0, finished = 0;
  Future<void> worker() async {
    while (true) {
      if (isCancelled?.call() ?? false) throw const PageJobsCancelled();
      final i = next++;
      if (i >= items.length) return;
      final item = items[i];
      results[i] = await _inIsolate(job, item);
      finished++;
      onProgress?.call(finished, items.length);
    }
  }

  final workers = math.max(1, math.min(concurrency ?? math.min(2, RenderQueue.defaultConcurrency), items.length));
  await Future.wait([for (var w = 0; w < workers; w++) worker()]);
  if (isCancelled?.call() ?? false) throw const PageJobsCancelled();
  return results.cast<R>();
}

/// Runs [job] on [item] in a new isolate. Top-level, so the closure sent
/// holds only these two, never [runPageJobs]'s [isCancelled] or
/// [onProgress], which belong to the screen.
Future<R> _inIsolate<T, R>(R Function(T item) job, T item) => Isolate.run(() => job(item));
