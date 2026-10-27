import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/app_info.dart';

/// The app's name is set once, as [appName] in lib/app/app_info.dart. These
/// checks fail when a copy of it creeps back in somewhere else.
void main() {
  test('no Dart code spells out the app name; it all reads appName', () {
    final literal = RegExp(r"""['"][^'"\n]*\b""" + RegExp.escape(appName) + r"""\b""");
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('app_info.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (literal.hasMatch(line)) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('Android takes its launcher label from appName', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('lib/app/app_info.dart'));
    expect(gradle, contains('manifestPlaceholders["appName"] = appName'));
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains(r'android:label="${appName}"'),
    );
  });

  test('the iOS name matches appName', () {
    final config = File('ios/Flutter/AppName.xcconfig').readAsStringSync();
    expect(RegExp(r'^APP_DISPLAY_NAME = (.+)$', multiLine: true).firstMatch(config)?[1]?.trim(), appName);
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, isNot(contains(appName)));
    expect(plist, contains(r'$(APP_DISPLAY_NAME)'));
  });
}
