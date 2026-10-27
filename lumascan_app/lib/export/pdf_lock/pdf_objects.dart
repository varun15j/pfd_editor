import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A small reader for the objects of an existing PDF, enough to copy every
/// object into a new file (the password lock rewrites the whole file). It
/// understands classic cross-reference tables, cross-reference streams,
/// object streams and incremental updates. Streams are kept as stored; only
/// the Flate filter is decoded, for cross-reference and object streams.
sealed class PdfValue {
  const PdfValue();
}

class PdfNull extends PdfValue {
  const PdfNull();
}

class PdfBool extends PdfValue {
  const PdfBool(this.value);
  final bool value;
}

/// A number, kept as written so it is copied exactly.
class PdfNumber extends PdfValue {
  const PdfNumber(this.text);
  PdfNumber.of(num v) : text = v is int ? '$v' : v.toString();
  final String text;
  int get asInt => num.parse(text).toInt();
}

/// A name without its slash, kept as written (with any #xx escapes).
class PdfName extends PdfValue {
  const PdfName(this.raw);
  final String raw;
}

class PdfString extends PdfValue {
  const PdfString(this.bytes);
  final Uint8List bytes;
}

class PdfArray extends PdfValue {
  PdfArray(this.items);
  final List<PdfValue> items;
}

class PdfDict extends PdfValue {
  PdfDict(this.entries);
  final Map<String, PdfValue> entries;

  PdfValue? operator [](String key) => entries[key];
  void operator []=(String key, PdfValue value) => entries[key] = value;

  /// The name stored under [key], or null.
  String? name(String key) => switch (entries[key]) {
    PdfName(:final raw) => raw,
    _ => null,
  };
}

class PdfRef extends PdfValue {
  const PdfRef(this.num, this.gen);
  final int num;
  final int gen;
}

class PdfStream extends PdfValue {
  PdfStream(this.dict, this.data);
  final PdfDict dict;

  /// The stream as stored in the file, still filtered.
  final Uint8List data;
}

/// The file cannot be read as a PDF.
class PdfReadException implements Exception {
  const PdfReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _isWhite(int c) => c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;

bool _isDelim(int c) =>
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3C ||
    c == 0x3E ||
    c == 0x5B ||
    c == 0x5D ||
    c == 0x7B ||
    c == 0x7D ||
    c == 0x2F ||
    c == 0x25;

bool _isRegular(int c) => !_isWhite(c) && !_isDelim(c);

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x37;
  if (c >= 0x61 && c <= 0x66) return c - 0x57;
  return -1;
}

/// Reads PDF tokens and values from [bytes] starting at [pos].
class PdfLexer {
  PdfLexer(this.bytes, [this.pos = 0]);

  final Uint8List bytes;
  int pos;

  bool get atEnd => pos >= bytes.length;

  void skipWhite() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (_isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        // A comment runs to the end of the line.
        while (pos < bytes.length && bytes[pos] != 10 && bytes[pos] != 13) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// The next run of regular characters, such as a number or keyword.
  String token() {
    skipWhite();
    final start = pos;
    while (pos < bytes.length && _isRegular(bytes[pos])) {
      pos++;
    }
    return latin1.decode(Uint8List.sublistView(bytes, start, pos));
  }

  bool startsWith(String keyword) {
    if (pos + keyword.length > bytes.length) return false;
    for (var i = 0; i < keyword.length; i++) {
      if (bytes[pos + i] != keyword.codeUnitAt(i)) return false;
    }
    return true;
  }

  int readInt() {
    final t = token();
    final v = int.tryParse(t);
    if (v == null) throw PdfReadException('Expected a number at $pos, found "$t"');
    return v;
  }

  PdfValue value() {
    skipWhite();
    if (atEnd) throw const PdfReadException('Unexpected end of file');
    final c = bytes[pos];
    switch (c) {
      case 0x2F: // /
        pos++;
        final start = pos;
        while (pos < bytes.length && _isRegular(bytes[pos])) {
          pos++;
        }
        return PdfName(latin1.decode(Uint8List.sublistView(bytes, start, pos)));
      case 0x28: // (
        return PdfString(_literalString());
      case 0x3C: // <
        if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3C) return _dict();
        return PdfString(_hexString());
      case 0x5B: // [
        pos++;
        final items = <PdfValue>[];
        while (true) {
          skipWhite();
          if (atEnd) throw const PdfReadException('Unclosed array');
          if (bytes[pos] == 0x5D) {
            pos++;
            break;
          }
          items.add(value());
        }
        return PdfArray(items);
    }
    final t = token();
    if (t.isEmpty) {
      throw PdfReadException('Unexpected character "${String.fromCharCode(c)}" at $pos');
    }
    switch (t) {
      case 'true':
        return const PdfBool(true);
      case 'false':
        return const PdfBool(false);
      case 'null':
        return const PdfNull();
    }
    if (num.tryParse(t) == null && !_looksNumeric(t)) {
      throw PdfReadException('Unexpected "$t" at $pos');
    }
    // "12 0 R" is a reference; anything else leaves the number on its own.
    final n = int.tryParse(t);
    if (n != null && n >= 0) {
      final save = pos;
      final gen = int.tryParse(token());
      if (gen != null && gen >= 0) {
        skipWhite();
        if (pos < bytes.length && bytes[pos] == 0x52 && (pos + 1 >= bytes.length || !_isRegular(bytes[pos + 1]))) {
          pos++;
          return PdfRef(n, gen);
        }
      }
      pos = save;
    }
    return PdfNumber(t);
  }

