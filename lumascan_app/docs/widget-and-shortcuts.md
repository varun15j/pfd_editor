# Home-screen widget and quick actions

Improvement #16, Basic (free). Built 2026-10-27.

## Quick actions (Android and iOS)

Long-press the app icon for four shortcuts: **Scan document**, **Scan a book**, **Scan ID card** and **Import photos**. They come from the `quick_actions` plugin, set at every start by `PlatformLaunchActions` (`lib/data/platform_launch_actions.dart`). Android shows a blue icon for each (`res/drawable/ic_shortcut_*.xml`); iOS shows the titles with the system's default icon.

## Widget (Android)

**Quick scan**, two cells wide: a green **Scan** button that opens the camera and an **Import** button for photos. `ScanWidget.kt` starts `MainActivity` with the action `com.mobi.scanner.LAUNCH` and the extra `lumascan.launch_action` (`scan` or `import`). `MainActivity` passes it to Dart on the `lumascan/launch` channel: `takePending` for the tap that opened the app, `action` for a tap while it runs. The widget has no data, so it never refreshes.

The iOS widget is not built: it needs a WidgetKit extension target added in Xcode on a Mac. The quick actions cover the same shortcuts on iOS until then.

## In the app

`LaunchActionsListener` (`lib/features/capture/launch_actions_listener.dart`) wraps the app shell, after the intro. On an action it closes whatever screen is open and does what the camera button, Book, ID Card or Photos to PDF would do. An action that arrives while pages are being added is dropped. The ids in `LaunchAction` are what the shortcuts and the widget send, so they must not change.
