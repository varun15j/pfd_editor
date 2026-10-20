import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/version_bump.dart';

void main() {
  group('bumpVersion', () {
    test('patch raises patch and build', () {
      expect(bumpVersion('1.0.0+1'), '1.0.1+2');
      expect(bumpVersion('1.2.9+14'), '1.2.10+15');
    });

    test('minor resets patch, major resets minor and patch, and the build always rises', () {
      expect(bumpVersion('1.2.3+4', part: BumpPart.minor), '1.3.0+5');
      expect(bumpVersion('1.2.3+4', part: BumpPart.major), '2.0.0+5');
    });

    test('rejects a version without a build number', () {
      expect(() => bumpVersion('1.2.3'), throwsFormatException);
      expect(() => bumpVersion('one.two'), throwsFormatException);
    });
  });

  group('bumpPubspec', () {
    const pubspec = 'name: lumascan\nversion: 1.0.0+1\n\nenvironment:\n  sdk: ^3.13.1\n';

    test('changes only the version line', () {
      expect(bumpPubspec(pubspec), 'name: lumascan\nversion: 1.0.1+2\n\nenvironment:\n  sdk: ^3.13.1\n');
      expect(readVersion(bumpPubspec(pubspec)), '1.0.1+2');
    });

    test('keeps Windows line endings', () {
      final windows = pubspec.replaceAll('\n', '\r\n');
      expect(bumpPubspec(windows), pubspec.replaceAll('1.0.0+1', '1.0.1+2').replaceAll('\n', '\r\n'));
    });

    test('ignores version-like text elsewhere, such as a dependency', () {
      const withDep = 'name: x\nversion: 2.0.0+7\ndependencies:\n  version: 1.0.0+1\n';
      expect(readVersion(withDep), '2.0.0+7');
      expect(bumpPubspec(withDep), 'name: x\nversion: 2.0.1+8\ndependencies:\n  version: 1.0.0+1\n');
    });

    test('fails clearly when there is no version line', () {
      expect(() => bumpPubspec('name: x\n'), throwsFormatException);
      expect(readVersion('name: x\nversion: 1.0.0\n'), isNull);
    });
  });

  test('the real pubspec.yaml has a version the script can raise', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(readVersion(pubspec), isNotNull);
    expect(() => bumpPubspec(pubspec), returnsNormally);
  });
}
