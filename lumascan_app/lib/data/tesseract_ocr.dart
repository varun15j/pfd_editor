import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';
import '../domain/ocr.dart';
import '../domain/ocr_languages.dart';

/// Text recognition with Tesseract, on the device, for the Indian scripts ML
/// Kit cannot read: Bengali (Bangla, Assamese), Gujarati, Gurmukhi, Odia,
/// Tamil, Telugu, Kannada, Malayalam and Urdu.
///
/// Each language's model is downloaded once (1 to 4 MB) and then works
/// without internet; pages never leave the phone. English is read alongside,
/// so English words in a Tamil page are kept. Tesseract is made for print;
/// neat handwriting is read in part at best. Android only for now
/// (TesseractOcr.kt); iOS reports these languages as unavailable.
class TesseractOcrEngine implements OcrEngine, OcrLayoutEngine {
  TesseractOcrEngine({required this.imageFor, http.Client? client, Future<String> Function()? dataDir})
    : _client = client ?? http.Client(),
      _dataDir = dataDir ?? (() async => p.join((await getApplicationSupportDirectory()).path, 'ocr'));

  /// The page as rendered with its crop, rotation and filter.
  final Future<String> Function(ScanPage page) imageFor;

  final http.Client _client;

  /// Holds `tessdata/`, where Tesseract looks for its models.
  final Future<String> Function() _dataDir;

  static const _channel = MethodChannel('lumascan/tesseract');

  /// LumaScan language code to Tesseract model name.
  static const models = {
    'bn': 'ben', 'as': 'asm', 'gu': 'guj', 'pa': 'pan', 'or': 'ori', //
    'ta': 'tam', 'te': 'tel', 'kn': 'kan', 'ml': 'mal', 'ur': 'urd',
  };

  /// Download size in MB, rounded up, shown before the download.
  static const _sizeMb = {
    'ben': 2, 'asm': 2, 'guj': 2, 'pan': 2, 'ori': 2, //
    'tam': 2, 'tel': 2, 'kan': 3, 'mal': 3, 'urd': 2, 'eng': 4,
  };

  /// The fast integer models: a fraction of the size of the best ones and
  /// quick enough on a phone, for a small loss in accuracy.
  static const _source = 'https://github.com/tesseract-ocr/tessdata_fast/raw/main';

  static bool handles(String languageCode) => models.containsKey(languageCode);

  static bool get _supportedPlatform => Platform.isAndroid;

  Future<File> _model(String name) async => File(p.join(await _dataDir(), 'tessdata', '$name.traineddata'));

  Future<List<String>> _missing(String model) async => [
    for (final name in [model, 'eng'])
      if (!await (await _model(name)).exists()) name,
  ];

  @override
  Future<OcrCapability> capability(String languageCode) async {
    final language = OcrLanguage.byCode(languageCode);
    final name = language?.name ?? languageCode;
    final model = models[languageCode];
    if (model == null || !_supportedPlatform) {
      return OcrCapability(
        readiness: OcrReadiness.unavailable,
        language: name,
        reason: model == null ? 'This language is not supported yet.' : 'Reading $name works on Android only for now.',
      );
    }
    final missing = await _missing(model);
    if (missing.isEmpty) return OcrCapability(readiness: OcrReadiness.ready, language: name);
    final mb = missing.fold<int>(0, (sum, m) => sum + (_sizeMb[m] ?? 3));
    return OcrCapability(
      readiness: OcrReadiness.needsDownload,
      language: name,
      reason: 'Reading $name needs a one-time download of about $mb MB. After that it works offline.',
    );
  }

  @override
  Future<void> prepare(String languageCode) async {
    final model = models[languageCode];
    if (model == null) throw UnsupportedError('No Tesseract model for $languageCode');
    for (final name in await _missing(model)) {
      final file = await _model(name);
      await file.parent.create(recursive: true);
      final response = await _client.get(Uri.parse('$_source/$name.traineddata'));
      if (response.statusCode != 200 || response.bodyBytes.length < 1024) {
        throw HttpException('Download of $name failed (${response.statusCode})');
      }
      // Written aside and renamed, so a cut-off download never looks complete.
      final part = File('${file.path}.part');
      await part.writeAsBytes(response.bodyBytes, flush: true);
      await part.rename(file.path);
    }
  }

