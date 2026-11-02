import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumascan/data/photo_import_services.dart';
import 'package:lumascan/domain/id_copy.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/imaging/card_outline.dart';
import 'package:lumascan/imaging/page_detector.dart';
import 'package:lumascan/imaging/rgb_image.dart';

import 'support/temp_dir.dart';

/// Whether every corner of [found] is within [tolerance] of [expected].
Matcher _near(CropQuad expected, {double tolerance = 0.03}) => predicate<CropQuad?>((found) {
  if (found == null) return false;
  for (var i = 0; i < 4; i++) {
    final a = found.points[i], b = expected.points[i];
    if ((a.x - b.x).abs() > tolerance || (a.y - b.y).abs() > tolerance) return false;
  }
  return true;
}, 'corners within $tolerance of $expected');

CropQuad _rect(double l, double t, double r, double b) =>
    CropQuad(NormPoint(l, t), NormPoint(r, t), NormPoint(r, b), NormPoint(l, b));

/// A card 1.586 wide to high on a wooden desk, turned [degrees], as the
/// camera takes it in ID card mode: no printed outline, just the card's
/// edge against the desk.
img.Image _cardOnDesk({double degrees = 4}) {
  const w = 1000, h = 750;
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(112, 82, 58));
  final a = degrees * math.pi / 180, cx = w / 2, cy = h / 2, hw = 380.0, hh = hw / 1.586;
  img.Point corner(double x, double y) =>
      img.Point(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a));
  img.fillPolygon(
    im,
    vertices: [corner(-hw, -hh), corner(hw, -hh), corner(hw, hh), corner(-hw, hh)],
    color: img.ColorRgb8(244, 241, 232),
  );
  img.fillPolygon(
    im,
    vertices: [corner(-hw, -hh), corner(hw, -hh), corner(hw, -hh + 70), corner(-hw, -hh + 70)],
    color: img.ColorRgb8(40, 104, 64),
  );
  return im;
}

void main() {
  // Where the card is in test/fixtures/id_card_photocopy.jpg, made by
  // tool/make_id_card_sample.dart: a photocopied card on white paper, its
  // outline a thin grey line, the right side barely printed.
  final copiedCard = _rect(85 / 900, 45 / 553, 815 / 900, 515 / 553);
  const photocopy = 'test/fixtures/id_card_photocopy.jpg';
  final aspect = IdCopyType.idCard.aspect;

  group('a photocopied card', () {
    test('the page detector does not find the card: it is only a faint outline on white paper', () {
      final image = RgbImage.decode(File(photocopy).readAsBytesSync(), maxDimension: DetectorPhotoAnalyzer.decodeSize);
      expect(detectPageQuad(image), isNot(_near(copiedCard)));
    });

    test('the card is found by its printed outline, the whole card and not a strip of text', () {
      final image = RgbImage.decode(File(photocopy).readAsBytesSync(), maxDimension: DetectorPhotoAnalyzer.decodeSize);
      expect(findCardOutline(image, aspect: aspect), _near(copiedCard));
    });

    test('an imported copy is cropped to the whole card, before the sheet of paper the analyzer finds', () async {
      expect(await idCardCrop(photocopy, aspect: aspect), _near(copiedCard));
      // The sheet, or all of a photo cropped close to the card, is in the
      // card's shape too, but the outline inside it wins.
      expect(await idCardCrop(photocopy, aspect: aspect, found: CropQuad.full), _near(copiedCard));
    });
  });

  group('a card on a desk', () {
    late Directory dir;
    late String path;
    late CropQuad card;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('lumascan_id_outline');
      path = '${dir.path}/desk.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(_cardOnDesk(), quality: 90));
      card = detectPageQuad(RgbImage.decode(File(path).readAsBytesSync(), maxDimension: 640))!;
    });

    tearDown(() => deleteTemp(dir));

    test('the page detector finds it, and both a camera shot and an import keep that', () async {
      final guide = _rect(0.1, 0.17, 0.9, 0.83);
      expect(cardShaped(card, 1000, 750, aspect), isTrue);
      expect(await idCardCrop(path, aspect: aspect, found: card, guide: guide), card);
      expect(await idCardCrop(path, aspect: aspect, found: card), card);
    });

    test('nothing card-shaped is made up where there is no card', () async {
      final blank = '${dir.path}/blank.jpg';
      File(blank)
          .writeAsBytesSync(img.encodeJpg(img.Image(width: 900, height: 600)..clear(img.ColorRgb8(230, 230, 228))));
      expect(await idCardCrop(blank, aspect: aspect), isNull);
    });
  });

  test('the card shape: about 1.59 wide to high either way round, not a strip of text or a square', () {
    expect(cardShaped(_rect(0.1, 0.1, 0.9, 0.9), 1586, 1000, IdCopyType.idCard.aspect), isTrue);
    expect(cardShaped(_rect(0.1, 0.1, 0.9, 0.9), 1000, 1586, IdCopyType.idCard.aspect), isTrue);
    expect(cardShaped(_rect(0.1, 0.33, 0.9, 0.67), 900, 553, IdCopyType.idCard.aspect), isFalse);
    expect(cardShaped(_rect(0.1, 0.1, 0.9, 0.9), 1000, 1000, IdCopyType.idCard.aspect), isFalse);
  });
}
