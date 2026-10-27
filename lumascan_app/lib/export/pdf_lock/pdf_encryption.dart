import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'pdf_objects.dart';

/// The PDF already has a password.
class PdfAlreadyLockedException implements Exception {
  const PdfAlreadyLockedException();
  @override
  String toString() => 'This PDF already has a password.';
}

/// Shortest password the lock accepts.
const minPasswordLength = 6;

/// Returns [source] rewritten so it opens only with [password]: AES-256
/// (PDF 2.0 standard security handler, revision 6), the strongest
/// encryption PDF readers support. All objects are copied as they are, so
/// text, images and burned-in masks stay exactly as in the original.
/// The password is never stored or logged.
Uint8List lockPdfBytes(Uint8List source, String password, {Random? random}) {
  final rnd = random ?? Random.secure();
  final file = PdfObjectFile.parse(source);
  if (file.trailer['Encrypt'] != null && file.trailer['Encrypt'] is! PdfNull) {
    throw const PdfAlreadyLockedException();
  }
  final security = PdfSecurity.create(password, rnd);

  final out = BytesBuilder(copy: false);
  void ascii(String s) => out.add(latin1.encode(s));
  // The binary comment tells transfer tools the file is not text.
  ascii('%PDF-1.7\n');
  out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

  final rootRef = file.trailer['Root'] as PdfRef;
  final offsets = <int, (int, int)>{};
  var maxNum = 0;
  for (final num in file.objectNumbers) {
    var v = file.object(num);
    // Cross-reference and object streams are rebuilt as a plain table.
    if (v is PdfStream) {
      final type = v.dict.name('Type');
      if (type == 'XRef' || type == 'ObjStm') continue;
    }
    if (num == rootRef.num && v is PdfDict && v['Extensions'] == null) {
      // AES-256 is Adobe extension level 8 of PDF 1.7.
      v = PdfDict({
        ...v.entries,
        'Extensions': PdfDict({
          'ADBE': PdfDict({'BaseVersion': const PdfName('1.7'), 'ExtensionLevel': PdfNumber.of(8)}),
        }),
      });
    }
    final gen = file.generationOf(num);
    offsets[num] = (out.length, gen);
    if (num > maxNum) maxNum = num;
    ascii('$num $gen obj\n');
    _write(out, security.encryptValue(v));
    ascii('\nendobj\n');
  }

  final encryptNum = maxNum + 1;
  offsets[encryptNum] = (out.length, 0);
  ascii('$encryptNum 0 obj\n');
  _write(out, security.encryptDict);
  ascii('\nendobj\n');

  final xref = out.length;
  final size = encryptNum + 1;
  ascii('xref\n0 $size\n');
  ascii('0000000000 65535 f\r\n');
  for (var n = 1; n < size; n++) {
    final e = offsets[n];
    if (e == null) {
      ascii('0000000000 00001 f\r\n');
    } else {
      ascii('${e.$1.toString().padLeft(10, '0')} ${e.$2.toString().padLeft(5, '0')} n\r\n');
    }
  }

  var id = file.resolve(file.trailer['ID']);
  if (id is! PdfArray || id.items.length != 2 || id.items.any((i) => i is! PdfString)) {
    final fresh = PdfString(_randomBytes(rnd, 16));
    id = PdfArray([fresh, fresh]);
  }
  final info = file.trailer['Info'];
  final trailer = PdfDict({
    'Size': PdfNumber.of(size),
    'Root': rootRef,
    if (info is PdfRef && offsets.containsKey(info.num)) 'Info': info,
    'ID': id,
    'Encrypt': PdfRef(encryptNum, 0),
  });
  ascii('trailer\n');
  _write(out, trailer);
  ascii('\nstartxref\n$xref\n%%EOF\n');
  return out.takeBytes();
}

/// AES-256 keys and the /Encrypt dictionary for one locked file.
class PdfSecurity {
  PdfSecurity._(this.fileKey, this.encryptDict, this._random);

  factory PdfSecurity.create(String password, Random random) {
    final pw = passwordBytes(password);
    final fileKey = _randomBytes(random, 32);

    final uValidation = _randomBytes(random, 8), uKeySalt = _randomBytes(random, 8);
    final u = Uint8List.fromList([...hash2B(pw, uValidation, const []), ...uValidation, ...uKeySalt]);
    final ue = _aesCbcNoPadding(hash2B(pw, uKeySalt, const []), Uint8List(16), fileKey);

    // The owner password is the same as the open password: whoever can
    // open the file may also print and copy from it.
    final oValidation = _randomBytes(random, 8), oKeySalt = _randomBytes(random, 8);
    final o = Uint8List.fromList([...hash2B(pw, oValidation, u), ...oValidation, ...oKeySalt]);
    final oe = _aesCbcNoPadding(hash2B(pw, oKeySalt, u), Uint8List(16), fileKey);

    const permissions = -4; // Every permission granted.
    final perms = Uint8List(16)
      ..buffer.asByteData().setInt32(0, permissions, Endian.little)
      ..setRange(4, 8, const [0xFF, 0xFF, 0xFF, 0xFF])
      ..setRange(8, 12, ascii.encode('Tadb'))
      ..setRange(12, 16, _randomBytes(random, 4));
    final aes = AESEngine()..init(true, KeyParameter(fileKey));
    final permsOut = Uint8List(16);
    aes.processBlock(perms, 0, permsOut, 0);

    final dict = PdfDict({
      'Filter': const PdfName('Standard'),
      'V': PdfNumber.of(5),
      'R': PdfNumber.of(6),
      'Length': PdfNumber.of(256),
      'CF': PdfDict({
        'StdCF': PdfDict({
          'AuthEvent': const PdfName('DocOpen'),
          'CFM': const PdfName('AESV3'),
          'Length': PdfNumber.of(32),
        }),
      }),
      'StmF': const PdfName('StdCF'),
      'StrF': const PdfName('StdCF'),
      'O': PdfString(o),
      'U': PdfString(u),
      'OE': PdfString(oe),
      'UE': PdfString(ue),
      'P': PdfNumber.of(permissions),
      'Perms': PdfString(permsOut),
      'EncryptMetadata': const PdfBool(true),
    });
    return PdfSecurity._(fileKey, dict, random);
  }