  // Writers sometimes emit numbers such as "-.5" or "4." that num.parse
  // does not take; they are copied as written.
  static bool _looksNumeric(String t) => RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$').hasMatch(t);

  PdfDict _dict() {
    pos += 2;
    final entries = <String, PdfValue>{};
    while (true) {
      skipWhite();
      if (atEnd) throw const PdfReadException('Unclosed dictionary');
      if (bytes[pos] == 0x3E && pos + 1 < bytes.length && bytes[pos + 1] == 0x3E) {
        pos += 2;
        break;
      }
      final key = value();
      if (key is! PdfName) throw PdfReadException('Dictionary key is not a name at $pos');
      skipWhite();
      // A key with no value before ">>" is treated as null.
      if (bytes[pos] == 0x3E && pos + 1 < bytes.length && bytes[pos + 1] == 0x3E) {
        entries[key.raw] = const PdfNull();
        continue;
      }
      entries[key.raw] = value();
    }
    return PdfDict(entries);
  }

  Uint8List _literalString() {
    pos++;
    final out = BytesBuilder(copy: false);
    var depth = 1;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x5C) {
        if (pos >= bytes.length) break;
        final e = bytes[pos++];
        switch (e) {
          case 0x6E:
            out.addByte(10);
          case 0x72:
            out.addByte(13);
          case 0x74:
            out.addByte(9);
          case 0x62:
            out.addByte(8);
          case 0x66:
            out.addByte(12);
          case 13:
            if (pos < bytes.length && bytes[pos] == 10) pos++;
          case 10:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var i = 0; i < 2 && pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x37; i++) {
                v = v * 8 + bytes[pos++] - 0x30;
              }
              out.addByte(v & 0xFF);
            } else {
              out.addByte(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.addByte(c);
      } else if (c == 0x29) {
        if (--depth == 0) return out.takeBytes();
        out.addByte(c);
      } else if (c == 13) {
        // An unescaped end of line is read as a single line feed.
        if (pos < bytes.length && bytes[pos] == 10) pos++;
        out.addByte(10);
      } else {
        out.addByte(c);
      }
    }
    throw const PdfReadException('Unclosed string');
  }

  Uint8List _hexString() {
    pos++;
    final out = BytesBuilder(copy: false);
    int? high;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x3E) {
        if (high != null) out.addByte(high << 4);
        return out.takeBytes();
      }
      final v = _hexValue(c);
      if (v < 0) continue;
      if (high == null) {
        high = v;
      } else {
        out.addByte(high << 4 | v);
        high = null;
      }
    }
    throw const PdfReadException('Unclosed hex string');
  }
}

class _Entry {
  const _Entry.inFile(this.offset) : stream = null, index = null;
  const _Entry.inStream(this.stream, this.index) : offset = null;
  const _Entry.free() : offset = null, stream = null, index = null;

  final int? offset;
  final int? stream;
  final int? index;

  bool get isFree => offset == null && stream == null;
}

/// The objects of a PDF file, read on demand.
class PdfObjectFile {
  PdfObjectFile._(this.bytes);

