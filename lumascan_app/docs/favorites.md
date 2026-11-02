# Favorite documents

Saved documents can be marked as favorites with a heart (LIB-01). All plans
have it.

## Where the heart is

- **Library list:** a heart button beside each row's overflow menu.
- **Library grid:** a heart on the top right of the page preview.
- **Home list and gallery:** a heart on every saved PDF. Scans kept as page
  images (not yet saved as a PDF) have no heart.
- **Library selection:** More actions > "Add to favorites" or "Remove from
  favorites" (remove shows when every picked document is already a
  favorite).

Outline heart means not a favorite, the filled red heart means favorite. The
switch scales in on the High animation profile and is instant on Low or with
system animations off (`Motion.of(context)`).

## Order

Favorites are always listed first, then the rest. Inside each group the
chosen sort applies (newest, oldest, name A to Z, name Z to A). On Home the
favorites come first, then the scan last on screen, then everything else
newest first. Marking a favorite does not change the document's modified
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
- `LibraryController.delete` also refuses a favorite, so no other path can
  remove one.

## Storage

`SavedDocument.favorite`, stored as `"favorite": true` in the library index
only when set. Older index files read as not favorite, so no migration is
needed.
