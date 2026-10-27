import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../imaging/onnx_corner_model.dart';
import 'camera_frame.dart';

/// One isolate that analyses preview frames with the corner model loaded
/// once, rather than a fresh isolate per frame, which would have to load the
/// model every time.
class FrameWorker {
  FrameWorker._(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _pending = <int, Completer<FrameAnalysis>>{};
  var _next = 0;

  /// Starts the worker, or gives null when the model cannot be loaded or
  /// run here (no native library, as in tests), so the caller falls back to
  /// the hand-made detector.
  static Future<FrameWorker?> start() async {
    try {
      final bytes = (await rootBundle.load(cornerModelAsset)).buffer.asUint8List();
      final replies = ReceivePort();
      final isolate = await Isolate.spawn(_main, (replies.sendPort, bytes), debugName: 'frame worker');
      final first = Completer<Object?>();
      late final FrameWorker worker;
      replies.listen((message) {
        if (!first.isCompleted) {
          first.complete(message);
          return;
        }
        final (id, analysis) = message as (int, FrameAnalysis);
        worker._pending.remove(id)?.complete(analysis);
      });
      final ready = await first.future;
      if (ready is! SendPort) {
        debugPrint('Corner model unavailable: $ready');
        replies.close();
        isolate.kill();
        return null;
      }
      return worker = FrameWorker._(isolate, ready, replies);
    } catch (e) {
      debugPrint('Corner model unavailable: $e');
      return null;
    }
  }

  Future<FrameAnalysis> analyze(CameraFrame frame) {
    final id = _next++;
    final done = Completer<FrameAnalysis>();
    _pending[id] = done;
    _send.send((id, frame));
    return done.future;
  }

  void stop() {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    for (final p in _pending.values) {
      p.completeError(StateError('Frame worker stopped'));
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
      final (id, frame) = message as (int, CameraFrame);
      FrameAnalysis analysis;
      try {
        analysis = analyzeFrame(frame, model: model);
      } catch (e) {
        // A model failure must not stall the camera: the hand-made
        // detector still answers.
        debugPrint('Corner model failed: $e');
        analysis = analyzeFrame(frame);
      }
      reply.send((id, analysis));
    });
  }
}
