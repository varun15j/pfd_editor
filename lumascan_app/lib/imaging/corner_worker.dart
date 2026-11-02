import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'corner_model.dart';
import 'onnx_corner_model.dart';

/// A piece of corner-finding work for the [CornerWorker]. [run] gets the
/// corner model, or null when it failed on this job, so every job can fall
/// back to the hand-made detector. Jobs are sent to the worker's isolate,
/// so they hold plain data only.
abstract class CornerJob<T> {
  const CornerJob();

  T run(CornerModel? model);
}

/// One long-lived isolate that holds the corner model ([OnnxCornerModel]),
/// loaded once, and runs every kind of scan's corner finding on it: preview
/// frames in the camera, the photo just taken, imported photos, ID card
/// sides and book spreads. A fresh isolate per job would have to load the
/// model every time.
class CornerWorker {
  CornerWorker._(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _pending = <int, Completer<Object?>>{};
  var _next = 0;

  /// Starts the worker, or gives null when the model cannot be loaded or
  /// run here (no native library, as in tests), so callers fall back to the
  /// hand-made detector.
  static Future<CornerWorker?> start() async {
    try {
      final bytes = (await rootBundle.load(cornerModelAsset)).buffer.asUint8List();
      final replies = ReceivePort();
      final isolate = await Isolate.spawn(_main, (replies.sendPort, bytes), debugName: 'corner worker');
      final first = Completer<Object?>();
      late final CornerWorker worker;
      replies.listen((message) {
        if (!first.isCompleted) {
          first.complete(message);
          return;
        }
        final (id, ok, value) = message as (int, bool, Object?);
        final done = worker._pending.remove(id);
        if (done == null) return;
        ok ? done.complete(value) : done.completeError(value ?? StateError('Corner job failed'));
      });
      final ready = await first.future;
      if (ready is! SendPort) {
        debugPrint('Corner model unavailable: $ready');
        replies.close();
        isolate.kill();
        return null;
      }
      return worker = CornerWorker._(isolate, ready, replies);
    } catch (e) {
      debugPrint('Corner model unavailable: $e');
      return null;
    }
  }

  Future<T> run<T>(CornerJob<T> job) async {
    final id = _next++;
    final done = Completer<Object?>();
    _pending[id] = done;
    _send.send((id, job));
    return await done.future as T;
  }

  void stop() {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    for (final p in _pending.values) {
      p.completeError(StateError('Corner worker stopped'));
    }
    _pending.clear();
  }

  static void _main((SendPort, Uint8List) start) {
    final (reply, bytes) = start;
    final OnnxCornerModel model;
    try {
      model = OnnxCornerModel(bytes);
    } catch (e) {
      reply.send('$e');
      return;
    }
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    inbox.listen((message) {
      final (id, job) = message as (int, CornerJob<Object?>);
      try {
        reply.send((id, true, job.run(model)));
      } catch (e) {
        // A model failure must not stall the scan: the hand-made detector
        // still answers. An error it raises too (an unreadable photo) goes
        // back to the caller.
        debugPrint('Corner model failed: $e');
        try {
          reply.send((id, true, job.run(null)));
        } catch (e) {
          reply.send((id, false, e is Exception || e is Error ? e : '$e'));
        }
      }
    });
  }
}

/// The app's one [CornerWorker], started the first time a scan asks for
/// it. Null when the model cannot run on this device.
final cornerWorkerProvider = Provider<Future<CornerWorker?> Function()>((ref) {
  Future<CornerWorker?>? worker;
  ref.onDispose(() => worker?.then((w) => w?.stop()));
  return () => worker ??= CornerWorker.start();
});
