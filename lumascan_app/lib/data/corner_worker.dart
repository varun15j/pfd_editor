import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../imaging/corner_model.dart';
import '../imaging/onnx_corner_model.dart';

/// Work for a [CornerWorker]: given the corner model, or null when the model
/// failed on this job and the hand-made detector must answer alone.
///
/// A job crosses to another isolate, and a Dart closure carries every
/// variable its enclosing scopes share with other closures, so build jobs
/// in small top-level functions that capture only their arguments, not in
/// a provider or widget.
typedef CornerJob<R> = R Function(CornerModel? model);

/// Runs [job] in [worker], or, when there is no worker (the model cannot
/// load, or smart scanning is off), in a fresh isolate on the hand-made
/// detector alone.
Future<R> runCornerJob<R>(Future<CornerWorker?> worker, CornerJob<R> job) async {
  final w = await worker;
  return w == null ? _alone(job) : w.run(job);
}

Future<R> _alone<R>(CornerJob<R> job) => Isolate.run(() => job(null));

/// One isolate that holds the corner model, loaded once, for every page
/// search: camera preview frames, photos (camera shots, imports, ID cards,
/// crop and auto crop) and book spreads. A fresh isolate per job would have
/// to load the model every time, and one model, not one per screen, keeps
/// memory down on small phones.
class CornerWorker {
  CornerWorker._(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _pending = <int, Completer<Object?>>{};
  var _next = 0;

  /// Starts the worker, or gives null when the model cannot be loaded or
  /// run here (no native library, as in tests), so the caller falls back to
  /// the hand-made detector.
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
        final (id, result, error) = message as (int, Object?, Object?);
        final done = worker._pending.remove(id);
        if (done == null) return;
        error == null ? done.complete(result) : done.completeError(error);
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

  /// Runs [job] in the worker. [job] is sent to the worker isolate, so it
  /// must capture only what can be sent (frames, paths, flags).
  Future<R> run<R>(CornerJob<R> job) async {
    final id = _next++;
    final done = Completer<Object?>();
    _pending[id] = done;
    _send.send((id, job));
    return await done.future as R;
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
        reply.send((id, job(model), null));
        return;
      } on FormatException catch (e) {
        // An unreadable photo, which the caller reports as such.
        reply.send((id, null, e));
        return;
      } catch (e) {
        // A model failure must not stall a scan: the hand-made detector
        // still answers.
        debugPrint('Corner model failed: $e');
      }
      try {
        reply.send((id, job(null), null));
      } catch (e) {
        reply.send((id, null, e is FormatException ? e : StateError('$e')));
      }
    });
  }
}
