# User-journey test cases

End-to-end cases that follow what a real user does, from the first photo to a shared PDF. They are automated in
`integration_test/user_journeys_test.dart` and run on a device or emulator:

```bash
flutter test integration_test/user_journeys_test.dart -d emulator-5554
```

## Test data

The automated run swaps only the parts an emulator cannot do well for real photos bundled with the app
(`integration_test/support/journey_harness.dart`):

| Replaced | By |
|---|---|
| Camera shots | The five maths revision phone photos in `sample_photos/` (fingers, torn edges, desk backgrounds) |
| Platform document scanner (Retake on the Pages screen) | Real book photos from `sample_photos/book/` |
| Gallery picker | Real book photos from `sample_photos/book/` |
| ID card photos | A drawn card with a 12-digit number in the Aadhaar layout. No real ID card belongs in the repository |

Everything else is the real app on the device: page detection and auto crop, rendering, filters, markup and masks,
PDF export and the ID copy. Library, draft and settings stores are kept in memory so the device's own Library is not
touched. The plan is set to Gold so every feature is open.

For trying the same journeys by hand, the photo sets can be pushed into the emulator's gallery:

```bash
adb push sample_photos/. /sdcard/Pictures/LumaScanTest/maths_revision_photos/
adb push sample_photos/book/. /sdcard/Pictures/LumaScanTest/book/
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/LumaScanTest/book/01_contents.jpg
```

## J1: Photograph pages, edit, retake, edit again, export; add a photo, export again

| # | Step | Expected |
|---|---|---|
| 1 | Home, tap the camera button, take 3 photos | "3 pages captured"; each photo is cropped to the page found in it |
| 2 | Captured photos > Review all 3 pages > Done > Review document | The Pages screen shows the 3 pages |
| 3 | Crop: drag the top-left corner in, Apply crop | Page 1's crop changes |
| 4 | Filters: B&W, Apply, Apply to this page | Page 1 is black and white; pages 2 and 3 keep their filter |
| 5 | Markup: draw a pen stroke, Done | The stroke is kept on page 1 |
| 6 | Next page, Retake | "Page 2 retaken"; the new photo is page 2, still 3 pages |
| 7 | Filters on the new page 2: Grayscale, this page | Page 2 is grayscale |
| 8 | Export > Export as PDF > Save PDF | "PDF saved"; the Library has one 3-page document |
| 9 | Add pages > Scan with camera, take 1 photo, Review document | 4 pages, same document name |
| 10 | Add pages > Import photos > Add 1 page | 5 pages |
| 11 | Export > Export as PDF > Save PDF | A new 5-page PDF in the Library; the first 3-page PDF is kept (saving never overwrites a PDF) |

## J2: ID card front and back, hide the number, save and export

| # | Step | Expected |
|---|---|---|
| 1 | Tools > ID Card > Make it now | The camera asks for the front page ("1 of 2") |
| 2 | Take front page, Take back page | The review shows both sides on one A4 page |
| 3 | Tap the front > Hide a number, drag over the number, Done | The front has a mask over the number |
| 4 | Save the copy | The saved grid: 01 ID copy, 02 front, 03 back; the Library has one ID card PDF with 3 pages |

Checked by hand on the emulator as well: Auto mask on the front hides the first 8 digits and leaves the last 4
readable; the Basic plan shows the upgrade pop-up instead.

## J3: A new scan after the ID card

| # | Step | Expected |
|---|---|---|
| 1 | More > Done on the saved ID grid | Back on Home |
| 2 | Camera button, take 2 photos, Review document | A new 2-page document, not the ID card |
| 3 | Export > Export as PDF > Save PDF | The Library has 2 documents; the ID card is still there |

## Known limits

- The Google ML Kit document scanner cannot be opened on most emulators (its module download fails), so Retake on
  the Pages screen is only covered with the replaced scanner. Retake inside the camera (Captured photos > Retake page
  N) uses the app's own camera and works on the emulator.
- The emulator camera shows a virtual room, so live edge detection and the QR, Text and OCR camera modes need a real
  phone.

## Results (1 November 2026)

| Device | J1 | J2 + J3 | Notes |
|---|---|---|---|
| OnePlus CPH2661, Android 16, display size large (320 dp wide) | Pass | Pass | Whole run 1 min 21 s. J2 needs PR #88: without it the ID review's Edit sheet overflows on this screen |
| Emulator sdk_gphone16k_x86_64, 4 cores, 4 GB | Pass (about 4 min) | Pass | With 1 core and 2 GB, Android's watchdog restarted the system during long runs; give the AVD at least 4 cores |
