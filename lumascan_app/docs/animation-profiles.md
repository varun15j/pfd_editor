# Animation profiles (High and Low)

LumaScan picks how much it animates, and how many page pictures it draws, from
the phone it runs on. Entry phones sold in India around ₹10,000 can have 2 GB of
memory and slow cores; drawing a picture for every page and running every fade
there makes the camera and page grids stutter.

## How the profile is picked (Auto)

Read once at start from Android (`lumascan/device_load` channel, `snapshot`):
total memory, CPU cores and `ActivityManager.isLowRamDevice`.

| Phone | Profile |
| --- | --- |
| Android Go (`isLowRamDevice`) | Low |
| 1 or 2 cores | Low |
| 2.5 GB or less reported (2 GB phones report about 1.8 GB) | Low |
| Everything else, iOS, or when the phone cannot be read | High |

The limits are `lowProfileMaxMb` and `lowProfileMaxCores` in
`lib/domain/motion_profile.dart`. 3 to 5 GB phones get High.

The system setting "Remove animations" also turns decorative animations off on
any profile, but keeps page pictures.

## What changes

| Place | High | Low |
| --- | --- | --- |
| Camera thumbnail | Last three shots fanned out, each new shot pops in | Page icon and count; no photo decoded until the pages are opened |
| Camera capture flash | White flash over the preview | None (shutter still dips, count still rises) |
| Camera page outline analysis | About 6 frames a second (QR 4) | About 4 a second (QR 3) |
| Camera mode strip, toast, count pill, QR frame, import/thumbnail switch | Animated | Instant |
| Page grids and strips (Batch Review, Reorder, document grid and list, strip under the opened page) | Page picture, fades in as it arrives | Page icon with "Page N" (or N on small tiles) |
| Home and Library documents (gallery and list) | First-page cover | Document or PDF icon; pages show once the document is opened |
| Opened page (the big page view) | Picture | Picture (the only place Low draws one) |
| Page turns and strip scrolling | Animated | Jump |
| Screen transitions | Platform default | None (iOS keeps its own for the back swipe) |
| Button ink | Platform default (sparkle shader on Android) | Plain ripple |
| Intro dots and page turns, markup toolbar, compact buttons | Animated | Instant |

Filter previews, crop, markup and the ID card
screens draw pictures on both profiles: there the picture is the point of the
screen.

## Code

- `lib/app/motion.dart`: `motionProfileProvider`, `MotionScope` (set in
  `app.dart`), `Motion.of(context)` with `duration`, `scrollTo`, `toPage`,
  `pageThumbnails`, and `themeForMotion`.
- `lib/features/pages/page_thumbnail.dart`: `PageThumbnail` (picture on High,
  `PageIconTile` on Low). Use it for any new grid, list or strip of pages.
- New animations: take the duration from `Motion.of(context).duration(...)`, or
  check `Motion.of(context).animates`, so Low gets an instant version.

## Testing

Debug builds: swipe in from the left edge, then **Animation profile**:
Auto / High / Low. Auto shows what the phone reported.
