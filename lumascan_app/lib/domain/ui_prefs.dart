import 'package:flutter/foundation.dart';

enum LibraryView { list, grid }

/// Small UI choices kept on the device.
@immutable
class UiPrefs {
  const UiPrefs({this.libraryView = LibraryView.list, this.dismissedCards = const {}});

  final LibraryView libraryView;

  /// Ids of Home discovery cards the user closed and one-time hints already
  /// shown (such as the scan tips).
  final Set<String> dismissedCards;

  UiPrefs copyWith({LibraryView? libraryView, Set<String>? dismissedCards}) =>
      UiPrefs(libraryView: libraryView ?? this.libraryView, dismissedCards: dismissedCards ?? this.dismissedCards);

  Map<String, Object?> toJson() => {'libraryView': libraryView.name, 'dismissedCards': dismissedCards.toList()};

  static UiPrefs fromJson(Map<String, Object?> json) => UiPrefs(
    libraryView: LibraryView.values.asNameMap()[json['libraryView']] ?? LibraryView.list,
    dismissedCards: {for (final id in (json['dismissedCards'] as List?) ?? const []) id as String},
  );
}
