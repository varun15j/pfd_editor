import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/features/batch_capture/batch_camera.dart';

/// A camera that writes a small JPEG into [dir] for every shot. [deny] makes
/// [open] fail as if camera access were refused. Set [gate] to hold the next
/// shots until the test completes it.
class FakeBatchCamera implements BatchCamera {
  FakeBatchCamera(this.dir, {this.deny = false});

  final Directory dir;
  final bool deny;
  Completer<void>? gate;

  int shots = 0;
  int opens = 0;
  int pauses = 0;
  int resumes = 0;
  bool closed = false;
  bool torch = false;
  bool _ready = false;

  static final _jpg = img.encodeJpg(img.Image(width: 30, height: 40)..clear(img.ColorRgb8(236, 232, 222)));

  @override
  Future<void> open() async {
    opens++;
    if (deny) throw const ScannerPermissionDenied(permanently: true);
    _ready = true;
  }

  @override
  bool get isReady => _ready;

  @override
  bool get hasTorch => true;

  @override
  Widget buildPreview() => const SizedBox.expand(key: ValueKey('camera-preview'));

  @override
  Future<String> takePicture() async {
    await gate?.future;
    final file = File('${dir.path}/shot${shots++}.jpg')..writeAsBytesSync(_jpg);
    return file.path;
  }

  @override
  Future<void> setTorch(bool on) async => torch = on;

  @override
  Future<void> pause() async {
    pauses++;
    _ready = false;
  }

  @override
  Future<void> resume() async {
    resumes++;
    _ready = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    _ready = false;
  }
}
