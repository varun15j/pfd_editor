import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/scan_document.dart';
import 'package:lumascan/domain/ui_prefs.dart';
import 'package:lumascan/features/capture/scan_tips.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_service.dart';
import 'package:lumascan/ui/state_views.dart';

import 'support/fake_batch_camera.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';

/// A camera whose access is turned off; it never takes a photo.
FakeBatchCamera _blockedCamera() => FakeBatchCamera(Directory.systemTemp, deny: true);

/// Page images that cannot be drawn, so screens showing pages that are not
/// on disk settle at once with the broken-image icon.
class _NoImages extends RenderService {
  _NoImages() : super(PageStore());

  @override
  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = RenderService.previewSize}) =>
      Future.error(const FileSystemException('not in tests'));
}

final _noImages = renderServiceProvider.overrideWithValue(_NoImages());

class _BrokenLibraryStore extends MemoryLibraryStore {
  @override
  Future<LibraryIndex> load() async => throw const FileSystemException('disk unavailable');
}

/// WCAG relative-luminance contrast ratio.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

MemoryUiPrefsStore tipsSeen() => MemoryUiPrefsStore(const UiPrefs(dismissedCards: {scanTipsId}));

void main() {
  group('app shell', () {
    testWidgets('home offers scan, import and PDF editing', (tester) async {
      await pumpApp(tester);
      expect(find.text('LumaScan'), findsOneWidget);
      for (final label in ['Scan', 'Import', 'Edit PDF']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.text('Your scans will show up here.'), findsOneWidget);
      expect(find.byTooltip('Create'), findsOneWidget);
    });

    testWidgets('bottom bar switches between the four tabs', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();
      expect(find.text('No saved documents yet'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Tools'));
      await tester.pumpAndSettle();
      expect(find.text('Merge PDFs'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Scan something new'), findsOneWidget);
    });

    testWidgets('selected tab is announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      expect(tester.getSemantics(find.bySemanticsLabel('Home')), isSemantics(isSelected: true, isButton: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Library')), isSemantics(isSelected: false, isButton: true));
      handle.dispose();
    });

    testWidgets('blocked camera explains and links to Settings', (tester) async {
      await pumpApp(
        tester,
        prefs: tipsSeen(),
        overrides: [batchCameraProvider.overrideWithValue(() => _blockedCamera())],
      );
      await tester.tap(find.bySemanticsLabel('Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Discard all captured photos and changes'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access needed'), findsNothing);
    });

    testWidgets('scanning from the Create sheet uses the same camera flow', (tester) async {
      await pumpApp(
        tester,
        prefs: tipsSeen(),
        overrides: [batchCameraProvider.overrideWithValue(() => _blockedCamera())],
      );
      await tester.tap(find.byTooltip('Create'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan document'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access needed'), findsOneWidget);
    });

    testWidgets('appearance setting switches to the dark theme', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Appearance'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(LumaColors.of(context).background, LumaColors.dark.background);
    });

    testWidgets('home and tabs fit at 200% text size', (tester) async {
      await pumpApp(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      for (final tab in ['Library', 'Tools', 'Settings']) {
        await tester.tap(find.bySemanticsLabel(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets('bottom bar items and quick actions are at least 48 dp tall', (tester) async {
      await pumpApp(tester);
      for (final label in ['Home', 'Library', 'Tools', 'Settings', 'Scan', 'Import', 'Edit PDF']) {
        expect(tester.getSize(find.bySemanticsLabel(label)).height, greaterThanOrEqualTo(minTapTarget), reason: label);
      }
    });
  });

  group('library and draft', () {
    final doc = SavedDocument(
      id: 'd1',
      name: 'Rental agreement',
      pdfPath: '/nowhere/exports/Rental agreement.pdf',
      pageCount: 3,
      type: ScanType.document,
      createdAt: DateTime(2026, 3, 7),
      modifiedAt: DateTime(2026, 3, 7),
    );
    final library = const LibraryIndex().copyWith(documents: [doc]);

    testWidgets('library lists saved documents with name, date and page count', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(library));
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();
      expect(find.text('No saved documents yet'), findsNothing);
      expect(find.text('Rental agreement'), findsWidgets);
      expect(find.text('7 Mar 2026 · 3 pages'), findsWidgets);
    });

    testWidgets('home shows recent documents instead of the empty hint', (tester) async {
      await pumpApp(tester, library: MemoryLibraryStore(library));
      expect(find.text('Rental agreement'), findsOneWidget);
      expect(find.text('Your scans will show up here.'), findsNothing);
    });

    testWidgets('a scan saved before the app was killed is on home under its name', (tester) async {
      final store = MemoryDraftStore(const [
        ScanPage(id: 'a', originalPath: '/nowhere/a.jpg'),
        ScanPage(id: 'b', originalPath: '/nowhere/b.jpg'),
      ])..info = ScanDocInfo(name: '2026-10-11 Scan', createdAt: DateTime(2026, 10, 11, 9));
      await pumpApp(tester, draft: store, overrides: [_noImages]);
      expect(find.text('2026-10-11 Scan'), findsOneWidget);
      expect(find.textContaining('2 pages · Images'), findsOneWidget);
    });

    testWidgets('earlier scans are listed on home and open again to add pages', (tester) async {
      final store = MemoryDraftStore(const [
        ScanPage(id: 'a', originalPath: '/nowhere/a.jpg'),
        ScanPage(id: 'b', originalPath: '/nowhere/b.jpg'),
      ])..info = ScanDocInfo(name: '2026-10-11 Scan 2', createdAt: DateTime(2026, 10, 11, 10));
      await store.park(
        const [
          ScanPage(id: 'x', originalPath: '/nowhere/x.jpg'),
          ScanPage(id: 'y', originalPath: '/nowhere/y.jpg'),
          ScanPage(id: 'z', originalPath: '/nowhere/z.jpg'),
        ],
        exported: true,
        info: ScanDocInfo(name: '2026-10-11 Scan', createdAt: DateTime(2026, 10, 11, 9)),
      );
      await pumpApp(tester, draft: store, overrides: [_noImages]);
      expect(find.text('2026-10-11 Scan 2'), findsOneWidget);
      expect(find.textContaining('3 pages · Images, PDF made'), findsOneWidget);

      await tester.tap(find.text('2026-10-11 Scan'));
      // Page images that do not exist keep their spinners going, so no settle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(store.pages.map((p) => p.id), ['x', 'y', 'z']);
      expect(store.info?.name, '2026-10-11 Scan');
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The other scan is kept, now as an earlier one, with its own name.
      expect(find.text('2026-10-11 Scan'), findsOneWidget);
      expect(find.text('2026-10-11 Scan 2'), findsOneWidget);
    });

    testWidgets('a scan on home can be renamed and deleted from its menu', (tester) async {
      final store = MemoryDraftStore();
      await store.park(const [
        ScanPage(id: 'x', originalPath: '/nowhere/x.jpg'),
      ], info: ScanDocInfo(name: '2026-10-11 Scan', createdAt: DateTime(2026, 10, 11, 9)));
      await pumpApp(tester, draft: store, overrides: [_noImages]);
      await tester.tap(find.byTooltip('More for 2026-10-11 Scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Bills');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Bills'), findsOneWidget);
      expect(store.parkedPages.values.single.$1.name, 'Bills');

      await tester.tap(find.byTooltip('More for Bills'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Bills'), findsNothing);
      expect(store.parkedPages, isEmpty);
    });

    testWidgets('a library that fails to load offers a retry', (tester) async {
      await pumpApp(tester, library: _BrokenLibraryStore());
      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Library could not be opened'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('design tokens', () {
    for (final (name, c) in [('light', LumaColors.light), ('dark', LumaColors.dark)]) {
      test('$name text and actions meet WCAG AA contrast', () {
        final pairs = {
          'ink on surface': (c.ink, c.surface),
          'ink on background': (c.ink, c.background),
          'muted on surface': (c.muted, c.surface),
          'muted on background': (c.muted, c.background),
          'muted on raised': (c.muted, c.surfaceRaised),
          'on-accent on accent': (c.onAccent, c.accent),
          'accent on surface': (c.accent, c.surface),
          'on-premium on premium': (c.onPremium, c.premium),
          'danger on surface': (c.danger, c.surface),
        };
        pairs.forEach((label, p) {
          expect(contrast(p.$1, p.$2), greaterThanOrEqualTo(4.5), reason: '$name $label');
        });
      });
    }
  });

  group('shared state widgets', () {
    Future<void> pumpIn(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: buildLumaTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );

    testWidgets('empty state runs its action', (tester) async {
      var tapped = 0;
      await pumpIn(
        tester,
        EmptyState(
          icon: Icons.inbox,
          title: 'Nothing here',
          message: 'Add one',
          actionLabel: 'Add',
          onAction: () => tapped++,
        ),
      );
      await tester.tap(find.text('Add'));
      expect(tapped, 1);
    });

    testWidgets('error state offers retry', (tester) async {
      var retried = 0;
      await pumpIn(tester, ErrorState(message: 'Could not load', onRetry: () => retried++));
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('loading list is announced once', (tester) async {
      await pumpIn(tester, const LoadingList(label: 'Loading documents'));
      expect(find.bySemanticsLabel('Loading documents'), findsOneWidget);
    });

    testWidgets('premium badge says Premium, not colour alone', (tester) async {
      await pumpIn(tester, const Center(child: PremiumBadge()));
      expect(find.text('Premium'), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium_outlined), findsOneWidget);
    });
  });
}
