import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/cloud/cloud_http.dart';
import 'package:lumascan/data/cloud/google_drive_provider.dart';
import 'package:lumascan/data/cloud/onedrive_provider.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/cloud_storage.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/photo_import.dart';
import 'package:lumascan/export/word/word_service.dart';
import 'package:lumascan/features/capture/pdf_import.dart';
import 'package:lumascan/features/cloud/cloud_accounts.dart';
import 'package:lumascan/features/cloud/cloud_importer.dart';
import 'package:lumascan/features/library/library_controller.dart';
import 'package:lumascan/features/merge/pdf_inspector.dart';
import 'package:lumascan/features/open/open_progress.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:path/path.dart' as p;

import 'support/fake_photos.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';
import 'support/temp_dir.dart';

/// A cloud account held in memory: a folder tree of entries by parent id.
class FakeCloudProvider extends CloudStorageProvider {
  FakeCloudProvider(
    this.id, {
    this.availability = CloudAvailability.ready,
    this.saved,
    this.tree = const {},
    this.connectAs = const CloudAccount(name: 'Varun', email: 'varun@example.com'),
    this.listError,
  });

  @override
  final CloudProviderId id;
  @override
  final CloudAvailability availability;
  CloudAccount? saved;
  final Map<String?, List<CloudEntry>> tree;
  final CloudAccount connectAs;
  Object? listError;
  final listed = <String?>[];
  final downloaded = <String>[];
  var disconnected = false;

  @override
  Future<CloudAccount?> restore() async => saved;

  @override
  Future<CloudAccount> connect() async => saved = connectAs;

  @override
  Future<void> disconnect() async {
    disconnected = true;
    saved = null;
  }

  @override
  Future<List<CloudEntry>> list(String? folderId) async {
    listed.add(folderId);
    final error = listError;
    if (error != null) throw error;
    return sortCloudEntries(tree[folderId] ?? const []);
  }

  @override
  Future<File> download(CloudEntry entry, Directory directory) async {
    downloaded.add(entry.id);
    return File(p.join(directory.path, 'download-${entry.id}'))..writeAsStringSync('%PDF-1.7');
  }
}

class _RecordingImporter implements CloudImporter {
  final calls = <({String name, CloudEntryKind kind, String? folderId})>[];

  @override
  Future<SavedDocument> import(
    File file, {
    required String name,
    required CloudEntryKind kind,
    String? folderId,
  }) async {
    calls.add((name: name, kind: kind, folderId: folderId));
    final now = DateTime(2026, 10, 13);
    return SavedDocument(
      id: 'd${calls.length}',
      name: p.basenameWithoutExtension(name),
      pdfPath: '/tmp/${p.basenameWithoutExtension(name)}.pdf',
      pageCount: 2,
      type: ScanType.pdf,
      createdAt: now,
      modifiedAt: now,
      folderId: folderId,
    );
  }
}

/// A service reached through the system file picker, like Google Drive.
class _PickerProvider extends FakeCloudProvider {
  _PickerProvider(this.pick) : super(CloudProviderId.googleDrive);

  final PickedCloudFile Function() pick;

  @override
  bool get usesSystemPicker => true;

  @override
  Future<PickedCloudFile?> pickFile({void Function()? onFetching}) async => pick();
}

/// Makes three small page images for any PDF, as pdfrx would.
class _FakePagesMaker implements PdfPagesMaker {
  final opened = <String>[];
  final dirs = <Directory>[];

  @override
  Future<List<PickedPhoto>> makePages(
    BuildContext context,
    String path,
    String name,
    Directory dir,
    OpenProgress progress,
  ) async {
    opened.add(path);
    dirs.add(dir);
    final jpeg = img.encodeJpg(img.Image(width: 60, height: 80)..clear(img.ColorRgb8(250, 250, 250)));
    final photos = [
      for (var i = 1; i <= 3; i++)
        PickedPhoto(path: (File(p.join(dir.path, 'page_$i.jpg'))..writeAsBytesSync(jpeg)).path, name: 'page $i'),
    ];
    return photos;
  }
}

class _FakeInspector implements PdfInspector {
  _FakeInspector(this.info);
  final PdfInfo info;

  @override
  Future<PdfInfo> inspect(String path) async => info;
}

class _FakeWord implements WordService {
  _FakeWord(this.output);
  final File output;
  final converted = <(String, String)>[];

