import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/data/mlkit_vision.dart';
import 'package:lumascan/data/routed_ocr_engine.dart';
import 'package:lumascan/data/tesseract_ocr.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/ocr.dart';
import 'package:lumascan/domain/ocr_languages.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/features/settings/ocr_language_screen.dart';

import 'support/memory_stores.dart';

class _Engine implements OcrEngine, OcrLayoutEngine {
  _Engine(this.name);
  final String name;
  final asked = <String>[];

  @override
  Future<OcrCapability> capability(String languageCode) async {
    asked.add(languageCode);
    return OcrCapability(readiness: OcrReadiness.ready, language: name);
  }

  @override
  Future<void> prepare(String languageCode) async => asked.add(languageCode);

  @override
  Future<String> recognize(ScanPage page, {required String languageCode}) async => name;

  @override
  Future<String> recognizeFile(String path, {String languageCode = 'en'}) async => name;

  @override
  Future<OcrLayout> recognizeLayout(ScanPage page, {required String languageCode}) async =>
      OcrLayout([OcrBlock(text: name, left: 0, top: 0, right: 1, bottom: 1)]);
}

void main() {
  test('every language the request named is listed, with a native name', () {
    for (final code in ['en', 'hi', 'mr', 'gu', 'kn', 'ta', 'ml', 'bn', 'te', 'pa', 'or', 'as', 'ur']) {
      final language = OcrLanguage.byCode(code);
      expect(language, isNotNull, reason: code);
      expect(language!.nativeName, isNotEmpty);
    }
    expect(OcrLanguage.all.map((l) => l.code).toSet().length, OcrLanguage.all.length, reason: 'codes are unique');
    expect(OcrLanguage.of('xx').code, 'en');
  });

  test('ML Kit reads Latin and Devanagari; Tesseract takes the other Indian scripts', () {
    for (final l in OcrLanguage.all) {
      final mlKit = MlKitOcrEngine.modelFor(l.script) != null;
      expect(mlKit || TesseractOcrEngine.handles(l.code), isTrue, reason: '${l.name} has an engine');
      expect(mlKit && TesseractOcrEngine.handles(l.code), isFalse, reason: '${l.name} has one engine');
    }
    expect(MlKitOcrEngine.unsupportedReason('hi'), isNull);
    expect(MlKitOcrEngine.unsupportedReason('ta'), contains('Tamil'));
  });

  test('the routed engine sends each language to its engine', () async {
    final mlKit = _Engine('mlkit'), tess = _Engine('tess');
    final engine = RoutedOcrEngine(fallback: mlKit, special: tess, handles: TesseractOcrEngine.handles);
    const page = ScanPage(id: 'p', originalPath: '/x.jpg');
    expect(await engine.recognize(page, languageCode: 'hi'), 'mlkit');
    expect(await engine.recognize(page, languageCode: 'ta'), 'tess');
    expect(await engine.recognizeFile('/x.jpg', languageCode: 'bn'), 'tess');
    expect((await engine.recognizeLayout(page, languageCode: 'en')).text, 'mlkit');
    await engine.capability('gu');
    expect(tess.asked, ['gu']);
  });

  test('the language is saved with the settings; an unknown one falls back to English', () {
    const s = AppSettings(ocrLanguage: 'ta');
    expect(AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>), s);
    expect(AppSettings.fromJson(const {'ocrLanguage': 'klingon'}).ocrLanguage, 'en');
    expect(AppSettings.fromJson(const {}).ocrLanguage, 'en');
  });

  test('Indian languages are read on Pro and Gold; Basic reads English instead', () {
    expect(AppPlan.basic.includes(PlanFeature.indianOcr), isFalse);
    expect(AppPlan.gold.includes(PlanFeature.indianOcr), isTrue);
    for (final (plan, code, read) in [
      (AppPlan.basic, 'hi', 'en'),
      (AppPlan.basic, 'de', 'de'),
      (AppPlan.pro, 'hi', 'hi'),
      (AppPlan.gold, 'ta', 'ta'),
    ]) {
      final container = ProviderContainer(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
          planProvider.overrideWithValue(plan),
        ],
      );
      addTearDown(container.dispose);
      container.read(appSettingsProvider.notifier).setOcrLanguage(code);
      expect(container.read(ocrLanguageProvider), read, reason: '${plan.label} $code');
    }
  });

  group('Tesseract models', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tess'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('are downloaded once with English, and a failed download leaves nothing behind', () async {
      final fetched = <String>[];
      var fail = true;
      final client = MockClient((r) async {
        fetched.add(r.url.pathSegments.last);
        return fail ? http.Response('nope', 404) : http.Response.bytes(List.filled(2048, 1), 200);
      });
      final engine = TesseractOcrEngine(imageFor: (_) async => '', client: client, dataDir: () async => dir.path);
      await expectLater(engine.prepare('ta'), throwsA(isA<HttpException>()));
      expect(Directory('${dir.path}/tessdata').listSync(), isEmpty);
      fail = false;
      fetched.clear();
      await engine.prepare('ta');
      expect(fetched, ['tam.traineddata', 'eng.traineddata']);
      fetched.clear();
      await engine.prepare('bn');
      expect(fetched, ['ben.traineddata'], reason: 'English is already there');
    });
  });

  test('hOCR becomes paragraphs of lines with boxes as fractions of the page', () {
    const hocr = '''
<div class='ocr_page' id='page_1' title='image "x.png"; bbox 0 0 1000 2000; ppageno 0'>
 <div class='ocr_carea' id='block_1_1' title="bbox 100 200 900 400">
  <p class='ocr_par' id='par_1_1' lang='tam' title="bbox 100 200 900 400">
   <span class='ocr_line' id='line_1_1' title="bbox 100 200 900 260; baseline 0 -5">
    <span class='ocrx_word' id='word_1_1' title='bbox 100 200 400 260; x_wconf 91'>வணக்கம்</span>
    <span class='ocrx_word' id='word_1_2' title='bbox 450 200 900 260; x_wconf 88'>A&amp;B</span>
   </span>
   <span class='ocr_line' id='line_1_2' title="bbox 100 300 500 400; baseline 0 -5">
    <span class='ocrx_word' id='word_1_3' title='bbox 100 300 500 400; x_wconf 80'>உலகம்</span>
   </span>
  </p>
  <p class='ocr_par' id='par_1_2' title="bbox 100 1000 300 1100">
   <span class='ocr_line' id='line_1_3' title="bbox 100 1000 300 1100">
    <span class='ocrx_word' id='word_1_4' title='bbox 100 1000 300 1100'>2026</span>
   </span>
  </p>
 </div>
</div>''';
    final layout = parseHocr(hocr);
    expect(layout.blocks, hasLength(2));
    final first = layout.blocks.first;
    expect(first.text, 'வணக்கம் A&B\nஉலகம்');
    expect(first.lines.first.left, 0.1);
    expect(first.lines.first.top, 0.1);
    expect(first.lines.first.right, 0.9);
    expect(first.bottom, 0.2);
    expect(layout.blocks.last.text, '2026');
    expect(parseHocr('').blocks, isEmpty);
  });

  testWidgets('picking an Indian language on Basic offers the upgrade and keeps English', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
        planProvider.overrideWithValue(AppPlan.basic),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OcrLanguageScreen()),
      ),
    );
    expect(find.text('Pro'), findsWidgets);
    await tester.tap(find.text('Hindi · हिन्दी'));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade to Pro'), findsWidgets);
    expect(container.read(appSettingsProvider).ocrLanguage, 'en');
  });

  testWidgets('on Pro, picking Tamil saves it', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
        planProvider.overrideWithValue(AppPlan.pro),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OcrLanguageScreen()),
      ),
    );
    expect(find.text('Pro'), findsNothing);
    await tester.scrollUntilVisible(find.text('Tamil · தமிழ்'), 100);
    await tester.tap(find.text('Tamil · தமிழ்'));
    await tester.pump();
    expect(container.read(ocrLanguageProvider), 'ta');
  });
}
