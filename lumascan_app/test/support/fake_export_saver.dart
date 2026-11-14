import 'package:lumascan/features/export/export_saver.dart';

/// The system save screen: notes each file and answers with [answer]
/// (null: the user cancelled).
class FakeExportSaver implements ExportSaver {
  FakeExportSaver({this.answer = 'Saved.pdf'});

  final saved = <String>[];
  String? answer;

  @override
  bool get canSaveToFolder => true;

  @override
  Future<String?> saveFile(String path, {required String mimeType, String? name}) async {
    saved.add(path);
    return answer;
  }

  @override
  Future<String?> saveToFolder(List<String> paths, {required String mimeType}) async {
    saved.addAll(paths);
    return answer;
  }
}
