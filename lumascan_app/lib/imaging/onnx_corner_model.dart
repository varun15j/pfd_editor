import 'dart:typed_data';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import '../domain/models.dart';
import 'corner_model.dart';
import 'rgb_image.dart';

/// Asset of the corner model ([CornerModel]).
const cornerModelAsset = 'assets/models/lcnet100_256_lumascan_v1.onnx';

/// [CornerModel] run with ONNX Runtime on the CPU. Made from the model's
/// bytes, so it can be built inside the isolate that analyses frames.
class OnnxCornerModel implements CornerModel {
  OnnxCornerModel(Uint8List modelBytes) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      // Two threads: the preview analysis must leave the phone room for the
      // camera and the UI.
      ..setIntraOpNumThreads(2);
    _session = OrtSession.fromBuffer(modelBytes, options);
    options.release();
  }

  late final OrtSession _session;

  @override
  CropQuad? find(RgbImage image, {bool spread = false}) {
    const n = cornerModelInputSize;
    final input = OrtValueTensor.createTensorWithDataList(cornerModelInput(image), [1, 3, n, n]);
    final runOptions = OrtRunOptions();
    final outputs = _session.run(runOptions, {'img': input});
    input.release();
    runOptions.release();
    try {
      // [1][maps][size][size]
      final heat = (outputs.first!.value as List)[0] as List;
      final size = (heat[0] as List).length;
      final maps = [
        for (final map in heat)
          Float32List.fromList([
            for (final row in map as List)
              for (final v in row as List) (v as num).toDouble(),
          ]),
      ];
      return pageOutline(maps, size, spread: spread);
    } finally {
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  void release() => _session.release();
}
