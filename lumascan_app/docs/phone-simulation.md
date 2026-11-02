# Testing as a 2 GB or 4 GB phone

Debug builds can act as a cheaper phone, so the app can be tried and profiled on a fast phone (for example an 8 GB OnePlus) the way it behaves on an entry or mid phone.

## In the app

Swipe in from the left edge for the debug panel. Under **Simulate phone**:

| | Real | 4 GB mid | 2 GB entry | 1 GB Go |
|---|---|---|---|---|
| Memory the app reads | the phone's | 3650 MB | 1840 MB | 900 MB, low RAM device |
| Cores the app reads | the phone's | 8 | 4 | 4 |
| Animation profile (Auto) | from the phone | High | Low | Low |
| Page pictures rendered at once | half the cores, 1-3 | 2 | 1 | 1 |
| Decoded picture cache | 100 MB | 64 MB | 32 MB | 16 MB |
| Memory budget in the overlay | none | 700 MB | 350 MB | 200 MB |
| CPU left to the app with **Slow the CPU** | all | about 3 fast cores | about 1.5 fast cores | about 1 fast core |

Free memory and the app's CPU share are scaled to that phone, so the background text check (repeat page check) and other load-based choices decide as they would there. The choice is saved and survives a restart.

**Slow the CPU** keeps the other cores busy with plain arithmetic in background isolates (7 of 8 on 1 GB, 6 of 8 on 2 GB, 5 of 8 on 4 GB). The app then competes for the CPU as on a slower phone. The phone gets warm, so turn it off after a test run.

**Performance overlay** shows, at the top right:
- UI and GPU frame times (median and 90th percentile, ms) over the last 120 frames
- slow frames: frames over 16.7 ms, which miss a 60 Hz screen (most entry phones are 60 Hz)
- the app's memory (RSS) against the phone's budget, red when over, and the peak
- the decoded picture cache in use against its limit

## What it cannot do

An app cannot take memory or cores away from the phone it runs on without root. The real 8 GB (plus virtual RAM) is still there, so Android will not close the app at 350 MB the way a 2 GB phone might. Watch the red memory figure in the overlay instead. The busy cores also run on fast cores, and the app's own threads may still land on a big core, so treat timings as a rough guide.

The simulation is in debug builds only, and debug builds run Dart much slower than the release app. Compare Real against 2 GB or 4 GB in the same build rather than reading the numbers as what users will see.

## Outside the app

- **Android Studio profiler** (Profile build: `flutter run --profile`) or **Flutter DevTools** (Performance and Memory tabs) for detailed frame and memory timelines. Profile builds give real timings; debug builds are much slower everywhere.
- **Memory pressure on the phone**: `adb shell am send-trim-memory com.mobi.scanner RUNNING_CRITICAL` tells the app memory is running out (send while the app is open). `adb shell dumpsys meminfo com.mobi.scanner` shows the app's real memory use.
- **A true 2 GB / 4 GB test**: an Android emulator AVD (Device Manager, Edit, Advanced settings) with RAM 2048 MB and 2 cores, or 4096 MB and 4 cores. Android then really has only that memory and closes the app when it runs out. The CPU is still the PC's, so frame times are not those of a real cheap phone.
- **The best test** is a real entry phone (a 2 GB Android Go phone costs little second-hand).
