import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What makes a page recognisable from the text read on it: its page
/// number, its first and last lines, and the words on it. Auto capture
/// compares each new page with the one before, so a page held in front of
/// the camera too long is not kept twice.
///
/// Read from OCR text, so every comparison allows for misread letters.
@immutable
class PageIdentity {
  const PageIdentity({required this.numbers, required this.first, required this.last, required this.words});

  /// Page numbers printed on the page: lines that hold only a number, such
  /// as "28", "- 28 -", "(28)" or "Page 28". An open book shows two.
  final Set<int> numbers;

  /// The first and last lines of text, lower case, letters and digits only.
  final String first, last;

  /// Every word of three letters or more, lower case.
  final Set<String> words;

  /// Fewest words a page needs before its text says anything about it.
  static const minWords = 6;

  /// Lines at least this alike, after allowing for misread letters, are the
  /// same line.
  static const lineMatch = 0.8;

  /// Share of words two readings of the same page have in common. Two
  /// different pages of one book share far fewer, even with the same
  /// common words.
  static const sameWords = 0.6;

  /// With the same page number, a smaller share of common words is enough.
  static const sameWordsWithNumber = 0.4;

  /// The identity of the page in [text], or null when too little was read
  /// to tell pages apart (a photo, a blank page, or OCR that found nothing).
  static PageIdentity? fromText(String text) {
    final numbers = <int>{};
    final lines = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final number = _pageNumber.firstMatch(line);
      if (number != null) {
        numbers.add(int.parse(number.group(1)!));
        continue;
      }
      final normal = _normal(line);
      if (RegExp('[a-z]').allMatches(normal).length >= 3) lines.add(normal);
    }
    final words = {
      for (final line in lines)
        for (final word in line.split(' '))
          if (word.length >= 3 && RegExp(r'^[a-z]+$').hasMatch(word)) word,
    };
    if (words.length < minWords) return null;
    return PageIdentity(numbers: numbers, first: lines.first, last: lines.last, words: words);
  }

  /// Whether [other] reads as this same page.
  bool samePageAs(PageIdentity other) {
    final common = wordOverlap(other);
    if (numbers.isNotEmpty && other.numbers.isNotEmpty) {
      // Different page numbers are different pages, however alike the
      // text: two pages of the same form, say.
      if (numbers.intersection(other.numbers).isEmpty) return false;
      return common >= sameWordsWithNumber || _sameEnds(other);
    }
    return common >= sameWords || (_sameEnds(other) && common >= sameWordsWithNumber);
  }

  bool _sameEnds(PageIdentity other) =>
      lineSimilarity(first, other.first) >= lineMatch && lineSimilarity(last, other.last) >= lineMatch;

  /// Share of words the two pages have in common (Jaccard index), 0 to 1.
  double wordOverlap(PageIdentity other) {
    final union = words.union(other.words).length;
    return union == 0 ? 0 : words.intersection(other.words).length / union;
  }

  @override
  String toString() => 'PageIdentity(numbers: $numbers, first: "$first", last: "$last", ${words.length} words)';
}

/// A line that is only a page number.
final _pageNumber = RegExp(r'^(?:page|p\.)?\s*[-–—(\[]?\s*(\d{1,4})\s*[-–—)\]]?$', caseSensitive: false);

String _normal(String line) =>
    line.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll(RegExp(' +'), ' ');

/// How alike two lines are, from 0 to 1: one minus their edit distance over
/// the longer length, so a few misread letters still match.
double lineSimilarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final longest = math.max(a.length, b.length);
  return 1 - _editDistance(a, b) / longest;
}

int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      row[j] = math.min(math.min(row[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost);
    }
    previous = row;
  }
  return previous[b.length];
}