  /// Reads the cross-reference data of [bytes]. A file whose cross-reference
  /// data is damaged is read by scanning for its objects instead.
  factory PdfObjectFile.parse(Uint8List bytes) {
    final file = PdfObjectFile._(bytes);
    if (!_startsWithPdfHeader(bytes)) throw const PdfReadException('This is not a PDF file');
    try {
      file._readXrefChain();
      if (file.trailer['Root'] is! PdfRef) throw const PdfReadException('No document catalog');
    } on Object {
      file._entries.clear();
      file._gens.clear();
      file._cache.clear();
      file._scanForObjects();
    }
    return file;
  }

  final Uint8List bytes;
  final Map<int, _Entry> _entries = {};
  final Map<int, int> _gens = {};
  final Map<int, PdfValue> _cache = {};
  final Map<int, (List<int>, List<int>, int, Uint8List)> _objectStreams = {};
  PdfDict trailer = PdfDict({});

  static bool _startsWithPdfHeader(Uint8List b) {
    final head = latin1.decode(Uint8List.sublistView(b, 0, b.length < 1024 ? b.length : 1024));
    return head.contains('%PDF-');
  }

  /// Numbers of the objects in use, in order.
  List<int> get objectNumbers => [
    for (final e in _entries.entries)
      if (!e.value.isFree) e.key,
  ]..sort();

  int generationOf(int num) => _gens[num] ?? 0;

  /// Follows [v] if it is a reference.
  PdfValue resolve(PdfValue? v) => v is PdfRef ? object(v.num) : (v ?? const PdfNull());

  /// The object numbered [num], or null for a missing one.
  PdfValue object(int num) {
    final cached = _cache[num];
    if (cached != null) return cached;
    final e = _entries[num];
    if (e == null || e.isFree) return const PdfNull();
    final PdfValue v;
    if (e.offset != null) {
      v = _objectAt(e.offset!);
    } else {
      v = _fromObjectStream(e.stream!, e.index!);
    }
    _cache[num] = v;
    return v;
  }

  // --- Cross-reference data ---

  void _readXrefChain() {
    final start = _findStartXref();
    final seen = <int>{};
    int? offset = start;
    var first = true;
    while (offset != null && seen.add(offset)) {
      final lexer = PdfLexer(bytes, offset)..skipWhite();
      final PdfDict section;
      if (lexer.startsWith('xref')) {
        section = _readXrefTable(lexer);
        final hybrid = section['XRefStm'];
        if (hybrid is PdfNumber) _readXrefStream(hybrid.asInt);
      } else {
        section = _readXrefStream(offset);
      }
      if (first) {
        trailer = PdfDict({...section.entries});
        first = false;
      } else {
        for (final key in const ['Root', 'Info', 'ID', 'Encrypt']) {
          final v = section[key];
          if (v != null && trailer[key] == null) trailer[key] = v;
        }
      }
      final prev = section['Prev'];
      offset = prev is PdfNumber ? prev.asInt : null;
    }
  }

  int _findStartXref() {
    final from = bytes.length > 4096 ? bytes.length - 4096 : 0;
    final tail = latin1.decode(Uint8List.sublistView(bytes, from));
    final at = tail.lastIndexOf('startxref');
    if (at < 0) throw const PdfReadException('No startxref');
    return PdfLexer(bytes, from + at + 9).readInt();
  }

  void _put(int num, int gen, _Entry entry) {
    // Newer sections are read first, so an entry already set wins.
    if (_entries.containsKey(num)) return;
    _entries[num] = entry;
    _gens[num] = gen;
  }

  PdfDict _readXrefTable(PdfLexer lexer) {
    lexer.pos += 4;
    while (true) {
      lexer.skipWhite();
      if (lexer.startsWith('trailer')) {
        lexer.pos += 7;
        final t = lexer.value();
        if (t is! PdfDict) throw const PdfReadException('Bad trailer');
        return t;
      }
      final first = lexer.readInt();
      final count = lexer.readInt();
      for (var i = 0; i < count; i++) {
        final offset = lexer.readInt();
        final gen = lexer.readInt();
        final kind = lexer.token();
        if (kind == 'n') {
          _put(first + i, gen, _Entry.inFile(offset));
        } else if (kind == 'f') {
          _put(first + i, gen, const _Entry.free());
        } else {
          throw PdfReadException('Bad xref entry "$kind"');
        }
      }
    }
  }