  @override
  Future<WordPdfFile> wordToPdf(String docxPath, {required String name}) async {
    converted.add((docxPath, name));
    return WordPdfFile(output, 3);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _drive = [
  CloudEntry(id: 'f-work', name: 'Work', kind: CloudEntryKind.folder),
  CloudEntry(id: 'lease', name: 'Lease.pdf', kind: CloudEntryKind.pdf, sizeBytes: 204800),
  CloudEntry(id: 'notes', name: 'Notes.docx', kind: CloudEntryKind.word),
  CloudEntry(id: 'photo', name: 'Holiday.jpg', kind: CloudEntryKind.other),
];

const _work = [CloudEntry(id: 'invoice', name: 'Invoice.pdf', kind: CloudEntryKind.pdf)];

void main() {
  group('Google Drive', () {
    test('uses the system file picker, so there is no sign-in or Drive scope', () async {
      final drive = GoogleDriveProvider();

      expect(drive.id, CloudProviderId.googleDrive);
      expect(drive.usesSystemPicker, isTrue);
      expect(await drive.restore(), isNull);
      expect(drive.connect, throwsUnsupportedError);
      expect(() => drive.list(null), throwsUnsupportedError);
    });
  });

  group('OneDrive API', () {
    test('follows nextLink pages and reads the account name', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/me')) {
          return http.Response(jsonEncode({'displayName': 'Varun', 'userPrincipalName': 'varun@outlook.com'}), 200);
        }
        if (request.url.host == 'next.example') {
          return http.Response(
            jsonEncode({
              'value': [
                {'id': 'c', 'name': 'Report.PDF', 'size': 10},
              ],
            }),
            200,
          );
        }
        expect(request.url.path, '/v1.0/me/drive/items/folder%201/children');
        return http.Response(
          jsonEncode({
            '@odata.nextLink': 'https://next.example/page2',
            'value': [
              {
                'id': 'a',
                'name': 'Taxes',
                'folder': {'childCount': 2},
              },
              {'id': 'b', 'name': 'Letter.docx', 'file': {}},
            ],
          }),
          200,
        );
      });
      final api = OneDriveApi(CloudHttp(client, () async => 't'));

      final entries = await api.list('folder 1');
      final me = await api.me();

      expect(entries.map((e) => (e.name, e.kind)), [
        ('Taxes', CloudEntryKind.folder),
        ('Letter.docx', CloudEntryKind.word),
        ('Report.PDF', CloudEntryKind.pdf),
      ]);
      expect(me.label, 'Varun (varun@outlook.com)');
    });
  });

  group('CloudHttp', () {
    test('drops a rejected token and tries once more', () async {
      var calls = 0;
      final dropped = <String>[];
      final client = MockClient((request) async {
        calls++;
        return request.headers['Authorization'] == 'Bearer fresh'
            ? http.Response('{"ok": true}', 200)
            : http.Response('', 401);
      });
      var token = 'stale';
      final http0 = CloudHttp(
        client,
        () async => token,
        onRejected: (t) async {
          dropped.add(t);
          token = 'fresh';
        },
      );

      expect(await http0.getJson(Uri.parse('https://x.test')), {'ok': true});
      expect(dropped, ['stale']);
      expect(calls, 2);
    });

    test('a second rejection means the sign-in has expired', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final http0 = CloudHttp(client, () async => 't', onRejected: (_) async {});

      expect(http0.getJson(Uri.parse('https://x.test')), throwsA(isA<CloudSignInExpired>()));
    });

    test('passes on the message the service gave', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 403, 'message': 'Drive API is not enabled'},
          }),
          403,
        ),
      );
      final http0 = CloudHttp(client, () async => 't');

      expect(
        http0.getJson(Uri.parse('https://x.test')),
        throwsA(isA<CloudHttpException>().having((e) => e.toString(), 'message', 'Drive API is not enabled')),
      );
    });
  });

  group('CloudImporter', () {
    late Directory tmp;
    late MemoryLibraryStore libraryStore;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_cloud_import');
      libraryStore = MemoryLibraryStore(
        const LibraryIndex(
          folders: [LibraryFolder(id: 'f1', name: 'Bills')],
        ),
      );
    });
    tearDown(() => deleteTemp(tmp));

    ProviderContainer container({PdfInfo info = const PdfInfo.ok(4), WordService? word}) {
      final c = ProviderContainer(
        overrides: [
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => tmp)),
          libraryStoreProvider.overrideWithValue(libraryStore),
          pdfInspectorProvider.overrideWithValue(_FakeInspector(info)),
          if (word != null) wordServiceProvider.overrideWithValue(word),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    File download(String name, String content) => File(p.join(tmp.path, name))..writeAsStringSync(content);

    test('saves a PDF to the Library in the chosen folder', () async {
      final c = container();
      await c.read(libraryProvider.future);

      final saved = await c
          .read(cloudImporterProvider)
          .import(download('x.pdf', '%PDF-1.7'), name: 'Lease.pdf', kind: CloudEntryKind.pdf, folderId: 'f1');

      expect(saved.name, 'Lease');
      expect(saved.pageCount, 4);
      expect(saved.folderId, 'f1');
      expect(File(saved.pdfPath).readAsStringSync(), '%PDF-1.7');
      expect(p.dirname(saved.pdfPath), p.join(tmp.path, 'exports'));
      final doc = libraryStore.index.documents.single;
      expect(doc.folderId, 'f1');
      expect(doc.type, ScanType.pdf);
    });

    test('keeps a second import with the same name as a separate file', () async {
      final c = container();
      await c.read(libraryProvider.future);
      final importer = c.read(cloudImporterProvider);

      final first = await importer.import(download('1.pdf', 'a'), name: 'Lease.pdf', kind: CloudEntryKind.pdf);
      final second = await importer.import(download('2.pdf', 'b'), name: 'Lease.pdf', kind: CloudEntryKind.pdf);

      expect(p.basename(second.pdfPath), 'Lease (2).pdf');
      expect(first.id, isNot(second.id));
      expect(libraryStore.index.documents, hasLength(2));
    });

    test('names a Google Doc after its title', () async {
      final c = container();
      await c.read(libraryProvider.future);

      final saved = await c
          .read(cloudImporterProvider)
          .import(download('g.pdf', '%PDF'), name: 'Q3 plan v1.2', kind: CloudEntryKind.googleDoc);

      expect(saved.name, 'Q3 plan v1.2');
      expect(saved.folderId, isNull);
    });

    test('turns a Word file into a PDF through the Word import', () async {
      final made = File(p.join(tmp.path, 'Notes.pdf'))..writeAsStringSync('%PDF');
      final word = _FakeWord(made);
      final c = container(word: word);
      await c.read(libraryProvider.future);
      final source = download('w.docx', 'PK');

      final saved = await c
          .read(cloudImporterProvider)
          .import(source, name: 'Notes.docx', kind: CloudEntryKind.word, folderId: 'f1');

      expect(word.converted, [(source.path, 'Notes')]);
      expect(saved.pageCount, 3);
      expect(libraryStore.index.documents.single.folderId, 'f1');
    });

    test('refuses a locked PDF with a message and adds nothing', () async {
      final c = container(info: const PdfInfo.problem(PdfProblem.locked));
      await c.read(libraryProvider.future);

      await expectLater(
        c.read(cloudImporterProvider).import(download('l.pdf', 'x'), name: 'Bank.pdf', kind: CloudEntryKind.pdf),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('locked with a password'))),
      );
      expect(libraryStore.index.documents, isEmpty);
    });
  });

  group('Accounts screens', () {
    late FakeCloudProvider drive;
    late FakeCloudProvider oneDrive;
    late FakeCloudProvider icloud;
    late _RecordingImporter importer;
    late Directory tmp;
    late Directory downloads;
    late _FakePagesMaker pages;

    setUp(() {
      // Google Drive itself uses the system picker; OneDrive is the service
      // with a sign-in and a browse screen.
      drive = FakeCloudProvider(CloudProviderId.googleDrive, availability: CloudAvailability.notConfigured);
      oneDrive = FakeCloudProvider(CloudProviderId.oneDrive, tree: {null: _drive, 'f-work': _work});
      icloud = FakeCloudProvider(CloudProviderId.iCloudDrive, availability: CloudAvailability.unsupportedPlatform);
      importer = _RecordingImporter();
      tmp = Directory.systemTemp.createTempSync('lumascan_cloud_ui');
      downloads = Directory(p.join(tmp.path, 'downloads'))..createSync();
      pages = _FakePagesMaker();
    });

    tearDown(() => deleteTemp(tmp));

    Future<void> openAccounts(WidgetTester tester, {LibraryIndex index = const LibraryIndex()}) async {
      await pumpApp(
        tester,
        library: MemoryLibraryStore(index),
        overrides: [
          cloudProvidersProvider.overrideWithValue([drive, oneDrive, icloud]),
          cloudImporterProvider.overrideWithValue(importer),
          cloudDownloadDirProvider.overrideWithValue(() async => downloads),
          pdfPagesMakerProvider.overrideWithValue(pages),
          pdfImportDirProvider.overrideWithValue(() async => Directory(p.join(tmp.path, 'pages')).create()),
          pageStoreProvider.overrideWithValue(PageStore(rootDir: () async => Directory(p.join(tmp.path, 'store')))),
          photoAnalyzerProvider.overrideWithValue(FakePhotoAnalyzer()),
        ],
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accounts'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the three services and why one cannot be used', (tester) async {
      await openAccounts(tester);

      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Not set up in this build yet'), findsOneWidget);
      expect(find.text('Microsoft OneDrive'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('iCloud Drive'), findsOneWidget);
      expect(find.text('Only on iPhone and iPad'), findsOneWidget);
      expect(find.text('Connect Google Drive'), findsNothing);
    });

    testWidgets('connects, shows the account and disconnects', (tester) async {
      await openAccounts(tester);

      await tester.tap(find.text('Connect Microsoft OneDrive'));
      await tester.pumpAndSettle();
      expect(find.text('Connected as Varun (varun@example.com)'), findsOneWidget);
      expect(find.text('Browse files'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await tester.pumpAndSettle();
      expect(oneDrive.disconnected, isTrue);
      expect(find.text('Not connected'), findsOneWidget);
    });

    testWidgets('a saved sign-in shows as connected on the next visit', (tester) async {
      oneDrive.saved = const CloudAccount(name: 'Varun', email: 'varun@example.com');
      await openAccounts(tester);

      expect(find.text('Connected as Varun (varun@example.com)'), findsOneWidget);
    });

    testWidgets('browses into a folder and opens a PDF as editable pages in Batch review', (tester) async {
      oneDrive.saved = const CloudAccount(name: 'Varun');
      await openAccounts(tester);

      await tester.tap(find.text('Browse files'));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Lease.pdf'), findsOneWidget);
      expect(find.textContaining('Only PDF and Word files'), findsOneWidget);

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(oneDrive.listed, [null, 'f-work']);
      // Real file copies happen on the way, so let real time pass.
      await tester.tap(find.text('Invoice.pdf'));
      for (var i = 0; i < 100 && find.text('Batch review').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 500));

      // No Library folder to choose and nothing saved to the Library.
      expect(find.text('Import to'), findsNothing);
      expect(importer.calls, isEmpty);
      expect(oneDrive.downloaded, ['invoice']);
      expect(pages.opened.single, endsWith('download-invoice'));
      expect(find.text('Batch review'), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.text('Batch review')));
      final draft = container.read(scanControllerProvider);
      expect(draft.pages, hasLength(3));
      expect(draft.info?.name, 'Invoice');
      // Each page starts uncropped: a PDF page is already a page.
      expect(draft.pages.every((pg) => pg.recipe.crop.isFull), isTrue);
      // The download and the page images made from it are gone.
      expect(File(pages.opened.single).existsSync(), isFalse);
      expect(pages.dirs.single.existsSync(), isFalse);
    });

    testWidgets('a PDF chosen in the system picker opens as pages in Batch review', (tester) async {
      final picked = File(p.join(downloads.path, 'Lease.pdf'))..writeAsStringSync('%PDF-1.7');
      drive = _PickerProvider(() => PickedCloudFile(name: 'Lease.pdf', file: picked));
      await openAccounts(tester);

      await tester.tap(find.text('Choose a file'));
      for (var i = 0; i < 100 && find.text('Batch review').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Import to'), findsNothing);
      expect(importer.calls, isEmpty);
      expect(find.text('Batch review'), findsOneWidget);
      final draft = ProviderScope.containerOf(tester.element(find.text('Batch review'))).read(scanControllerProvider);
      expect(draft.pages, hasLength(3));
      expect(draft.info?.name, 'Lease');
      expect(picked.existsSync(), isFalse);
    });

    testWidgets('imports a Word file to the top of the Library', (tester) async {
      oneDrive.saved = const CloudAccount(name: 'Varun');
      await openAccounts(tester);
      await tester.tap(find.text('Browse files'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notes.docx'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library (no folder)'));
      await tester.pumpAndSettle();

      expect(importer.calls.single, (name: 'Notes.docx', kind: CloudEntryKind.word, folderId: null));
      expect(find.text('Saved Notes.pdf to your Library'), findsOneWidget);
      // The Send button must not keep it up for ever, over the next screen.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Saved Notes.pdf to your Library'), findsNothing);
    });

    testWidgets('files that are not PDF or Word cannot be imported', (tester) async {
      oneDrive.saved = const CloudAccount(name: 'Varun');
      await openAccounts(tester);
      await tester.tap(find.text('Browse files'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Holiday.jpg'));
      await tester.pumpAndSettle();

      expect(find.text('Import to'), findsNothing);
      expect(importer.calls, isEmpty);
    });

    testWidgets('an expired sign-in sends the user back to connect again', (tester) async {
      oneDrive.saved = const CloudAccount(name: 'Varun');
      oneDrive.listError = const CloudSignInExpired();
      await openAccounts(tester);
      await tester.tap(find.text('Browse files'));
      await tester.pumpAndSettle();

      expect(find.text('The sign-in has expired. Connect the account again.'), findsOneWidget);
      await tester.tap(find.text('Back to Accounts'));
      await tester.pumpAndSettle();

      expect(find.text('Connect Microsoft OneDrive'), findsOneWidget);
    });
  });
}
