import 'package:flutter/foundation.dart';

enum LibraryView { list, grid }

/// Small UI choices kept on the device.
@immutable
class UiPrefs {
  const UiPrefs({
    this.libraryView = LibraryView.list,
    this.homeView = LibraryView.grid,
    this.dismissedCards = const {},
  });

  final LibraryView libraryView;

  /// How Home shows the documents: a gallery of page previews unless the
  /// user picks the list.
  final LibraryView homeView;

  /// Ids of Home discovery cards the user closed and one-time hints already
  /// shown (such as the scan tips).
  final Set<String> dismissedCards;

  UiPrefs copyWith({LibraryView? libraryView, LibraryView? homeView, Set<String>? dismissedCards}) => UiPrefs(
    libraryView: libraryView ?? this.libraryView,
    homeView: homeView ?? this.homeView,
    dismissedCards: dismissedCards ?? this.dismissedCards,
  );

  Map<String, Object?> toJson() => {
    'libraryView': libraryView.name,
    'homeView': homeView.name,
    'dismissedCards': dismissedCards.toList(),
  };

  static UiPrefs fromJson(Map<String, Object?> json) => UiPrefs(
    libraryView: LibraryView.values.asNameMap()[json['libraryView']] ?? LibraryView.list,
    homeView: LibraryView.values.asNameMap()[json['homeView']] ?? LibraryView.grid,
    dismissedCards: {for (final id in (json['dismissedCards'] as List?) ?? const []) id as String},
  );
}
