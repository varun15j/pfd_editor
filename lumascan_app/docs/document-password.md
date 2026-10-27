# Document password

Added 2026-10-27 (Phase 2, item 4 of `docs/improvement.md`). Pro and Gold (`PlanFeature.password`). App lock is not part of this change.

## What the user sees

- **Library > document menu > Add password**, and **Send PDF > Send with password**. Both open the same sheet (`lib/features/share/lock_pdf_sheet.dart`).
- The sheet asks for the password twice (at least 6 characters, shown or hidden with the eye button) and says that LumaScan does not keep it and a forgotten password cannot be recovered.
- **Lock PDF** writes `<name> (locked).pdf` to the app's `share/` folder, then offers **Send** through the system share sheet.
- On Basic both entries carry a Pro badge and open the upgrade pop-up.

## Why a locked copy, not the saved file

The PDF in the Library stays without a password, so thumbnails, editing, merge, text PDF, Word and the smaller copy keep working on it, and a forgotten password never locks the user out of their own scan. The locked copy is what leaves the phone. The password is never stored, logged or kept in the sheet after locking.

## How the file is encrypted

`lib/export/pdf_lock/`:

- `pdf_objects.dart` reads every object of an existing PDF: classic xref tables, xref streams, object streams, incremental updates, and a scan for objects when the xref is damaged.
- `pdf_encryption.dart` (`lockPdfBytes`) writes every object again with all strings and streams encrypted, using the PDF 2.0 standard security handler, revision 6: AES-256 (`/V 5 /R 6`, `AESV3`), the strongest that PDF readers support (Acrobat 9 and later, PDFium/Chrome/Android, Apple PDFKit). Objects are copied as stored, so text stays selectable, images keep their quality and burned-in masks stay burned in. Runs on a background isolate.
- `pdf_locker.dart` (`PdfLocker`) reads the saved PDF and writes the copy.
- AES and SHA-2 come from `pointycastle`.

A PDF that already has a password is refused with "This PDF already has a password."

## Checked

- `test/pdf_lock_test.dart`: the password check (Algorithm 2.A) passes only for the right password, every stream decrypts to the original bytes, title and author are encrypted, object and xref streams are read, the sheet's validation, the copy and sending, and the Pro gate.
- The five PDFs in `sample_docs/` were locked and opened with PDFium (the engine in Chrome, Android and pdfrx) and with pypdf: no password and a wrong password are refused, the right one opens, and every page renders pixel-identical to the original.
