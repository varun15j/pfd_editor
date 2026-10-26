import 'package:lumascan/data/app_settings_store.dart';
import 'package:lumascan/data/library_store.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/data/plan_cache_store.dart';
import 'package:lumascan/data/ui_prefs_store.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/scan_document.dart';
import 'package:lumascan/domain/ui_prefs.dart';

/// Library and draft stores kept in memory, for widget tests where real file
/// I/O would not complete inside the fake clock.
class MemoryLibraryStore extends LibraryStore {
  MemoryLibraryStore([this.index = const LibraryIndex()]) : super(PageStore());

  LibraryIndex index;

  @override
  Future<LibraryIndex> load() async => index;

  @override
  Future<void> save(LibraryIndex index) async => this.index = index;

  @override
  Future<String?> writeThumbnail(String docId, ScanPage page) async => null;

  @override
  Future<void> deleteFiles(SavedDocument doc) async {}
}

class MemoryDraftStore extends DraftStore {
  MemoryDraftStore([this.pages = const []]) : super(PageStore());

  List<ScanPage> pages;
  ScanDocInfo? info;

  @override
  Future<SavedDraft> load() async => SavedDraft(pages: pages, info: info);

  @override
  Future<void> save(List<ScanPage> pages, {ScanDocInfo? info}) async {
    this.pages = pages;
    this.info = info;
  }

  /// Earlier documents by id.
  final parkedPages = <String, (ParkedDraft, List<ScanPage>)>{};

  @override
  Future<ParkedDraft> park(List<ScanPage> pages, {bool exported = false, ScanDocInfo? info}) async {
    final now = DateTime.now();
    final draft = ParkedDraft(
      id: 'p${parkedPages.length}',
      pageCount: pages.length,
      savedAt: now,
      exported: exported,
      cover: pages.first,
      info: info ?? ScanDocInfo(name: scanDocumentName(now), createdAt: now),
    );
    parkedPages[draft.id] = (draft, pages);
    return draft;
  }

  @override
  Future<List<ParkedDraft>> parked() async => [for (final e in parkedPages.values) e.$1].reversed.toList();

  @override
  Future<List<ScanPage>> loadParked(String id) async => parkedPages[id]?.$2 ?? const [];

  @override
  Future<void> deleteParked(String id) async => parkedPages.remove(id);

  @override
  Future<void> renameParked(String id, String name) async {
    final entry = parkedPages[id];
    if (entry != null) parkedPages[id] = (entry.$1.renamed(name), entry.$2);
  }
}

class MemoryUiPrefsStore extends UiPrefsStore {
  MemoryUiPrefsStore([this.prefs = const UiPrefs()]) : super(PageStore());

  UiPrefs prefs;

  @override
  Future<UiPrefs> load() async => prefs;

  @override
  Future<void> save(UiPrefs prefs) async => this.prefs = prefs;
}

/// Settings where new pages start with no filter, for tests about edits
/// where the untouched page is the baseline. Scans are enhanced by default.
MemoryAppSettingsStore plainPagesSettings() =>
    MemoryAppSettingsStore(const AppSettings(onboardingSeen: true, defaultFilter: DocumentFilter.original));

class MemoryAppSettingsStore extends AppSettingsStore {
  MemoryAppSettingsStore([this.settings = const AppSettings(onboardingSeen: true)]) : super(PageStore());

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async => this.settings = settings;
}

/// The last plan the store reported, kept in memory.
class MemoryPlanCacheStore extends PlanCacheStore {
  MemoryPlanCacheStore([this.plan]) : super(PageStore());

  AppPlan? plan;

  @override
  Future<AppPlan?> load() async => plan;

  @override
  Future<void> save(AppPlan plan) async => this.plan = plan;
}
