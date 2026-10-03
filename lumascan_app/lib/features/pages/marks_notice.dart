import 'package:flutter/material.dart';

import 'scan_controller.dart';

/// Tells the user that a crop or rotation removed the marks on a page.
void showMarksRemovedNotice(BuildContext context, ScanController controller) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: const Text('Markup removed because the page changed'),
        action: SnackBarAction(label: 'Undo', onPressed: controller.undo),
      ),
    );
}
