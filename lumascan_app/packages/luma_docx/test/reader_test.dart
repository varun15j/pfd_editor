// Reads the Word feature test file and checks every feature with a sample.
import 'dart:io';

import 'support/feature_checks.dart';

void main() => featureChecks(() => File('test/fixtures/Word_Feature_Test.docx').readAsBytesSync());