  PdfDict _readXrefStream(int offset) {
    final s = _objectAt(offset);
    if (s is! PdfStream) throw const PdfReadException('Bad xref stream');
    final dict = s.dict;
    final data = decodeStream(s);
    final w = [for (final v in (dict['W'] as PdfArray).items) (v as PdfNumber).asInt];
    final size = (dict['Size'] as PdfNumber).asInt;
    final index = dict['Index'] is PdfArray
        ? [for (final v in (dict['Index'] as PdfArray).items) (v as PdfNumber).asInt]
        : [0, size];
    var pos = 0;
    int field(int width, int fallback) {
      if (width == 0) return fallback;
      var v = 0;
      for (var i = 0; i < width; i++) {
        v = v << 8 | data[pos++];
      }
      return v;
    }

    final rowLength = w[0] + w[1] + w[2];
    for (var k = 0; k + 1 < index.length; k += 2) {
      for (var i = 0; i < index[k + 1]; i++) {
        if (pos + rowLength > data.length) return dict;
        final type = field(w[0], 1);
        final a = field(w[1], 0);
        final b = field(w[2], 0);
        final num = index[k] + i;
        switch (type) {
          case 0:
            _put(num, b, const _Entry.free());
          case 1:
            _put(num, b, _Entry.inFile(a));
          case 2:
            _put(num, 0, _Entry.inStream(a, b));
        }
      }
    }
    return dict;
  }

  /// Fallback for damaged files: every "n g obj" in the file, the last one
  /// of each number winning, and the catalog found among them.
  void _scanForObjects() {
    final text = latin1.decode(bytes);
    final pattern = RegExp(r'(?:^|[\r\n\s])(\d+)\s+(\d+)\s+obj\b');
    for (final m in pattern.allMatches(text)) {
      final num = int.parse(m.group(1)!);
      _entries[num] = _Entry.inFile(m.start + (m.group(0)!.length - m.group(0)!.trimLeft().length));
      _gens[num] = int.parse(m.group(2)!);
    }
    // Objects packed in object streams.
    for (final num in objectNumbers) {
      final v = _tryObject(num);
      if (v is PdfStream && v.dict.name('Type') == 'ObjStm') {
        try {
          final (nums, _, _, _) = _objectStream(num);
          for (var i = 0; i < nums.length; i++) {
            _entries.putIfAbsent(nums[i], () => _Entry.inStream(num, i));
          }
        } on Object {
          // Skip a damaged object stream.
        }
      }
    }
    trailer = PdfDict({});
    final at = text.lastIndexOf('trailer');
    if (at >= 0) {
      try {
        final t = PdfLexer(bytes, at + 7).value();
        if (t is PdfDict) trailer = t;
      } on Object {
        // Keep looking for the catalog below.
      }
    }
    if (trailer['Root'] is! PdfRef) {
      for (final num in objectNumbers) {
        final v = _tryObject(num);
        if (v is PdfDict && v.name('Type') == 'Catalog') {
          trailer['Root'] = PdfRef(num, generationOf(num));
        }
      }
    }
    if (trailer['Root'] is! PdfRef) throw const PdfReadException('This PDF is damaged and could not be read');
  }

  PdfValue? _tryObject(int num) {
    try {
      return object(num);
    } on Object {
      return null;
    }
  }

  // --- Objects ---

  PdfValue _objectAt(int offset) {
    final lexer = PdfLexer(bytes, offset);
    lexer.readInt();
    lexer.readInt();
    if (lexer.token() != 'obj') throw PdfReadException('No object at $offset');
    final v = lexer.value();
    lexer.skipWhite();
    if (v is PdfDict && lexer.startsWith('stream')) {
      var start = lexer.pos + 6;
      if (start < bytes.length && bytes[start] == 13) start++;
      if (start < bytes.length && bytes[start] == 10) start++;
      return PdfStream(v, _streamData(v, start));
    }
    return v;
  }

  Uint8List _streamData(PdfDict dict, int start) {
    int? length;
    try {
      final l = resolve(dict['Length']);
      if (l is PdfNumber) length = l.asInt;
    } on Object {
      length = null;
    }
    if (length != null && length >= 0 && start + length <= bytes.length) {
      final check = PdfLexer(bytes, start + length)..skipWhite();
      if (check.startsWith('endstream')) return Uint8List.sublistView(bytes, start, start + length);
    }
    // A wrong /Length: the data runs to "endstream", less the end of line.
    var end = _indexOf('endstream', start);
    if (end < 0) throw const PdfReadException('Unclosed stream');
    if (end > start && bytes[end - 1] == 10) end--;
    if (end > start && bytes[end - 1] == 13) end--;
    return Uint8List.sublistView(bytes, start, end);
  }

