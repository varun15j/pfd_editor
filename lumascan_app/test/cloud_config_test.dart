import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/cloud_config.dart';

void main() {
  test('debug builds use the debug client IDs and release builds the release ones', () {
    expect(identical(cloudClientIdsFor(debug: true), debugCloudClientIds), isTrue);
    expect(identical(cloudClientIdsFor(debug: false), releaseCloudClientIds), isTrue);
  });

  test('the OneDrive redirect scheme matches the Android package name', () {
    expect(Uri.parse(CloudConfig.microsoftRedirectUri).scheme, 'com.mobi.scanner');
  });
}
