# Text PDF from OCR

After Batch OCR finishes, **Create text PDF** builds a PDF of the pages that were read and offers it to share. It is also saved in the exports folder.

- Each scan page becomes one or more PDF pages headed "Page N". Text blocks come out in reading order, top to bottom.
- ML Kit reports each text block with its position. The stretches of the page between and around the blocks that are tall enough (4% of the page) and not blank are cut out and placed as images where they sat. Pictures, drawings and tables the reader could not make out end up here.
- A page where no text was found goes in as one image.
- The standard PDF font covers Latin-1 only. Other characters become a close match or "?".
- Not yet: pictures beside a text column (the search is by horizontal bands), and selectable text over the original page.

Code: `lib/export/ocr_pdf_builder.dart`, `lib/imaging/ocr_figures.dart`, `OcrLayoutEngine` in `lib/domain/ocr.dart`.
