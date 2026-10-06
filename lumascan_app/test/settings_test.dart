import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/app_settings_store.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/domain/scanner_service.dart';
import 'package:lumascan/export/pdf_exporter.dart';
import 'package:lumascan/features/capture/photo_import_screen.dart';
import 'package:lumascan/features/export/export_sheet.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/features/settings/about_section.dart';
import 'package:lumascan/features/settings/storage_section.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

class _FakeScanner implements ScannerService {
  _FakeScanner(this.paths);
  final List<String> paths;

  @override
  Future<List<String>> scan({required ScanSource source, int maxPages = 100}) async => paths;

  @override
  Future<void> cleanUp() async {}
}

class _FakeExporter implements PdfExporter {
  _FakeExporter(this.output);
  final File output;

  @override
  Future<File> export(List<ScanPage> pages, ExportOptions options, {void Function(int done, int total)? onProgress}) =>
      Future.value(output);
}

class _FailingLibraryStore extends MemoryLibraryStore {
  @override
  Future<void> save(index) => Future.error(StateError('disk full'));
}

void main() {
  late Directory tmp;
  var ready = false;

  void makeTmp() {
    tmp = Directory.systemTemp.createTempSync('lumascan_settings');
    ready = true;
  }

  tearDown(() {
    if (!ready) return;
    ready = false;
    tmp.deleteSync(recursive: true);
  });

  File write(String relative, int bytes) {
    final f = File(p.join(tmp.path, relative))..parent.createSync(recursive: true);
    return f..writeAsBytesSync(List.filled(bytes, 7));
  }

  group('settings values', () {
    test('survive a JSON round trip', () {
      const s = AppSettings(
        themeMode: ThemeMode.dark,
        defaultFilter: DocumentFilter.blackWhite,
        autoCropOnImport: false,
        keepOriginals: false,
        fileNamePattern: FileNamePattern.compact,
      );
      expect(AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>), s);
    });

    test('missing or unknown values fall back to the defaults', () {
      expect(AppSettings.fromJson(const {}), const AppSettings());
      expect(
        AppSettings.fromJson(const {'themeMode': 'neon', 'defaultFilter': 'sepia', 'fileNamePattern': 7}),
        const AppSettings(),
      );
      const defaults = AppSettings();
      expect(defaults.keepOriginals, isTrue);
      expect(defaults.autoCropOnImport, isTrue);
    });

    test('file name patterns', () {
      final t = DateTime(2026, 10, 3, 14, 5);
      expect(FileNamePattern.dateTime.format(t), 'Scan 2026-10-03 14.05');
      expect(FileNamePattern.date.format(t), 'Scan 2026-10-03');
      expect(FileNamePattern.compact.format(t), 'Scan_20261003_1405');
      expect(PdfExporter.defaultScanName(t), FileNamePattern.dateTime.format(t));
    });

    test('choices survive a restart and a damaged file falls back to defaults', () async {
      makeTmp();
      ProviderContainer launch() =>
          ProviderContainer(overrides: [pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp))]);
      final first = launch();
      final settings = first.read(appSettingsProvider.notifier);
      await settings.settled;
      settings
        ..setThemeMode(ThemeMode.dark)
        ..setDefaultFilter(DocumentFilter.grayscale)
        ..setKeepOriginals(false);
      await settings.settled;
      first.dispose();

      final file = File(p.join(tmp.path, AppSettingsStore.settingsFile));
      expect(jsonDecode(file.readAsStringSync()), containsPair('themeMode', 'dark'));

      final second = launch();
      await second.read(appSettingsProvider.notifier).settled;
      final back = second.read(appSettingsProvider);
      expect(
        (back.themeMode, back.defaultFilter, back.keepOriginals),
        (ThemeMode.dark, DocumentFilter.grayscale, false),
      );
      expect(back.autoCropOnImport, isTrue, reason: 'untouched choices keep their default');
      expect(second.read(themeModeProvider), ThemeMode.dark);
      second.dispose();

      file.writeAsStringSync('nonsense');
      final third = launch();
      await third.read(appSettingsProvider.notifier).settled;
      expect(third.read(appSettingsProvider), const AppSettings());
      third.dispose();
    });
  });

  group('new pages follow the settings', () {
    late ProviderContainer container;

    Future<void> setUpContainer() async {
      makeTmp();
      final paths = [
        for (var i = 0; i < 2; i++)
          (File('${tmp.path}/scan$i.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)))).path,
      ];
      container = ProviderContainer(
        overrides: [
          scannerServiceProvider.overrideWithValue(_FakeScanner(paths)),
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
          photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer()),
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
        ],
      );
      addTearDown(container.dispose);
    }

    test('scanned pages start with the default filter, and earlier pages keep theirs', () async {
      await setUpContainer();
      final scan = container.read(scanControllerProvider.notifier);
      await scan.scan(ScanSource.camera);
      expect(
        container.read(scanControllerProvider).pages.map((p) => p.recipe.filter),
        everyElement(DocumentFilter.original),
      );

      container.read(appSettingsProvider.notifier).setDefaultFilter(DocumentFilter.blackWhite);
      await scan.scan(ScanSource.camera);
      expect(container.read(scanControllerProvider).pages.map((p) => p.recipe.filter), [
        DocumentFilter.original,
        DocumentFilter.original,
        DocumentFilter.blackWhite,
        DocumentFilter.blackWhite,
      ]);
    });

    test('imported photos get the default filter, with or without auto-crop', () async {
      await setUpContainer();
      container.read(appSettingsProvider.notifier).setDefaultFilter(DocumentFilter.grayscale);
      final scan = container.read(scanControllerProvider.notifier);
      final photos = [PickedPhoto(path: '${tmp.path}/scan0.jpg', name: 'scan0.jpg')];
      await scan.importPhotos(photos, autoCrop: true);
      await scan.importPhotos(photos, autoCrop: false);
      final pages = container.read(scanControllerProvider).pages;
      expect(pages.map((p) => p.recipe.filter), everyElement(DocumentFilter.grayscale));
      expect(pages[0].recipe.crop, FakePhotoAnalyzer.quad);
      expect(pages[1].recipe.crop.isFull, isTrue);
    });
  });

  group('import screen', () {
    testWidgets('the auto-crop switch starts from the setting', (tester) async {
      Future<void> pump(bool autoCrop) => tester.pumpWidget(
        MaterialApp(
          theme: buildLumaTheme(Brightness.light),
          home: ImportPhotosScreen(
            photos: const [PickedPhoto(path: '/x/a.jpg', name: 'a.jpg')],
            autoCrop: autoCrop,
          ),
        ),
      );
      await pump(false);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
      await tester.pumpWidget(const SizedBox());
      await pump(true);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    });
  });

  group('saving', () {
    late ProviderContainer container;
    late List<String> originals;

    Future<void> setUpContainer({LibraryStoreOverride? library}) async {
      makeTmp();
      originals = [
        for (var i = 0; i < 2; i++)
          (File('${tmp.path}/scan$i.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40)))).path,
      ];
      container = ProviderContainer(
        overrides: [
          scannerServiceProvider.overrideWithValue(_FakeScanner(originals)),
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
          pdfExporterProvider.overrideWithValue(
            _FakeExporter(File('${tmp.path}/out.pdf')..writeAsBytesSync(List.filled(2048, 0))),
          ),
          libraryStoreProvider.overrideWithValue(library?.call() ?? MemoryLibraryStore()),
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(scanControllerProvider.notifier).scan(ScanSource.camera);
    }

    Future<void> openSheetAndSave(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLumaTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(onPressed: () => showExportSheet(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> tapSave(WidgetTester tester) async {
      await tester.tap(find.text('Save PDF'));
      await tester.pump();
      // New pages get their working copies made in the background, which
      // shares the CPU with the export, so allow it real time to finish.
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    String nameField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('the name offered follows the file name setting', (tester) async {
      await tester.runAsync(setUpContainer);
      container.read(appSettingsProvider.notifier).setFileNamePattern(FileNamePattern.compact);
      await openSheetAndSave(tester);
      expect(nameField(tester), matches(RegExp(r'^Scan_\d{8}_\d{4}$')));
    });

    testWidgets('by default the page images stay after saving', (tester) async {
      await tester.runAsync(setUpContainer);
      await openSheetAndSave(tester);
      await tapSave(tester);
      expect(find.text('PDF saved'), findsOneWidget);
      expect(find.textContaining('removed from this device'), findsNothing);
      final pages = container.read(scanControllerProvider).pages;
      expect(pages, hasLength(2));
      expect(File(pages.first.originalPath).existsSync(), isTrue);
    });

    testWidgets('with Keep page images off they are deleted once the PDF is in the Library', (tester) async {
      await tester.runAsync(setUpContainer);
      container.read(appSettingsProvider.notifier).setKeepOriginals(false);
      final paths = [for (final p in container.read(scanControllerProvider).pages) p.originalPath];
      await openSheetAndSave(tester);
      await tapSave(tester);

      expect(find.text('PDF saved'), findsOneWidget);
      expect(find.text('2 pages · 2 KB'), findsNothing); // sizes are shown from the saved file
      expect(find.textContaining('2 pages'), findsOneWidget, reason: 'the result keeps the saved page count');
      expect(find.textContaining('removed from this device'), findsOneWidget);
      expect(container.read(scanControllerProvider).pages, isEmpty);
      for (final path in paths) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      expect(File('${tmp.path}/out.pdf').existsSync(), isTrue, reason: 'the saved PDF is kept');
    });

    testWidgets('if the PDF cannot be added to the Library the pages are kept', (tester) async {
      await tester.runAsync(() => setUpContainer(library: _FailingLibraryStore.new));
      container.read(appSettingsProvider.notifier).setKeepOriginals(false);
      await openSheetAndSave(tester);
      await tapSave(tester);
      expect(find.textContaining('could not be added to your Library'), findsOneWidget);
      expect(container.read(scanControllerProvider).pages, hasLength(2));
    });
  });

  group('Settings screen', () {
    late MemoryAppSettingsStore store;

    Future<void> openSettings(WidgetTester tester, {double textScale = 1, List overrides = const []}) async {
      store = MemoryAppSettingsStore();
      await pumpApp(tester, settings: store, textScale: textScale, overrides: overrides);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      // A tall screen so the whole list is built, not only what is visible.
      if (textScale == 1) {
        tester.view.physicalSize = const Size(1080, 7000);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('every preference says whether it changes existing files', (tester) async {
      await openSettings(tester);
      expect(find.textContaining('New scans only'), findsOneWidget);
      expect(find.textContaining('Applies to future imports'), findsOneWidget);
      expect(find.textContaining('Saved PDFs are never affected'), findsOneWidget);
      expect(find.textContaining('saved files keep their names'), findsOneWidget);
      expect(find.textContaining('No files are affected'), findsOneWidget);
    });

    testWidgets('changes are applied at once and written to the device', (tester) async {
      await openSettings(tester);
      await tester.ensureVisible(find.text('Keep page images after saving'));
      await tester.tap(find.text('Keep page images after saving'));
      await tester.pumpAndSettle();
      expect(find.textContaining('deleted as soon as the PDF is saved'), findsOneWidget);

      await tester.ensureVisible(find.text('Auto-crop imported photos'));
      await tester.tap(find.text('Auto-crop imported photos'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);

      // Written through to the (in-memory) store.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(
        (store.settings.keepOriginals, store.settings.autoCropOnImport, store.settings.themeMode),
        (false, false, ThemeMode.dark),
      );
    });

    testWidgets('the default filter and file name are picked from a list', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Default filter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pages already in a document are not changed'), findsOneWidget);
      await tester.tap(find.text('B&W'));
      await tester.pumpAndSettle();
      expect(find.textContaining('B&W. New scans only'), findsOneWidget);

      await tester.ensureVisible(find.text('File name'));
      await tester.tap(find.text('File name'));
      await tester.pumpAndSettle();
      expect(find.text(FileNamePattern.date.example), findsOneWidget);
      await tester.tap(find.text('Date only'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Date only, like Scan 2026-10-03'), findsOneWidget);
    });

    testWidgets('help, privacy and about', (tester) async {
      await openSettings(
        tester,
        overrides: [
          packageInfoProvider.overrideWith(
            (ref) => PackageInfo(appName: 'LumaScan', packageName: 'app.lumascan', version: '1.2.3', buildNumber: '45'),
          ),
        ],
      );
      await tester.ensureVisible(find.text('About LumaScan'));
      await tester.pumpAndSettle();
      expect(find.text('Version 1.2.3 (45)'), findsOneWidget);

      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.text('Scanning a page'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Privacy'));
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.textContaining('stay on this device'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Open-source licences'));
      await tester.tap(find.text('Open-source licences'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('fits at 200% text size', (tester) async {
      await openSettings(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(find.text('About LumaScan'), find.byType(ListView).last, const Offset(0, -300));
      expect(tester.takeException(), isNull);
    });
  });

  group('storage', () {
    test('usage is counted by what the files are for', () async {
      makeTmp();
      write('exports/Lease.pdf', 3000);
      write('thumbnails/t.jpg', 500);
      write('pages/a.jpg', 1000);
      write('renders/r.jpg', 2048);
      write('share/s.pdf', 1024);
      final usage = await PageStore(rootDir: () async => tmp).usage();
      expect((usage.savedPdfs, usage.pageOriginals, usage.cache), (3500, 1000, 3072));
      expect(usage.total, 7572);
    });

    test('usage of an empty or missing folder is zero', () async {
      makeTmp();
      final usage = await PageStore(rootDir: () async => tmp).usage();
      expect(usage.total, 0);
    });

    test('clearing the cache frees previews and smaller copies and nothing else', () async {
      makeTmp();
      final pdf = write('exports/Lease.pdf', 3000);
      final thumb = write('thumbnails/t.jpg', 500);
      final page = write('pages/a.jpg', 1000);
      final render = write('renders/r.jpg', 2048);
      final copy = write('share/s.pdf', 1024);
      final freed = await PageStore(rootDir: () async => tmp).clearCache();
      expect(freed, 3072);
      expect(render.existsSync(), isFalse);
      expect(copy.existsSync(), isFalse);
      for (final kept in [pdf, thumb, page]) {
        expect(kept.existsSync(), isTrue, reason: kept.path);
      }
    });

    testWidgets('Clear cache shows what it frees, keeps saved PDFs and reports the result', (tester) async {
      makeTmp();
      final pdf = write('exports/Lease.pdf', 3000);
      write('renders/r.jpg', 2048);
      write('share/s.pdf', 1024);
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final store = PageStore(rootDir: () async => tmp);
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [pageStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: buildLumaTheme(Brightness.light),
            home: const Scaffold(body: SingleChildScrollView(child: StorageSection())),
          ),
        ),
      );
      await settle();
      expect(find.text('3 KB'), findsNWidgets(2), reason: 'saved PDFs and cache are both 3 KB');

      await tester.tap(find.text('Clear cache'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This frees 3 KB'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear cache'));
      await settle();
      await tester.pumpAndSettle();
      expect(find.text('Cleared 3 KB'), findsOneWidget);
      expect(find.text('0 KB'), findsWidgets);
      expect(pdf.existsSync(), isTrue);
      expect(Directory('${tmp.path}/renders').existsSync(), isFalse);
    });
  });
}

typedef LibraryStoreOverride = MemoryLibraryStore Function();