  /// The key every string and stream is encrypted with.
  final Uint8List fileKey;
  final PdfDict encryptDict;
  final Random _random;

  /// Password bytes for revision 6: UTF-8, at most 127 bytes.
  static Uint8List passwordBytes(String password) {
    final b = utf8.encode(password);
    return Uint8List.fromList(b.length > 127 ? b.sublist(0, 127) : b);
  }

  /// [v] with every string and stream encrypted.
  PdfValue encryptValue(PdfValue v) => switch (v) {
    PdfString(:final bytes) => PdfString(encrypt(bytes)),
    PdfArray(:final items) => PdfArray([for (final i in items) encryptValue(i)]),
    PdfDict(:final entries) => PdfDict({for (final e in entries.entries) e.key: encryptValue(e.value)}),
    PdfStream(:final dict, :final data) => _encryptStream(dict, data),
    _ => v,
  };

  PdfStream _encryptStream(PdfDict dict, Uint8List data) {
    final encrypted = encrypt(data);
    final d = encryptValue(dict) as PdfDict;
    d['Length'] = PdfNumber.of(encrypted.length);
    return PdfStream(d, encrypted);
  }

  /// AESV3: a random 16-byte IV, then AES-256-CBC with PKCS#7 padding.
  Uint8List encrypt(Uint8List data) {
    final iv = _randomBytes(_random, 16);
    final pad = 16 - data.length % 16;
    final padded = Uint8List(data.length + pad)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + pad, pad);
    return Uint8List.fromList([...iv, ..._aesCbcNoPadding(fileKey, iv, padded)]);
  }

  /// Algorithm 2.B of ISO 32000-2: the hash for revision 6 passwords.
  static Uint8List hash2B(List<int> password, List<int> salt, List<int> userKey) {
    var k = _digest(SHA256Digest(), [...password, ...salt, ...userKey]);
    var e = Uint8List(0);
    for (var round = 0; round < 64 || e.last > round - 32; round++) {
      final unit = [...password, ...k, ...userKey];
      final k1 = Uint8List(unit.length * 64);
      for (var i = 0; i < 64; i++) {
        k1.setRange(i * unit.length, (i + 1) * unit.length, unit);
      }
      e = _aesCbcNoPadding(Uint8List.sublistView(k, 0, 16), Uint8List.sublistView(k, 16, 32), k1);
      var sum = 0;
      for (var i = 0; i < 16; i++) {
        sum += e[i];
      }
      final Digest digest = switch (sum % 3) {
        0 => SHA256Digest(),
        1 => SHA384Digest(),
        _ => SHA512Digest(),
      };
      k = _digest(digest, e);
    }
    return Uint8List.sublistView(k, 0, 32);
  }
}

Uint8List _digest(Digest d, List<int> data) => d.process(data is Uint8List ? data : Uint8List.fromList(data));

Uint8List _aesCbcNoPadding(Uint8List key, Uint8List iv, Uint8List data) {
  final cipher = CBCBlockCipher(AESEngine())..init(true, ParametersWithIV(KeyParameter(key), iv));
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i += 16) {
    cipher.processBlock(data, i, out, i);
  }
  return out;
}

Uint8List _randomBytes(Random r, int n) => Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]);

const _hex = '0123456789ABCDEF';

void _write(BytesBuilder out, PdfValue v) {
  switch (v) {
    case PdfNull():
      out.add(latin1.encode('null'));
    case PdfBool(:final value):
      out.add(latin1.encode(value ? 'true' : 'false'));
    case PdfNumber(:final text):
      out.add(latin1.encode(text));
    case PdfName(:final raw):
      out.add(latin1.encode('/$raw'));
    case PdfRef(:final num, :final gen):
      out.add(latin1.encode('$num $gen R'));
    case PdfString(:final bytes):
      final s = StringBuffer('<');
      for (final b in bytes) {
        s
          ..write(_hex[b >> 4])
          ..write(_hex[b & 15]);
      }
      s.write('>');
      out.add(latin1.encode(s.toString()));
    case PdfArray(:final items):
      out.addByte(0x5B);
      for (var i = 0; i < items.length; i++) {
        if (i > 0) out.addByte(0x20);
        _write(out, items[i]);
      }
      out.addByte(0x5D);
    case PdfDict(:final entries):
      out.add(latin1.encode('<<'));
      for (final e in entries.entries) {
        out.add(latin1.encode('/${e.key} '));
        _write(out, e.value);
        out.addByte(0x0A);
      }
      out.add(latin1.encode('>>'));
    case PdfStream(:final dict, :final data):
      _write(out, dict);
      out.add(latin1.encode('\nstream\n'));
      out.add(data);
      out.add(latin1.encode('\nendstream'));
  }
}
