# Split PDF and extract pages

Phase 2 item 5 (`docs/improvement.md` in the project files). Pro and Gold (`PlanFeature.splitPdf`).

## Where

- **Tools > Process Files > Split PDF**: choose a PDF from the Library or the device.
- **Library > a document's menu > Split or extract pages**.

On Basic both are shown with a Pro badge and open the upgrade pop-up. A PDF locked with a password is turned away with a message to unlock it first.

## What it does

The split screen has two modes:

- **Split**: *Every few pages* (a stepper, files of the same length, the last one shorter) or *By page ranges* (typed as `1-3, 4, 5-`; one file per range; `7-` runs to the last page). The new files are listed before saving as "Name part 1", "Name part 2" and so on. A choice that keeps every page in one file is refused.
- **Extract**: tick pages (Select all / Clear); they go, in page order, into one file named "Name pages 2-4,7".

New files go to the exports folder and the Library. Taken names get " (2)", so nothing is replaced. The source PDF is only read. The result screen lists each file with Send.

## How

`lib/export/pdf_splitter.dart` (`PdfSplitter`, `parsePageRanges`, `pagesInChunks`, `describePages`), UI in `lib/features/split/`. Like Merge, each page is rendered to an image and rebuilt at its own size (ADR-014 write engine still open), so text cannot be selected in the new files; the screen says so. Masks, markup and signatures already burned into a saved PDF are part of the page image, so they stay covered in every part. If one part fails, the parts already written are deleted.

## Tests

`test/split_test.dart`: range parsing and its error messages, chunks, the splitter (pages per part, source unchanged, no overwrite, cleanup on failure), the screen (every 2 pages, typed ranges, extract), the Pro badge and upgrade pop-up on Basic, and a locked PDF.
