import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../domain/launch_action.dart';
import '../../domain/scanner_service.dart';
import '../batch_capture/camera_mode.dart';
import '../id_card/id_card_type_screen.dart';
import '../pages/scan_controller.dart';

/// Runs what the app was opened to do from a long-press shortcut on its icon
/// or from the home-screen widget (improvement.md #16): straight to the
/// camera in the right mode, to the ID card studio, or to the photo picker.
///
/// Anything else on screen is closed first, so the action starts from Home
/// the way it would from the camera button. An action that arrives while
/// pages are being added is dropped rather than interrupting them.
class LaunchActionsListener extends ConsumerStatefulWidget {
  const LaunchActionsListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LaunchActionsListener> createState() => _LaunchActionsListenerState();
}

class _LaunchActionsListenerState extends ConsumerState<LaunchActionsListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(launchActionSourceProvider).start(_run);
    });
  }

  void _run(LaunchAction action) {
    if (!mounted || ref.read(scanControllerProvider).busy) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (action) {
      case LaunchAction.scan:
        scanThenReview(context, ref, ScanSource.camera);
      case LaunchAction.book:
        scanThenReview(context, ref, ScanSource.camera, mode: CameraMode.book);
      case LaunchAction.idCard:
        openIdCardStudio(context);
      case LaunchAction.importPhotos:
        scanThenReview(context, ref, ScanSource.gallery);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
