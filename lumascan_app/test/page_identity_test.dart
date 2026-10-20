import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/batch_capture/page_identity.dart';

// Text as OCR reads two pages of the book in sample_photos/book.
const _page28 = '''
Tough Newspaper
Your strongest blow cannot budge this fearless newspaper!
You need:
a newspaper a wooden ruler
a table
What to do:
Place a ruler on a table so that an inch or two projects over the edge.
Strike the projecting edge of the ruler as hard as you can.
What happens:
The newspaper doesn't budge.
28''';

const _page30 = '''
Why No Flood?
Until you learn how to work this experiment perfectly (and maybe even then), it's best to work it over a sink or basin.
You need:
a piece of cardboard or a large index card
a drinking glass filled to the brim with water
What happens:
The cardboard stays in place and the water stays in the glass.
30''';

// The same page read again from a photo held a little askew: a few
// letters misread, a line lost, the page number in a different place.
const _page28Again = '''
- 28 -
Tough Newspaper
Your strongest b1ow cannot budge this fearless newspaper!
You need:
a newspaper a wooden ruIer
What to do:
Place a ruler on a table so that an inch or two projects over the edge.
Strike the projecting edge of the ruler as hard as you can.
What happens:
The newspaper doesnt budge.''';

PageIdentity _read(String text) => PageIdentity.fromText(text)!;

void main() {
  test('reads the page number, the first and last lines and the words', () {
    final page = _read(_page28);
    expect(page.numbers, {28});
    expect(page.first, 'tough newspaper');
    expect(page.last, 'the newspaper doesn t budge');
    expect(page.words, containsAll(['strongest', 'ruler', 'newspaper']));
  });

  test('page numbers are found written in several ways', () {
    for (final line in ['12', '- 12 -', '(12)', 'Page 12', 'p. 12', '[12]']) {
      expect(_read('$line\n$_page30').numbers, contains(12), reason: line);
    }
    expect(_read('12 cups of flour\n$_page30').numbers, {30}, reason: 'a number in a sentence is not a page number');
  });

  test('the same page read twice is the same page, despite misread letters', () {
    expect(_read(_page28Again).samePageAs(_read(_page28)), isTrue);
    expect(_read(_page28).samePageAs(_read(_page28)), isTrue);
  });

  test('the next page of the book is a different page', () {
    expect(_read(_page30).samePageAs(_read(_page28)), isFalse);
  });

  test('a different page number wins over alike text', () {
    final form = 'Name\nAddress\nCity and postcode\nDate of birth\nSignature of applicant\nOffice use only';
    expect(_read('$form\n1').samePageAs(_read('$form\n2')), isFalse);
    expect(_read(form).samePageAs(_read(form)), isTrue, reason: 'without page numbers the text decides');
  });

  test('without page numbers, matching first and last lines decide', () {
    final a = _read(_page28.replaceAll('28', '')), b = _read(_page28Again.replaceAll('- 28 -', ''));
    expect(a.numbers, isEmpty);
    expect(b.samePageAs(a), isTrue);
    expect(_read(_page30.replaceAll('30', '')).samePageAs(a), isFalse);
  });

  test('too little text tells nothing', () {
    expect(PageIdentity.fromText(''), isNull);
    expect(PageIdentity.fromText('Chapter 3\n14'), isNull);
  });

  test('line similarity allows a few misread letters', () {
    expect(lineSimilarity('the newspaper doesn t budge', 'the newspaper doesnt budge'), greaterThan(0.9));
    expect(lineSimilarity('tough newspaper', 'why no flood'), lessThan(0.5));
  });
}
