# Versioning

The app version is the `version:` line in `pubspec.yaml`, written `major.minor.patch+build`, for example `1.0.1+2`.
Flutter turns it into the Android version name and code and the iOS version and build number, and Settings > About
shows it as "Version 1.0.1 (2)" using `package_info_plus`. There is no second copy to keep in step.

## Every pull request raises it

Before opening a pull request, run this from `lumascan_app`:

```bash
dart run tool/bump_version.dart
```

It adds one to the patch number and one to the build number (`1.0.0+1` becomes `1.0.1+2`) and changes nothing else in
`pubspec.yaml`. Commit the change with the rest of the pull request.

| Command | Effect |
| --- | --- |
| `dart run tool/bump_version.dart` | patch and build, for an ordinary pull request |
| `dart run tool/bump_version.dart minor` | minor and build, patch back to 0, for a new feature users will notice |
| `dart run tool/bump_version.dart major` | major and build, minor and patch back to 0, for a release that changes how the app is used |
| `dart run tool/bump_version.dart --dry-run` | prints the change without writing it |

The build number only ever goes up, so every pull request is a distinct build for the stores.

If two open pull requests both bump from the same base, the second one conflicts in `pubspec.yaml` when the first is
merged. Merge the base into the branch and run the script again.

The version logic is in `tool/version_bump.dart` and is tested in `test/version_bump_test.dart`.
