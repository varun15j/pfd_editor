import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../domain/signature_library.dart';

/// What the pad hands back: the drawn strokes in pad pixels, and whether to
/// keep the mark in the signature library.
typedef SignaturePadResult = ({List<List<(double, double)>> strokes, bool save});

/// Full-screen signature pad (signature package, ADR-013). Pops with the
/// drawn strokes, or null when cancelled.
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key, this.kind = SignatureKind.signature, this.offerSave = false});

  /// A full signature or initials; only the wording changes.
  final SignatureKind kind;

  /// Shows "Save for next time" (on by default), for plans with the
  /// signature library.
  final bool offerSave;

  static Future<SignaturePadResult?> show(
    BuildContext context, {
    SignatureKind kind = SignatureKind.signature,
    bool offerSave = false,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SignaturePadScreen(kind: kind, offerSave: offerSave),
    ),
  );

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF14213D),
    strokeCap: StrokeCap.round,
    strokeJoin: StrokeJoin.round,
  );
  bool _save = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _done() {
    final strokes = [
      for (final s in _controller.pointsToStrokes(2)) [for (final p in s) (p.offset.dx, p.offset.dy)],
    ];
    Navigator.pop<SignaturePadResult>(context, (strokes: strokes, save: widget.offerSave && _save));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == SignatureKind.initials ? 'Draw your initials' : 'Draw your signature'),
        actions: [
          TextButton(onPressed: _controller.isEmpty ? null : _controller.clear, child: const Text('Clear')),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _controller.isEmpty ? null : _done, child: const Text('Add')),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 64,
                          child: Divider(color: scheme.outline, thickness: 1),
                        ),
                        Positioned.fill(
                          child: Signature(controller: _controller, backgroundColor: Colors.transparent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.offerSave)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Save for next time'),
                  subtitle: const Text('Kept on this phone only.'),
                  value: _save,
                  onChanged: (v) => setState(() => _save = v),
                ),
              const SizedBox(height: 12),
              Text(
                'This adds a picture of your signature. It is not a certificate-based digital signature.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
