import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether PDF to Word (Tools > PDF to Word and the Library menu's
/// "Convert to Word") is offered. It is left out of release builds, so the
/// Play Store release does not have it (Varun, 9 Nov 2026); debug and profile
/// builds keep it for testing. Exporting a scan as Word and Word to PDF are
/// not affected. A provider so tests can turn it off.
final pdfToWordAvailableProvider = Provider<bool>((ref) => !kReleaseMode);
