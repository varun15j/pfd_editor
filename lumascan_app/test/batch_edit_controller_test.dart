import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/features/pages/scan_controller.dart';
import 'package:lumascan/pdf_edit/annotations.dart';

import 'support/memory_stores.dart';

const _crop = CropQuad(NormPoint(0.1, 0.1), NormPoint(0.9, 0.1), NormPoint(0.9, 0.9), NormPoint(0.1, 0.9));

void main() {
  late MemoryDraftStore draft;
  late ProviderContainer container;

  setUp(() async {
    draft = MemoryDraftStore([
      for (var i = 0; i < 4; i++)
        ScanPage(
          id: 'p$i',
          originalPath: '/originals/p$i.jpg',
          recipe: EditRecipe(crop: i == 1 ? _crop : CropQuad.full, quarterTurns: i == 2 ? 1 : 0),
          annotations: i == 3
              ? const [TextAnnotation(id: 'a1', origin: NormPoint(0.5, 0.5), text: 'note', color: 0xff000000)]
              : const [],
        ),
    ]);
    container = ProviderContainer(overrides: [draftStoreProvider.overrideWithValue(draft)]);
    container.read(scanControllerProvider);
    await container.read(scanControllerProvider.notifier).draftSaved;
  });

  tearDown(() => container.dispose());

  ScanController controller() => container.read(scanControllerProvider.notifier);
  ScanState state() => container.read(scanControllerProvider);
  List<String> ids() => [for (final p in state().pages) p.id];

  test('rotatePages turns only the selected pages, in one undo step', () {
    controller().rotatePages({'p0', 'p2'});

    expect([for (final p in state().pages) p.recipe.quarterTurns], [1, 0, 2, 0]);
    expect(state().undoStack, hasLength(1));
    controller().undo();
    expect([for (final p in state().pages) p.recipe.quarterTurns], [0, 0, 1, 0]);
    controller().redo();
    expect([for (final p in state().pages) p.recipe.quarterTurns], [1, 0, 2, 0]);
  });

  test('rotatePages counter-clockwise wraps around', () {
    controller().rotatePages({'p0'}, clockwise: false);
    expect(state().pages.first.recipe.quarterTurns, 3);
  });

  test('rotatePages removes marks on rotated pages and says so beforehand', () {
    expect(controller().rotationDropsMarks({'p0', 'p1'}), isFalse);
    expect(controller().rotationDropsMarks({'p0', 'p3'}), isTrue);

    controller().rotatePages({'p0', 'p3'});

    expect(state().pages[3].annotations, isEmpty);
    controller().undo();
    expect(state().pages[3].annotations, hasLength(1));
  });

  test('applyEnhancementToPages copies only filter and adjustments', () {
    const look = EditRecipe(
      crop: CropQuad(NormPoint(0.3, 0.3), NormPoint(0.7, 0.3), NormPoint(0.7, 0.7), NormPoint(0.3, 0.7)),
      quarterTurns: 3,
      filter: DocumentFilter.blackWhite,
      brightness: 0.2,
      contrast: -0.1,
    );

    controller().applyEnhancementToPages({'p1', 'p2', 'p3'}, look);

    final pages = state().pages;
    expect(pages[0].recipe.filter, DocumentFilter.original);
    for (final p in pages.skip(1)) {
      expect(p.recipe.filter, DocumentFilter.blackWhite);
      expect(p.recipe.brightness, 0.2);
      expect(p.recipe.contrast, -0.1);
    }
    expect(pages[1].recipe.crop, _crop, reason: 'crop is never copied to another page');
    expect(pages[2].recipe.quarterTurns, 1);
    expect(pages[3].annotations, hasLength(1));
    expect(state().undoStack, hasLength(1));
  });

  test('removePages deletes the selection and one undo restores the order', () {
    controller().removePages({'p1', 'p3'});
    expect(ids(), ['p0', 'p2']);

    controller().undo();
    expect(ids(), ['p0', 'p1', 'p2', 'p3']);
  });

  test('unknown IDs are ignored and an all-unknown selection adds no undo step', () {
    controller().rotatePages({'p0', 'missing'});
    expect(state().pages.first.recipe.quarterTurns, 1);
    expect(state().undoStack, hasLength(1));

    controller().rotatePages({'missing'});
    controller().removePages({'missing'});
    controller().applyEnhancementToPages({'missing'}, const EditRecipe(filter: DocumentFilter.grayscale));
    expect(state().undoStack, hasLength(1));
    expect(ids(), ['p0', 'p1', 'p2', 'p3']);
  });

  test('batch changes reach the saved draft', () async {
    controller().removePages({'p0'});
    controller().rotatePages({'p1'});
    await controller().draftSaved;

    expect([for (final p in draft.pages) p.id], ['p1', 'p2', 'p3']);
    expect(draft.pages.first.recipe.quarterTurns, 1);
  });
}
