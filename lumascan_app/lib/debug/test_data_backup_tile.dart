import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/luma_icons.dart';
import 'test_data_backup.dart';

/// Settings > Developer and the debug panel: the test data backup in
/// `Documents/<app name> test` (see [TestDataBackup]). Debug builds on
/// Android only.
class TestDataBackupTile extends StatefulWidget {
  const TestDataBackupTile({super.key, this.backup, this.contentPadding});

  /// The backup; the app's one when null. Tests pass their own.
  final TestDataBackup? backup;

  final EdgeInsetsGeometry? contentPadding;

  @override
  State<TestDataBackupTile> createState() => _TestDataBackupTileState();
}

class _TestDataBackupTileState extends State<TestDataBackupTile> {
  TestDataBackup get _backup => widget.backup ?? TestDataBackup.instance;

  @override
  void initState() {
    super.initState();
    _backup.refresh();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TestBackupState>(
    valueListenable: _backup.state,
    builder: (context, s, _) => ListTile(
      contentPadding: widget.contentPadding,
      leading: s.busy
          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(LumaIcons.sync),
      title: const Text('Test data backup'),
      subtitle: Text(_subtitle(s)),
      onTap: s.busy ? null : () => _tap(context, s),
    ),
  );

  String _subtitle(TestBackupState s) {
    const where = 'Documents/${TestDataBackup.folderName}';
    if (!s.access) {
      return 'Off. Tap to allow file access: your test data is then kept in $where and comes back after a reinstall.';
    }
    final b = s.backup;
    if (b == null) return 'Nothing backed up yet. Tap to back up to $where now.';
    final what = '${b.files} files, ${_mb(b.bytes)}, ${_when(b.time)}';
    if (s.waiting) return 'A backup is waiting in $where ($what). Tap to load it.';
    return 'Backed up to $where: $what. Copied every few minutes and when you leave the app. Tap to back up now.';
  }

  Future<void> _tap(BuildContext context, TestBackupState s) async {
    if (!s.access) return _backup.requestAccess();
    if (!s.waiting) return _backup.backUp();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load the test data backup?'),
        content: const Text(
          'The backup replaces what this install has now. The app closes; open it again to see the backup.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'replace'), child: const Text('Keep this data')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, 'load'), child: const Text('Load and close')),
        ],
      ),
    );
    if (choice == 'load') {
      await _backup.loadOnNextStart();
      await SystemNavigator.pop();
    } else if (choice == 'replace') {
      await _backup.replaceBackup();
    }
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _when(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.day}/${t.month} ${two(t.hour)}:${two(t.minute)}';
  }
}