  int _indexOf(String word, int from) {
    final first = word.codeUnitAt(0);
    outer:
    for (var i = from; i + word.length <= bytes.length; i++) {
      if (bytes[i] != first) continue;
      for (var j = 1; j < word.length; j++) {
        if (bytes[i + j] != word.codeUnitAt(j)) continue outer;
      }
      return i;
    }
    return -1;
  }

  (List<int>, List<int>, int, Uint8List) _objectStream(int num) {
    final cached = _objectStreams[num];
    if (cached != null) return cached;
    final s = object(num);
    if (s is! PdfStream) throw PdfReadException('Object stream $num is missing');
    final data = decodeStream(s);
    final n = (resolve(s.dict['N']) as PdfNumber).asInt;
    final first = (resolve(s.dict['First']) as PdfNumber).asInt;
    final lexer = PdfLexer(data);
    final nums = <int>[];
    final offsets = <int>[];
    for (var i = 0; i < n; i++) {
      nums.add(lexer.readInt());
      offsets.add(lexer.readInt());
    }
    return _objectStreams[num] = (nums, offsets, first, data);
  }

  PdfValue _fromObjectStream(int stream, int index) {
    final (nums, offsets, first, data) = _objectStream(stream);
    if (index >= nums.length) return const PdfNull();
    return PdfLexer(data, first + offsets[index]).value();
  }

  /// The decoded data of [s]. Only Flate, with or without a PNG predictor,
  /// is needed here: it is what cross-reference and object streams use.
  Uint8List decodeStream(PdfStream s) {
    final filter = resolve(s.dict['Filter']);
    final filters = switch (filter) {
      PdfName(:final raw) => [raw],
      PdfArray(:final items) => [for (final i in items) (resolve(i) as PdfName).raw],
      _ => const <String>[],
    };
    if (filters.isEmpty) return s.data;
    if (filters.length != 1 || (filters.single != 'FlateDecode' && filters.single != 'Fl')) {
      throw PdfReadException('Unsupported filter $filters');
    }
    final inflated = Uint8List.fromList(ZLibDecoder().convert(s.data));
    var parms = resolve(s.dict['DecodeParms']);
    if (parms is PdfArray) parms = parms.items.isEmpty ? const PdfNull() : resolve(parms.items.first);
    if (parms is! PdfDict) return inflated;
    final predictor = (resolve(parms['Predictor']) as PdfNumber?)?.asInt ?? 1;
    if (predictor < 10) {
      if (predictor == 1) return inflated;
      throw PdfReadException('Unsupported predictor $predictor');
    }
    final colors = (resolve(parms['Colors']) as PdfNumber?)?.asInt ?? 1;
    final bits = (resolve(parms['BitsPerComponent']) as PdfNumber?)?.asInt ?? 8;
    final columns = (resolve(parms['Columns']) as PdfNumber?)?.asInt ?? 1;
    return _unpredictPng(inflated, (colors * bits + 7) ~/ 8, (columns * colors * bits + 7) ~/ 8);
  }

  static Uint8List _unpredictPng(Uint8List data, int bpp, int rowLength) {
    final rows = data.length ~/ (rowLength + 1);
    final out = Uint8List(rows * rowLength);
    for (var r = 0; r < rows; r++) {
      final type = data[r * (rowLength + 1)];
      final src = r * (rowLength + 1) + 1;
      final dst = r * rowLength;
      for (var i = 0; i < rowLength; i++) {
        final left = i >= bpp ? out[dst + i - bpp] : 0;
        final up = r > 0 ? out[dst - rowLength + i] : 0;
        final upLeft = r > 0 && i >= bpp ? out[dst - rowLength + i - bpp] : 0;
        final x = data[src + i];
        out[dst + i] =
            switch (type) {
              1 => x + left,
              2 => x + up,
              3 => x + ((left + up) >> 1),
              4 => x + _paeth(left, up, upLeft),
              _ => x,
            } &
            0xFF;
      }
    }
    return out;
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    return pb <= pc ? b : c;
  }
}
