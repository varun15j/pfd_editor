import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A PDF chosen on the device, already copied into app storage so it stays
/// readable after the picker's cache is cleared.
class PickedPdf {
  const PickedPdf({required this.path, required this.name});

  final String path;

  /// File name as the user knows it, with .pdf.
  final String name;
}

/// Lets the user choose several PDFs from the device. Behind an interface so
/// tests do not open a native picker.
abstract class PdfPicker {
  /// The chosen PDFs, empty when the user cancels. Throws when the picker
  /// cannot open or a file cannot be read.
  Future<List<PickedPdf>> pick();
}

class FilePickerPdfPicker implements PdfPicker {
  @override
  Future<List<PickedPdf>> pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (picked.isEmpty) return const [];
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'pdf_sources'));
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final result = <PickedPdf>[];
    for (final (i, file) in picked.indexed) {
      final path = p.join(dir.path, '$stamp-$i.pdf');
      await file.xFile.saveTo(path);
      result.add(PickedPdf(path: path, name: file.name));
    }
    return result;
  }
}

final pdfPickerProvider = Provider<PdfPicker>((ref) => FilePickerPdfPicker());
