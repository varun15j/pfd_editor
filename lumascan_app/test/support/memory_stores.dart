import 'package:lumascan/data/library_store.dart';
import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/data/ui_prefs_store.dart';
import 'package:lumascan/domain/library.dart';
import 'package:lumascan/domain/models.dart';
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

  @override
  Future<List<ScanPage>> load() async => pages;

  @override
  Future<void> save(List<ScanPage> pages) async => this.pages = pages;
}

class MemoryUiPrefsStore extends UiPrefsStore {
  MemoryUiPrefsStore([this.prefs = const UiPrefs()]) : super(PageStore());

  UiPrefs prefs;

  @override
  Future<UiPrefs> load() async => prefs;

  @override
  Future<void> save(UiPrefs prefs) async => this.prefs = prefs;
}
