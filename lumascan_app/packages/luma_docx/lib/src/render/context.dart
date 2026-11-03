import 'package:flutter/material.dart';

import '../model.dart';

/// How a document is laid out on screen.
enum WordLayout {
  /// Pages at their real size, scaled to fit the screen width, with
  /// headers, footers, page colour and watermark.
  pages,

  /// Text fills the screen width at a readable size, like Word's
  /// mobile view. No headers, footers or page frames.
  reflow,
}

class WordViewOptions {
  const WordViewOptions({
    this.layout = WordLayout.pages,
    this.showMarkup = true,
    this.showHidden = false,
    this.showComments = true,
    this.textScale = 1,
  });

  final WordLayout layout;

  /// Tracked changes shown in colour (true), or the final text only.
  final bool showMarkup;

  /// Show hidden text with a dotted underline.
  final bool showHidden;

  /// Comment marks and highlighted comment ranges.
  final bool showComments;

  /// Extra text size for [WordLayout.reflow].
  final double textScale;

  WordViewOptions copyWith({WordLayout? layout, bool? showMarkup, bool? showHidden, bool? showComments, double? textScale}) =>
      WordViewOptions(
        layout: layout ?? this.layout,
        showMarkup: showMarkup ?? this.showMarkup,
        showHidden: showHidden ?? this.showHidden,
        showComments: showComments ?? this.showComments,
        textScale: textScale ?? this.textScale,
      );
}

typedef WordLinkCallback = void Function(WordLink link);
typedef WordNoteCallback = void Function(WordNote note);
typedef WordCommentCallback = void Function(WordComment comment);

/// Everything a block widget needs while it draws.
class WordRenderContext {
  const WordRenderContext({
    required this.document,
    required this.options,
    required this.unit,
    required this.width,
    required this.onLink,
    required this.onNote,
    required this.onComment,
    required this.keyFor,
    this.pageNumber,
    this.pageCount,
    this.sectionPages,
  });

  final WordDocument document;
  final WordViewOptions options;

  /// Logical pixels per point.
  final double unit;

  /// Width available to the current block, in logical pixels.
  final double width;
  final WordLinkCallback onLink;
  final WordNoteCallback onNote;
  final WordCommentCallback onComment;

  /// A key for paragraphs that links or the navigation pane jump to.
  final GlobalKey? Function(int paragraphIndex) keyFor;

  /// For PAGE, NUMPAGES and SECTIONPAGES fields in headers and footers.
  final String? pageNumber;
  final int? pageCount;
  final int? sectionPages;

  WordRenderContext withWidth(double width) => WordRenderContext(
    document: document,
    options: options,
    unit: unit,
    width: width,
    onLink: onLink,
    onNote: onNote,
    onComment: onComment,
    keyFor: keyFor,
    pageNumber: pageNumber,
    pageCount: pageCount,
    sectionPages: sectionPages,
  );

  WordRenderContext forPage({String? pageNumber, int? pageCount, int? sectionPages}) => WordRenderContext(
    document: document,
    options: options,
    unit: unit,
    width: width,
    onLink: onLink,
    onNote: onNote,
    onComment: onComment,
    keyFor: (_) => null,
    pageNumber: pageNumber,
    pageCount: pageCount,
    sectionPages: sectionPages,
  );

  double pt(double points) => points * unit;
}

/// One colour per reviewer for tracked changes and comments, like Word.
Color reviewerColor(String? author) {
  const colors = [
    Color(0xFFB5082E),
    Color(0xFF2E5EAA),
    Color(0xFF2E7D32),
    Color(0xFF8E24AA),
    Color(0xFFEF6C00),
    Color(0xFF00838F),
  ];
  if (author == null) return colors.first;
  var h = 0;
  for (final c in author.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  return colors[h % colors.length];
}
