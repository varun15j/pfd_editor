# Favorite documents

Every document, saved PDF or scan, can be marked as a favorite with a heart (LIB-01). All plans
have it.

## Where the heart is

- **Library list:** a heart button beside each row's overflow menu.
- **Library grid:** a heart on the top right of the page preview.
- **Home list and gallery:** a heart on every document: saved PDFs, the
  draft on screen, and earlier scans kept as page images. In the gallery it
  sits on the top right of the preview.
- **Library selection:** More actions > "Add to favorites" or "Remove from
  favorites" (remove shows when every picked document is already a
  favorite).

Outline heart means not a favorite, the filled red heart means favorite. The
switch scales in on the High animation profile and is instant on Low or with
system animations off (`Motion.of(context)`).

## Order

Favorites are always listed first, then the rest. Inside each group the
chosen sort applies (newest, oldest, name A to Z, name Z to A). On Home
favorites of every kind come first, then the rest; in each group the scan
last on screen leads, then the others newest first. Marking a favorite does not change the document's modified
date.

## Delete protection

A favorite can't be deleted until its heart is taken off:

- The row menu shows Delete disabled, with "Remove from favorites to
  delete".
- Deleting a selection deletes only the non-favorites; the snackbar says
  how many favorites were kept, for example "2 documents deleted. 1
  favorite kept".
- If only favorites were selected, nothing is deleted and a snackbar
  explains why.
- `LibraryController.delete` and `ScanController.deleteParked` also refuse
  a favorite.
- Scans on Home: the menu's Delete is disabled the same way.
- Deleting every page inside a draft (page editor or batch review) still
  discards it after the usual confirmation; that is editing the document,
  not deleting it from a list.

## Storage

`SavedDocument.favorite` for PDFs, stored as `"favorite": true` in the
library index only when set. `ScanDocInfo.favorite` for scans, stored the
same way in `drafts/current.json` and `drafts/parked/<id>.json`, so it
follows a scan when it is set aside or opened again. Older index files read as not favorite, so no migration is
needed.
