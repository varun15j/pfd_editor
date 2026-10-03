/// Which part of `major.minor.patch` a bump raises.
enum BumpPart { major, minor, patch }

final _versionLine = RegExp(r'^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$', multiLine: true);

/// The `version:` value in [pubspec] (`1.2.3+4`), or null when there is none
/// in that shape.
String? readVersion(String pubspec) {
  final m = _versionLine.firstMatch(pubspec);
  return m == null ? null : '${m[1]}.${m[2]}.${m[3]}+${m[4]}';
}

/// Raises [version] (`1.2.3+4`): the chosen part goes up by one, the parts
/// after it reset to zero, and the build number always goes up by one, so
/// every bump is a new build for the stores.
String bumpVersion(String version, {BumpPart part = BumpPart.patch}) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch(version);
  if (m == null) throw FormatException('Not a major.minor.patch+build version', version);
  var major = int.parse(m[1]!), minor = int.parse(m[2]!), patch = int.parse(m[3]!);
  final build = int.parse(m[4]!) + 1;
  switch (part) {
    case BumpPart.major:
      (major, minor, patch) = (major + 1, 0, 0);
    case BumpPart.minor:
      (minor, patch) = (minor + 1, 0);
    case BumpPart.patch:
      patch += 1;
  }
  return '$major.$minor.$patch+$build';
}

/// [pubspec] with its `version:` line replaced by the bumped version. Every
/// other character, including line endings, is kept.
String bumpPubspec(String pubspec, {BumpPart part = BumpPart.patch}) {
  final current = readVersion(pubspec);
  if (current == null) {
    throw const FormatException('pubspec.yaml has no "version: major.minor.patch+build" line');
  }
  return pubspec.replaceFirst(_versionLine, 'version: ${bumpVersion(current, part: part)}');
}
