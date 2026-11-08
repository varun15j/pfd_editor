# Test data backup (debug builds)

Debug builds on Android keep a copy of the app's data in `Documents/LumaScan test` on the phone. That folder outlives
the app. If a test build is uninstalled, whether by `flutter run`, `flutter test`, Android Studio or by hand, and then
installed again, the app loads the copy back on its first start, before anything reads the data. Release builds and
iOS never do this.

## What is copied

| Folder in the backup | From | Holds |
|---|---|---|
| `documents/` | the app's documents folder | Library, scans, page photos, saved PDFs and Word files, settings, opened PDF/Word sources |
| `databases/` | the app's database folder | `export_state.db` (which exports are still current) |
| `backup.json` | | time, file count, size and app version of the last backup |

Page previews, thumbnails and smaller copies made for sending (`renders`, `thumbnails`, `share`) are not copied,
because the app rebuilds them. The image-loading profile already lives in `Documents/LumaScan/debug`.

## When

- At start, after the app opens.
- Every 3 minutes while the app is open, and whenever it goes to the background. Only changed files are copied.
  Files deleted in the app are deleted from the backup.
- Settings > Developer > **Test data backup** (also in the debug panel) shows the last backup. Tap it to back up now.

## Safety rules

- The backup is loaded only into an install that has no data yet, so it never overwrites what the app has.
- A fresh install that starts before it can read the folder does not overwrite the backup. The tile then says
  "A backup is waiting". **Load and close** replaces this install's data with the backup on the next start, and
  **Keep this data** lets this install's data replace the backup.
- An empty app never backs up, so it can't wipe the backup.

## Access

Access needs "All files access" (Android 11 and newer) or the storage permission (Android 8 to 10). Only debug builds
ask for it. Tap the tile to allow it, or grant it over adb before the first start, so the backup loads at once:

```
adb shell pm grant com.mobi.scanner android.permission.WRITE_EXTERNAL_STORAGE          # Android 8 to 10 (BlueStacks Pie)
adb shell pm grant com.mobi.scanner android.permission.READ_EXTERNAL_STORAGE
adb shell appops set --uid com.mobi.scanner MANAGE_EXTERNAL_STORAGE allow             # Android 11+
```

The app lock PIN (Android Keystore) and purchases are not copied.
