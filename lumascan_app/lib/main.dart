import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/frame_watchdog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installFrameWatchdog();
  runApp(const ProviderScope(child: LumaScanApp()));
}
