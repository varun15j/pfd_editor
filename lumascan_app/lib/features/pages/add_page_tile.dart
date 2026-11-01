import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/scanner_service.dart';
import 'scan_actions.dart';
import 'scan_controller.dart';
import '../../ui/luma_icons.dart';

/// The empty page after a document's last page: "Add a new page". Tapping it
/// opens the camera, and the photos taken join the end of this document.
class AddPageTile extends ConsumerWidget {
  const AddPageTile({super.key, this.compact = false});

  /// A small tile with only the plus, for the page strip.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = LumaColors.of(context);
    final busy = ref.watch(scanControllerProvider.select((s) => s.busy));
    final radius = BorderRadius.circular(compact ? 8 : 10);
    return Semantics(
      button: true,
      enabled: !busy,
      label: 'Add a new page',
      hint: 'Opens the camera',
      excludeSemantics: true,
      child: Material(
        color: colors.accentSoft.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.accent.withValues(alpha: 0.6), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : () => runScan(context, ref, ScanSource.camera),
          child: Center(
            child: compact
                ? Icon(LumaIcons.add, color: colors.accent)
                : Padding(
                    padding: const EdgeInsets.all(8),
                    // Shrinks to fit small tiles and large text.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                            child: Icon(LumaIcons.addPhoto, color: colors.onAccent, size: 22),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a new page',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
