import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/debug/debug_panel.dart';
import 'package:lumascan/debug/image_profiler.dart';
import 'package:lumascan/debug/profile_location.dart';
import 'package:lumascan/debug/profile_sample.dart';
import 'package:lumascan/debug/profile_store.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/pages/page_image.dart';
import 'package:lumascan/imaging/page_renderer.dart';
import 'package:lumascan/imaging/render_queue.dart';
import 'package:lumascan/imaging/render_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/memory_stores.dart';
import 'support/pump_app.dart';

ProfileSample _sample(
  ProfileKind kind,
  double ms, {
  String? screen,
  int bytes = 0,
  Map<String, double> stages = const {},
}) => ProfileSample(
  at: DateTime(2026, 10, 5),
  kind: kind,
  totalMs: ms,
  screen: screen,
  sourceBytes: bytes,
  stageMs: stages,
);

void main() {
  sqfliteFfiInit();

  group('SqliteProfileStore', () {
    late SqliteProfileStore store;

    setUp(() => store = SqliteProfileStore(factory: databaseFactoryFfi, path: () async => inMemoryDatabasePath));
    tearDown(() => store.close());

    test('saves samples and averages them per kind and screen, slowest first', () async {
      final samples = [
        _sample(ProfileKind.workingCopy, 600, bytes: 3 * 1024 * 1024, stages: {'decode': 150, 'encode': 400}),
        _sample(ProfileKind.workingCopy, 800, bytes: 5 * 1024 * 1024, stages: {'decode': 250, 'encode': 500}),
        _sample(ProfileKind.shown, 40, screen: 'PageGallery'),
        _sample(ProfileKind.shown, 60, screen: 'PageGallery'),
        _sample(ProfileKind.shown, 900, screen: 'FilterScreen'),
      ];
      final memory = MemoryProfileStore();
      for (final s in samples) {
        await store.add(s);
        await memory.add(s);
      }
      expect(await store.count(), 5);

      final rows = await store.summary();
      expect(
        [for (final r in rows) (r.kind, r.screen, r.count)],
        [
          (ProfileKind.shown, 'FilterScreen', 1),
          (ProfileKind.workingCopy, null, 2),
          (ProfileKind.shown, 'PageGallery', 2),
        ],
      );
      final photos = rows[1];
      expect(photos.avgMs, 700);
      expect((photos.minMs, photos.maxMs), (600, 800));
      expect(photos.avgSourceMb, 4);
      expect(photos.avgStageMs, {'decode': 200, 'encode': 450});

      final fromMemory = await memory.summary();
      expect(
        [for (final r in fromMemory) (r.kind, r.screen, r.count, r.avgMs)],
        [for (final r in rows) (r.kind, r.screen, r.count, r.avgMs)],
      );
      expect(fromMemory[1].avgStageMs, photos.avgStageMs);

      final recent = await store.recent(limit: 2);
      expect(recent.map((s) => s.screen), ['FilterScreen', 'PageGallery']);

      await store.clear();
      expect(await store.count(), 0);
    });

    test('keeps the panel switches', () async {
      expect(await store.readFlag('enabled'), isNull);
      await store.writeFlag('enabled', true);
      await store.writeFlag('enabled', false);
      expect(await store.readFlag('enabled'), isFalse);
    });
  });

  group('keeping the data after uninstall', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('profile_location'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ProfileLocation location(String privateDir, {bool allow = true, bool android = true}) => ProfileLocation(
      sharedDir: allow ? '${tmp.path}/Documents/LumaScan/debug' : '${tmp.path}/blocked/LumaScan/debug',
      privateDir: () async => privateDir,
      requestAccess: () async => allow,
      isAndroid: android,
    );

    test('without access the database stays inside the app', () async {
      File('${tmp.path}/blocked').writeAsStringSync('a file, so no folder can be made under it');
      final where = location('${tmp.path}/app1', allow: false);
      expect(await where.resolve(), '${tmp.path}/app1/image_profile.db');
      expect(await where.requestShared(), isFalse);
    });

    test('iOS keeps it inside the app', () async {
      final where = location('${tmp.path}/app1', android: false);
      expect(await where.resolve(), '${tmp.path}/app1/image_profile.db');
    });

    test('moving to shared storage keeps what was recorded, and a reinstall finds it', () async {
      Directory('${tmp.path}/app1').createSync();
      // Recorded before access was given, inside the app.
      final blocked = location('${tmp.path}/app1', allow: false);
      File('${tmp.path}/blocked').writeAsStringSync('x');
      final first = SqliteProfileStore(factory: databaseFactoryFfi, path: blocked.resolve);
      final profiler = ImageProfiler(store: first, location: location('${tmp.path}/app1'), available: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      profiler.enabled = true;
      await first.add(_sample(ProfileKind.thumbnail, 42));
      expect(profiler.keptAfterUninstall, isFalse);

      // The panel's "Keep data after uninstall".
      final reopened = SqliteProfileStore(factory: databaseFactoryFfi, path: location('${tmp.path}/app1').resolve);
      final moved = ImageProfiler(store: reopened, location: location('${tmp.path}/app1'), available: true);
      expect(await moved.keepAfterUninstall(), isTrue);
      expect(moved.databasePath, '${tmp.path}/Documents/LumaScan/debug/image_profile.db');
      expect(await reopened.count(), 1);
      await first.close();
      await reopened.close();

      // Uninstall removes the app's folder; the new install opens the shared file.
      Directory('${tmp.path}/app1').deleteSync(recursive: true);
      Directory('${tmp.path}/app2').createSync();
      final reinstalled = SqliteProfileStore(factory: databaseFactoryFfi, path: location('${tmp.path}/app2').resolve);
      expect(await reinstalled.count(), 1);
      expect((await reinstalled.recent()).single.totalMs, 42);
      expect(await reinstalled.readFlag('enabled'), isTrue);
      await reinstalled.close();
    });
  });

  group('ImageProfiler', () {
    test('records nothing in release-like builds or while switched off', () async {
      final store = MemoryProfileStore();
      final off = ImageProfiler(store: store, available: false)..enabled = true;
      off.record(_sample(ProfileKind.shown, 10));
      final idle = ImageProfiler(store: store, available: true);
      idle.record(_sample(ProfileKind.shown, 10));
      expect(store.samples, isEmpty);
      expect(off.enabled, isFalse);
    });

    test('records when on, keeps live averages, and remembers the switch', () async {
      final store = MemoryProfileStore();
      final profiler = ImageProfiler(store: store, available: true);
      await Future<void>.delayed(Duration.zero);
      profiler.enabled = true;
      profiler.record(_sample(ProfileKind.thumbnail, 10));
      profiler.record(_sample(ProfileKind.thumbnail, 30));
      expect(store.samples, hasLength(2));
      expect(profiler.liveAverages[ProfileKind.thumbnail], (2, 20.0));

      final restarted = ImageProfiler(store: store, available: true);
      await Future<void>.delayed(Duration.zero);
      expect(restarted.enabled, isTrue);
    });
  });

  test('the render service reports each step of making a picture', () async {
    final tmp = Directory.systemTemp.createTempSync('profiled_render');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = PageStore(rootDir: () async => tmp);
    final source = File('${tmp.path}/photo.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 2000, height: 1500)));
    final page = ScanPage(
      id: 'p',
      originalPath: await store.importOriginal(source.path, 'p'),
      recipe: const EditRecipe(filter: DocumentFilter.grayscale),
    );
    final samples = MemoryProfileStore();
    final profiler = ImageProfiler(store: samples, available: true);
    await Future<void>.delayed(Duration.zero);
    profiler.enabled = true;

    await RenderService(store, queue: RenderQueue(concurrency: 1), profiler: profiler).render(page, maxDimension: 480);

    expect(samples.samples.map((s) => s.kind), [ProfileKind.workingCopy, ProfileKind.thumbnail]);
    final working = samples.samples.first;
    expect(working.sourceBytes, source.lengthSync());
    expect(working.stageMs.keys, containsAll(['read', 'decode', 'convert', 'resize', 'encode', 'write']));
    final thumb = samples.samples.last;
    expect(thumb.filter, 'grayscale');
    expect(thumb.stageMs.keys, containsAll(['decode', 'crop', 'filter', 'adjust', 'encode']));
    expect(thumb.totalMs, greaterThanOrEqualTo(thumb.stageMs['filter']!));
    expect((thumb.width, thumb.maxDimension), (480, 480));
  });

  group('debug panel and labels', () {
    late ImageProfiler profiler;

    setUp(() => profiler = ImageProfiler(store: MemoryProfileStore(), available: true));

    Future<void> pump(WidgetTester tester, Widget home) async {
      // Tall enough for the whole panel.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final store = PageStore(rootDir: () async => Directory.systemTemp);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageProfilerProvider.overrideWithValue(profiler),
            renderServiceProvider.overrideWithValue(_InstantRender(store, profiler)),
          ],
          child: MaterialApp(
            navigatorKey: debugNavigatorKey,
            builder: (context, child) => DebugPanelHost(child: child!),
            home: home,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('swiping in from the left edge opens the panel, which switches profiling on', (tester) async {
      await pump(tester, const Scaffold(body: Center(child: Text('home'))));
      expect(find.text('Profile image loading'), findsNothing);

      await tester.dragFrom(const Offset(4, 300), const Offset(250, 0));
      await tester.pumpAndSettle();
      expect(find.text('Profile image loading'), findsOneWidget);

      await tester.tap(find.text('Profile image loading'));
      await tester.pumpAndSettle();
      expect(profiler.enabled, isTrue);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Profile image loading'), findsNothing);
    });

    testWidgets('the panel opens the profiling report', (tester) async {
      await pump(tester, const Scaffold(body: Center(child: Text('home'))));
      await tester.dragFrom(const Offset(4, 300), const Offset(250, 0));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Open profiling report'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Open profiling report'));
      await tester.pumpAndSettle();
      expect(find.text('Image loading profile'), findsOneWidget);
      expect(find.textContaining('Nothing measured yet'), findsOneWidget);
    });

    testWidgets('with profiling on, each picture shows its load time in red and is recorded', (tester) async {
      profiler.enabled = true;
      await pump(
        tester,
        const Scaffold(
          body: PagesStripView(
            child: PageImage(
              page: ScanPage(id: 'a', originalPath: '/x.jpg'),
            ),
          ),
        ),
      );
      final label = find.textContaining(RegExp(r'^\d+ ms R$'));
      expect(label, findsOneWidget);
      expect(tester.widget<Text>(label).style!.color, const Color(0xFFD50000));
      final shown = profiler.recentSamples.single;
      expect((shown.kind, shown.screen, shown.origin), (ProfileKind.shown, 'PagesStripView', ProfileOrigin.rendered));

      profiler.showLabels = false;
      await tester.pump();
      expect(label, findsNothing);
    });

    testWidgets('with profiling off, pictures have no label and nothing is recorded', (tester) async {
      await pump(
        tester,
        const Scaffold(
          body: SizedBox(
            width: 120,
            height: 160,
            child: PageImage(
              page: ScanPage(id: 'a', originalPath: '/x.jpg'),
            ),
          ),
        ),
      );
      expect(find.textContaining(' ms'), findsNothing);
      expect(profiler.recentSamples, isEmpty);
    });
  });

  group('Settings', () {
    Future<void> openSettings(WidgetTester tester, {required bool debug}) async {
      await pumpApp(
        tester,
        settings: MemoryAppSettingsStore(const AppSettings(onboardingSeen: true)),
        overrides: [
          imageProfilerProvider.overrideWithValue(ImageProfiler(store: MemoryProfileStore(), available: debug)),
        ],
      );
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
    }

    testWidgets('debug builds link to the profiling report', (tester) async {
      await openSettings(tester, debug: true);
      await tester.scrollUntilVisible(
        find.text('Image loading profile'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Image loading profile'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing measured yet'), findsOneWidget);
    });

    testWidgets('other builds have no developer section', (tester) async {
      await openSettings(tester, debug: false);
      expect(find.text('Image loading profile', skipOffstage: false), findsNothing);
    });
  });
}

/// Stands in for a screen, to check the screen name a sample is filed under.
class PagesStripView extends StatelessWidget {
  const PagesStripView({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: 120, height: 160, child: child);
}

/// Hands back a picture at once, as if it had just been rendered.
class _InstantRender extends RenderService {
  _InstantRender(super.store, ImageProfiler profiler) : super(profiler: profiler);

  @override
  Future<RenderedImage> render(ScanPage page, {EditRecipe? recipe, int maxDimension = RenderService.previewSize}) =>
      Future.value(RenderedImage(page.originalPath, 300, 400, sourceBytes: 1000, stageMicros: const {'filter': 5000}));
}