  Future<String> _run(String path, String languageCode, {required bool hocr}) async {
    final model = models[languageCode];
    if (model == null) throw UnsupportedError('No Tesseract model for $languageCode');
    final text = await _channel.invokeMethod<String>('recognize', {
      'imagePath': path,
      'dataDir': await _dataDir(),
      'languages': '$model+eng',
      'hocr': hocr,
    });
    return text ?? '';
  }

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async =>
      recognizeFile(await imageFor(page), languageCode: languageCode);

  @override
  Future<String> recognizeFile(String path, {String languageCode = 'en'}) async {
    return (await _run(path, languageCode, hocr: false)).trim();
  }

  @override
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode}) async {
    return parseHocr(await _run(await imageFor(page), languageCode, hocr: true));
  }
}

/// Reads Tesseract's hOCR into blocks (paragraphs) of lines, with boxes as
/// fractions of the page.
OcrLayout parseHocr(String hocr) {
  final tag = RegExp(
    r'''<(div|p|span)\b[^>]*class=['"](ocr_page|ocr_par|ocr_line|ocr_textfloat|ocr_header|ocr_caption|ocrx_word)['"][^>]*>''',
  );
  final bbox = RegExp(r'bbox (\d+) (\d+) (\d+) (\d+)');
  var pageW = 0.0, pageH = 0.0;
  final blocks = <OcrBlock>[];
  var lines = <OcrLine>[];
  List<int>? lineBox;
  var words = <String>[];

  void endLine() {
    final text = words.join(' ').trim();
    if (lineBox != null && text.isNotEmpty) lines.add(_line(text, lineBox!, pageW, pageH));
    lineBox = null;
    words = [];
  }

  void endBlock() {
    endLine();
    if (lines.isEmpty) return;
    double edge(double Function(OcrLine) f, bool min) =>
        lines.map(f).reduce((a, b) => min ? (a < b ? a : b) : (a > b ? a : b));
    blocks.add(
      OcrBlock(
        text: lines.map((l) => l.text).join('\n'),
        left: edge((l) => l.left, true),
        top: edge((l) => l.top, true),
        right: edge((l) => l.right, false),
        bottom: edge((l) => l.bottom, false),
        lines: lines,
      ),
    );
    lines = [];
  }

  for (final m in tag.allMatches(hocr)) {
    final box = bbox.firstMatch(m.group(0)!);
    final numbers = box == null ? null : [for (var i = 1; i <= 4; i++) int.parse(box.group(i)!)];
    switch (m.group(2)) {
      case 'ocr_page':
        if (numbers != null) {
          pageW = (numbers[2] - numbers[0]).toDouble();
          pageH = (numbers[3] - numbers[1]).toDouble();
        }
      case 'ocr_par':
        endBlock();
      case 'ocrx_word':
        final end = hocr.indexOf('</span>', m.end);
        if (end > 0) {
          final word = _unescape(hocr.substring(m.end, end).replaceAll(RegExp(r'<[^>]*>'), '')).trim();
          if (word.isNotEmpty) words.add(word);
        }
      default:
        endLine();
        lineBox = numbers;
    }
  }
  endBlock();
  if (pageW <= 0 || pageH <= 0) return const OcrLayout([]);
  return OcrLayout(blocks);
}

OcrLine _line(String text, List<int> box, double w, double h) {
  double unit(int v, double of) => of <= 0 ? 0 : (v / of).clamp(0.0, 1.0);
  return OcrLine(
    text: text,
    left: unit(box[0], w),
    top: unit(box[1], h),
    right: unit(box[2], w),
    bottom: unit(box[3], h),
  );
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
