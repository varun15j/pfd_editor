import 'dart:io';

/// Deletes a test's temporary folder. On Windows a file that is still open,
/// such as an image the test framework is decoding, cannot be deleted until
/// it is closed, so there a folder still in use is left for the OS to clear
/// instead of failing a test that passed.
void deleteTemp(Directory dir) {
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
  }
}

/// Deletes [file], waiting up to two seconds for whatever still has it open
/// (on Windows, the background render reading a new page) to let it go.
Future<void> deleteWhenFree(File file) async {
  for (var tries = 0; ; tries++) {
    try {
      file.deleteSync();
      return;
    } on FileSystemException {
      if (!Platform.isWindows || tries >= 20) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
