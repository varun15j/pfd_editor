# Phase 2: features competitors have that LumaScan does not

Written 2026-10-26, for Varun to choose from. Nothing here is built yet, except where a row says what already exists. The apps compared are Adobe Scan, Zoho Scanner, Genius Scan, vFlat Scan, iScanner and CamScanner (banned in India since 2020, but its feature list still sets expectations). Market and price findings come from the competitor study of 2026-10-26.

Effort is rough developer time for one person, including tests:

- **S** — up to about a day
- **M** — two to four days
- **L** — a week or more
- **XL** — more than two weeks, or needs the P1 backend

Plan tier follows the study's suggestion, with one change Varun made on 2026-10-27: Basic is free with no ads, but its exported PDFs carry a small "Scanned with LumaScan" mark (#20); Pro (₹99/month, ₹599/year) for what runs on the phone, Gold (₹199/month, ₹1,299/year) for what has a running cost.

## 1. Pick these first

The five that matter most in India, where LumaScan can be better than every legal rival rather than equal to them.

| # | Feature | What it is | Effort | Plan |
| --- | --- | --- | --- | --- |
| 1 | ID card mode (built, see [id-card.md](id-card.md)) | Front and back of an Aadhaar, PAN or licence card captured one after the other and laid out on one A4 page, ready to print. | M | Basic (free) |
| 2 | Compress to a target size | "Make this under 200 KB / 500 KB / 1 MB" for government portals, picking quality and resolution automatically and showing the real size. The pieces exist in `PdfShrinker`, which only has fixed quality levels. | M | Pro |
| 3 | Hindi and Indian-language OCR | **In progress in PR #62** (ML Kit Devanagari plus Tesseract for other Indic scripts, offline). Listed here so it is not started twice. | M | Pro |
| 4 | Lock a document and the app | A password on a saved PDF, plus fingerprint or face unlock for the app and for a locked folder. Genius Scan and Zoho both charge for this. | M | Pro |
| 5 | Split a PDF, and extract pages | Split one PDF into several by page range, or pull pages out into a new file. Merging exists; splitting does not. | M | Pro |

## 2. Worth doing next

| # | Feature | What it is | Effort | Plan |
| --- | --- | --- | --- | --- |
| 6 | Signature library (built 2026-10-27) | Signatures and initials saved once and reused, instead of drawing each time. Also a date and name stamp. Built as a Sign sheet in the PDF editor and Markup; drawing a one-off signature stays free. | M | Pro |
| 7 | Auto file naming (built 2026-10-27) | A name suggested from the text on the page (invoice number, date, title), instead of "Scan 2026-10-26". Genius Scan calls it smart rename. Built as a suggestion in the Save sheet, see [plans.md](plans.md). | M | Pro |
| 8 | Searchable library | Search inside the text of saved documents, not only their names, folders and tags. Needs OCR text kept in the index. | M | Pro |
| 9 | Book mode, finished | Curve flattening and finger removal for photographed books. The two-page split exists; pages photographed from a thick book still curve. | L | Pro |
| 10 | Table and form extraction | A table on a page becomes a real table, exported to Excel or CSV. Adobe and CamScanner both sell this. | L | Gold |
| 11 | Receipt mode | Receipts read into a list with date, merchant and amount, exported as a spreadsheet for expenses. | L | Gold |
| 12 | Cloud backup and sync | Documents backed up and the library shared across devices, with share links. Needs the P1 backend; today cloud accounts are import and export only. | XL | Gold |
| 13 | AI helpers | Summarise a document, ask questions about it, translate it. Needs a paid API, so it has a running cost per use. | L | Gold |
| 14 | Request a signature from someone else | Send a PDF for another person to sign and get it back signed. Zoho does this through Zoho Sign. | XL | Gold |

## 3. Smaller gaps

| # | Feature | What it is | Effort | Plan |
| --- | --- | --- | --- | --- |
| 15 | Redact text, not just cover it | Masking (built 2026-10-26) covers a region; redaction would also delete the text behind it in a PDF that has real text. | M | Pro |
| 16 | Widget and quick actions | A home-screen widget and a long-press shortcut that open the camera straight away. | S | Basic (free) |
| 17 | Share a scan as a link | A link instead of a file, so WhatsApp does not re-compress it. Needs the backend. | XL | Gold |
| 18 | Print | Print straight from the app through the system print service. | S | Basic (free) |
| 19 | Sort and bulk actions in the library | Multi-select for move, tag, delete and share; sort by size and by page count. | S | Basic (free) |
| 20 | Watermark and page numbers (built 2026-10-27) | Basic exports carry "Scanned with LumaScan" at the foot of each page; Pro and Gold exports have no mark and can add page numbers ("2 / 5"). The name comes from `appName` in `lib/app/app_info.dart`. See [plans.md](plans.md). | M | Watermark: Basic. Page numbers and no watermark: Pro |
| 21 | Scan to Excel from a photo of a table | A quicker path than #10: one photo, one spreadsheet. Built 2026-10-27 (Tools > Table to Excel): read with on-device ML Kit, so no cost per use and no usage cap. | L | Gold |
| 22 | Import from WhatsApp and files, by share sheet | LumaScan appearing in the system share sheet, so a PDF or photo from another app comes straight in. | S | Basic (free) |

## What LumaScan already has that rivals charge for

Worth saying in the store listing: scanning with auto crop and filters, batch capture and batch edit, markup and signing, PDF editing, merge, reorder, text PDF (OCR), PDF to Word, Word to PDF, JPG export, folders and tags, QR reading, book spread splitting, Aadhaar and ID masking, and no ads. Since 2026-10-27 Basic PDFs carry a small "Scanned with LumaScan" mark, so "no watermark" is a Pro selling point, not a Basic one. The study found that every legal rival in India charges for at least some of these.

## Notes on choosing

- The study's view was that the free tier must stay watermark-free and ad-free, because every legal rival in India is. Varun decided on 2026-10-27 to put a small "Scanned with LumaScan" mark on Basic exports anyway, and to make removing it part of Pro.
- #3 is already being built in PR #62, so the open picks among the first five are #1, #2, #4 and #5.
- #1 to #5 are all on-device work with no running cost, so they fit Pro cleanly and can ship without the backend.
- #12, #14 and #17 all wait on the P1 backend, so they belong in one later release rather than one at a time.
- #13, #10, #11 and #21 cost money per use, so they need Gold and a usage cap.
