import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../../export/pdf_lock/pdf_locker.dart';
import '../../ui/file_size.dart';
import 'pdf_sharer.dart';

/// Asks for a password and makes a locked copy of a saved PDF, then offers
/// to send it (Pro and Gold). The saved PDF is never changed.
Future<void> showLockPdfSheet(BuildContext context, {required String pdfPath, required String name}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Back and the scrim are blocked by the sheet itself while locking.
      enableDrag: false,
      builder: (_) => LockPdfSheet(pdfPath: pdfPath, name: name),
    );

class LockPdfSheet extends ConsumerStatefulWidget {
  const LockPdfSheet({super.key, required this.pdfPath, required this.name});

  final String pdfPath;

  /// Display name, with or without .pdf.
  final String name;

  @override
  ConsumerState<LockPdfSheet> createState() => _LockPdfSheetState();
}

class _LockPdfSheetState extends ConsumerState<LockPdfSheet> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;

  /// Errors are shown only after the first tap on Lock, not while typing.
  bool _tried = false;
  bool _locking = false;
  File? _locked;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _passwordError {
    if (_password.text.length < minPasswordLength) return 'Use at least $minPasswordLength characters';
    return null;
  }

  String? get _confirmError => _confirm.text == _password.text ? null : 'The passwords do not match';

  Future<void> _lock() async {
    if (_locking) return;
    setState(() {
      _tried = true;
      _error = null;
    });
    if (_passwordError != null || _confirmError != null) return;
    if (!File(widget.pdfPath).existsSync()) {
      setState(() => _error = 'This PDF is no longer on this device.');
      return;
    }
    final locker = ref.read(pdfLockerProvider);
    final password = _password.text;
    setState(() => _locking = true);
    try {
      final file = await locker.lock(sourcePath: widget.pdfPath, name: widget.name, password: password);
      if (!mounted) return;
      // The password is not kept once the copy is made.
      _password.clear();
      _confirm.clear();
      setState(() {
        _locking = false;
        _locked = file;
      });
    } on PdfAlreadyLockedException {
      if (mounted) {
        setState(() {
          _locking = false;
          _error = 'This PDF already has a password.';
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _locking = false;
          _error = 'Could not lock this PDF. Your saved PDF is unchanged. ($e)';
        });
      }
    }
  }

  Future<void> _send(BuildContext buttonContext) async {
    final file = _locked!;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _error = null);
    try {
      final outcome = await ref.read(pdfSharerProvider).send(file.path, origin: origin);
      if (outcome == SendOutcome.sent) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Locked PDF shared')));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not open the share sheet. ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locked = _locked;

    return PopScope(
      canPop: !_locking,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (locked != null) ...[
                Text('Locked PDF ready', style: textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('${p.basename(locked.path)} · ${formatFileSize(locked.lengthSync())}'),
                const SizedBox(height: 4),
                Text(
                  'It asks for the password when opened. The PDF in your Library has no password.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    onPressed: () => _send(buttonContext),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Send'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ] else ...[
                Text('Add a password', style: textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Makes a locked copy, ${PdfLocker.lockedName(widget.name)}, that asks for this password '
                  'when it is opened. Your saved PDF stays as it is.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  enabled: !_locking,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    errorText: _tried ? _passwordError : null,
                    suffixIcon: IconButton(
                      tooltip: _show ? 'Hide password' : 'Show password',
                      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  enabled: !_locking,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _lock(),
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    border: const OutlineInputBorder(),
                    errorText: _tried && _passwordError == null ? _confirmError : null,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$appName does not keep the password. If it is forgotten, the locked copy cannot be opened.',
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_locking) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text('Locking…', style: textTheme.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: _locking ? null : _lock,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(_locking ? 'Locking…' : 'Lock PDF'),
                ),
              ],
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: scheme.error))],
            ],
          ),
        ),
      ),
    );
  }
}
