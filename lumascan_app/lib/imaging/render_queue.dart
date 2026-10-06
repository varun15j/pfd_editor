import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Runs image jobs a few at a time, newest request first.
///
/// Each job decodes a picture on its own isolate, so twenty pages asked for at
/// once would hold twenty decoded images in memory together. Running only a
/// few keeps memory flat, and taking the newest request first means the pages
/// on screen now are drawn before the ones the user already scrolled past.
class RenderQueue {
  RenderQueue({int? concurrency}) : concurrency = concurrency ?? defaultConcurrency;

  /// Half the cores, between 1 and 3: enough to keep up with scrolling while
  /// leaving the UI thread room.
  static int get defaultConcurrency => (Platform.numberOfProcessors ~/ 2).clamp(1, 3);

  final int concurrency;

  /// Waiting jobs; the last one runs next.
  final _waiting = <_Job>[];
  final _byKey = <String, _Job>{};
  int _running = 0;

  /// Jobs started so far, for tests.
  int started = 0;

  /// The most jobs that ran at the same time, for tests.
  int peakRunning = 0;

  /// Queues [task] under [key]. Asking again for a key that is still waiting
  /// moves it to the front and returns the same result.
  Future<T> run<T>(String key, Future<T> Function() task) {
    final waiting = _byKey[key];
    if (waiting != null) {
      bump(key);
      return waiting.completer.future.then((v) => v as T);
    }
    final job = _Job(key, () => task());
    _byKey[key] = job;
    _waiting.add(job);
    _pump();
    return job.completer.future.then((v) => v as T);
  }

  /// Moves a waiting job to the front, because its picture is wanted now.
  void bump(String key) {
    final job = _byKey[key];
    if (job == null || !_waiting.remove(job)) return;
    _waiting.add(job);
  }

  void _pump() {
    while (_running < concurrency && _waiting.isNotEmpty) {
      final job = _waiting.removeLast();
      _byKey.remove(job.key);
      _running++;
      started++;
      peakRunning = math.max(peakRunning, _running);
      unawaited(
        Future.sync(job.task).then(job.completer.complete, onError: job.completer.completeError).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }
}

class _Job {
  _Job(this.key, this.task);
  final String key;
  final Future<Object?> Function() task;
  final completer = Completer<Object?>();
}
