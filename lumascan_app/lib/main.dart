import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/frame_watchdog.dart';
import 'debug/test_data_backup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installFrameWatchdog();
  // Debug builds on Android: a reinstalled test build gets its data back
  // before anything reads it, then keeps the backup up to date.
  await TestDataBackup.instance.restoreAtStart();
  runApp(const ProviderScope(child: LumaScanApp()));
  TestDataBackup.instance.start();
}
