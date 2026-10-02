# Sample documents

Real-world PDFs for trying the PDF editor and the save path by hand. They are not bundled into the app (nothing in `pubspec.yaml` lists them as assets). Copy one to the phone or emulator, then open it with **Edit a PDF**.

| File | Pages | Page size | Text layer | Size | Good for |
|---|---|---|---|---|---|
| KV_6th_Std_Half_Yearly_Exam_2022_Question_paper_Maths.pdf | 3 | A4 | Yes | 120 KB | Basic open, annotate, save |
| KV_6th_Std_Half_Yearly_Exam_2023_Maths_Question_paper.pdf | 5 | A4 | Yes | 968 KB | Reorder and delete pages |
| KV_6th_std_Half_Yearly_Question_Paper_2024_ENGLISH.pdf | 5 | A4 | Yes | 344 KB | Text marks and signature |
| KV_6th_std_Half_Yearly_Question_Paper_2024_HINDI.pdf | 4 | US Letter | Little extractable text | 344 KB | Devanagari content, non-A4 page size |
| english_sep.pdf | 25 | A4 | None (scanned images) | 12 MB | Long document, memory and save time |

None of them is password-protected.

To copy one to an Android emulator or a USB-connected phone:

```bash
adb push sample_docs/english_sep.pdf /sdcard/Download/
```
