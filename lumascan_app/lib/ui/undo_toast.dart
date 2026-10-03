import 'package:flutter/material.dart';

/// How long an undo message stays on screen unless the user answers it.
const undoToastDuration = Duration(seconds: 10);

/// Tells the user what just changed and offers Undo or Keep. It goes away by
/// itself after [undoToastDuration], which counts as Keep.
///
/// A SnackBar with an action stays up until it is dismissed (Flutter's
/// `persist` defaults to true then), so the buttons are part of the content
/// and `persist` is turned off to let the time limit work.
void showUndoToast(ScaffoldMessengerState messenger, {required String message, required VoidCallback onUndo}) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        persist: false,
        duration: undoToastDuration,
        content: Builder(
          builder: (context) {
            final button = TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.inversePrimary);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: button,
                      onPressed: () {
                        messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
                        onUndo();
                      },
                      child: const Text('Undo'),
                    ),
                    TextButton(
                      style: button,
                      onPressed: () => messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss),
                      child: const Text('Keep'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
}
