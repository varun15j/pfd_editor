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
- Not yet: pictures beside a text column (the search is by horizontal bands), and selectable text over the original page.

Code: `lib/export/ocr_pdf_builder.dart`, `lib/imaging/ocr_figures.dart`, `OcrLayoutEngine` in `lib/domain/ocr.dart`.
