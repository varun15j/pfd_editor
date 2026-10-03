<!-- Copied from lumascan_app/README.md; the code lives in the lumascan_app folder next to pfd_editor. -->
# LumaScan: scanning flow implementation

A working first cut of the document scanning flow from `pfd_editor/docs`: camera capture with automatic edge detection and crop, multi-page capture, manual corner crop, rotation, document filters (Original, Magic Color, Grayscale, B&W) and export of all pages to one PDF that can be shared or saved.

## How it fits the design docs

| Design decision | Where it lives |
|---|---|
| ADR-010 `ScannerService` wrapping cunning_document_scanner (ML Kit on Android, VisionKit on iOS) | `lib/domain/scanner_service.dart`, `lib/data/cunning_scanner_service.dart` |
| ADR-004 immutable originals plus edit recipes | `lib/domain/models.dart` (`EditRecipe`), `lib/data/page_store.dart` |
| LLD §7 render pipeline: orientation, perspective warp, quarter turns, filter | `lib/imaging/` (runs on background isolates) |
| ADR-011 scan PDFs written with the `pdf` package, atomic write | `lib/export/pdf_exporter.dart` |
| Riverpod services as overridable providers, one controller per flow | `lib/app/providers.dart`, `lib/features/pages/scan_controller.dart` |
| Screens S03 Crop, S04 Enhance, S08 Pages, S09 Export | `lib/features/` |

Filter behaviour follows `docs/document.md`: B&W uses an adaptive (Bradley) threshold plus despeckle so shadows do not turn black, Magic Color neutralises paper tint and whitens the background, Grayscale uses perceptual luminance with a contrast stretch. "Apply to all" copies only the filter; each page keeps its own crop and rotation.

## The flow

1. **Scan with camera** opens the platform scanner. It finds page edges live, auto-captures, lets the user adjust corners and keeps going for more pages.
2. **Import from photos** uses the system picker plus the scanner's crop step.
3. Pages are copied into app storage and listed in order. Drag to reorder, tap to enhance, or use crop, rotate and delete (with undo).
4. **Crop** lets the user fine-tune four corners; the page is perspective-corrected from the untouched original.
5. **Enhance** shows live filter thumbnails. Hold the page to compare with the original.
6. **Export PDF** picks page size (A4, Letter, fit to image) and quality, renders each page off the UI thread, writes the PDF and opens the share sheet.

## Run it

Requirements: Flutter 3.38 or newer (tested with 3.47.6 stable), Android Studio with an Android SDK, and Xcode 16+ on a Mac for iOS.

```bash
cd lumascan_app
flutter pub get
flutter test          # 26 unit and widget tests
flutter run           # with a phone connected or an emulator running
```

Use a real phone. The ML Kit scanner needs Google Play services, and the iOS document camera does not run in the Simulator (the Simulator can still use Import from photos).

## Permission setup (already applied)

**Android** (`android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`)
- `android.permission.CAMERA`, with the camera feature marked optional so tablets without one can still import.
- `minSdk = 26` (the plugin needs 24; 26 is the proposed target in the HLD).
- No storage permission: gallery import uses the system photo picker, and PDFs are written to app storage and shared through the share sheet.

**iOS** (`ios/Runner/Info.plist`, Xcode project)
- `NSCameraUsageDescription` explains camera use. iOS terminates the app without it.
- Deployment target 16.0 (plugin minimum is 13; 16 is the HLD proposal).
- permission_handler compiles in only the permissions whose Info.plist keys exist when building with Swift Package Manager, which new Flutter projects use by default. If you switch to CocoaPods, add `'PERMISSION_CAMERA=1'` to `GCC_PREPROCESSOR_DEFINITIONS` in the Podfile `post_install` block, as in the permission_handler README.

If the user denies the camera, the app explains why it is needed and offers **Try again**; if it is permanently denied it offers **Open Settings**. Photo import keeps working either way.

## Not done yet

- Drafts are kept in memory; the page files survive a restart but the list does not. Persisting the draft (Drift, per LLD §4) and the document library are the next step.
- Native builds were not run here. Analysis and all Dart tests pass, but the build machine could not download the Android SDK, so the first `flutter run` on a device is the real check of the Gradle and Xcode setup.
- Filter quality has been checked against synthetic images in the tests, not a corpus of real phone captures. `docs/document.md` §14 calls for golden-image tests on real documents before shipping.
- The custom camera surface (ADR-008, milestone M7), OCR and annotations are out of scope for this flow.
