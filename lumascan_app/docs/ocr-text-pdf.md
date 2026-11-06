# Text PDF from OCR

Text PDF is a **Pro and Gold** feature (`PlanFeature.textPdf`, see `docs/plans.md`). On Basic the buttons are shown with a Pro tag. Tapping one opens an "Upgrade to Pro" pop-up and does nothing else. There is no purchase flow yet, so Upgrade only says plans cannot be bought in this version.

Three places make a text PDF:

- **Export sheet** (saving the draft): choose **PDF** or **Text PDF**. Text PDF reads every page with OCR and saves `<name> (text).pdf`, then files it in the Library like a plain export. Page size and quality do not apply.
- **Library menu > Create text PDF** on any saved document: the PDF's pages are rendered to pictures, read, and the result is saved beside it as `<name> (text).pdf`. This works for any PDF of photos.
- **Batch OCR > Create text PDF** after the pages were read.

A page the reader could not read at all goes in as one image, so nothing is lost. Code: `lib/export/text_pdf_service.dart`, `lib/ui/upgrade_dialog.dart`.

After Batch OCR finishes, **Create text PDF** builds a PDF of the pages that were read and offers it to share. It is also saved in the exports folder.

- Each scan page becomes one or more PDF pages headed "Page N". Text blocks come out in reading order, top to bottom.
- ML Kit reports each text block with its position. The stretches of the page between and around the blocks that are tall enough (4% of the page) and not blank are cut out and placed as images where they sat. Pictures, drawings and tables the reader could not make out end up here.
- A page where no text was found goes in as one image.
- The standard PDF font covers Latin-1 only. Other characters become a close match or "?".
- A picture taller than the page is shrunk to fit it (a page break cannot split a picture).
- Not yet: pictures beside a text column (the search is by horizontal bands).

Code: `lib/export/ocr_pdf_builder.dart`, `lib/imaging/ocr_figures.dart`, `OcrLayoutEngine` in `lib/domain/ocr.dart`.

## Keep layout (Pro and Gold)

On Pro and Gold (`PlanFeature.smartScan`) every PDF page is the scanned page itself, at its own shape, with the text set
over it at each line's place as **invisible text** (PDF text render mode 3, the way scanners and OCR tools write it).
The page looks exactly like the scan, and every PDF app can find, select and copy the text. The text layer is written
with the render mode, not with a see-through (opacity 0) layer.

## Speed: the page image is drawn once

Text recognition reads each page from the render cache: `ocrPageImageProvider` (`lib/app/providers.dart`), which is
`RenderService.renderMasked(page, maxDimension: ocrImageSize)`, the page with its crop, filter and masks as a JPEG made
from the 1600 px working copy. The text PDF and the OCR Word file use **that same image**:

- Keep layout: the JPEG goes into the PDF as it is. Nothing is decoded or encoded again.
- Flowing text, and Word pictures: the JPEG is decoded to cut out the pictures between the text blocks.
- Only when the image cannot be had is the page drawn again from the full-size photo, as before.

Pages are drawn two at a time on their own isolates (`runPageJobs`, `lib/imaging/page_jobs.dart`) behind a dialog
with "Page X of N" and Cancel (`runWithProgress`, `lib/ui/work_progress.dart`). Cancel writes no file.

### Why Create text PDF took 10 to 20 minutes (November 2026)

The keep-layout page logic is the one from PR #55 and has not changed since. What made it slow: every page was
drawn again from the **full-size photo** (decode, crop, filter and JPEG encode in pure Dart, one page after another),
although text recognition had just made the same picture. On a phone or BlueStacks in a debug build that is many
seconds per page, and the button only showed a small spinner, so the build looked stuck. With 35 Word test pages on a
PC the build went from 8.0 s to 0.8 s with the page image reused.

