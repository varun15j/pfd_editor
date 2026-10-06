// Raises the app version in pubspec.yaml. Run it from lumascan_app once per
// pull request, before opening it:
//
//   dart run tool/bump_version.dart            patch + build (1.0.0+1 -> 1.0.1+2)
//   dart run tool/bump_version.dart minor      minor + build (1.0.1+2 -> 1.1.0+3)
//   dart run tool/bump_version.dart major      major + build
//   dart run tool/bump_version.dart --dry-run  show the change without writing it
//
// Settings > About shows the version the app was built with, which comes from
// this line. See docs/versioning.md.
import 'dart:io';

import 'version_bump.dart';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final names = args.where((a) => !a.startsWith('--')).toList();
  if (names.length > 1 || args.any((a) => a.startsWith('--') && a != '--dry-run')) {
    stderr.writeln('Usage: dart run tool/bump_version.dart [patch|minor|major] [--dry-run]');
    exit(64);
  }
  final part = names.isEmpty ? BumpPart.patch : BumpPart.values.where((p) => p.name == names.single).firstOrNull;
  if (part == null) {
    stderr.writeln('Unknown part "${names.single}". Use patch, minor or major.');
    exit(64);
  }

  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('pubspec.yaml not found. Run this from the lumascan_app folder.');
    exit(66);
  }
  final before = file.readAsStringSync();
  try {
    final after = bumpPubspec(before, part: part);
    stdout.writeln('${readVersion(before)} -> ${readVersion(after)}${dryRun ? ' (dry run)' : ''}');
    if (!dryRun) file.writeAsStringSync(after);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(65);
  }
}
