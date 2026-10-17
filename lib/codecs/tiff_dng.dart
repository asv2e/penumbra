// Pure-Dart TIFF / DNG / RAW-preview codecs. No dart:ui or dart:io so every
// function here can run in an isolate (or inline on web).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibDecoder;
import 'package:image/image.dart' as img;

class RgbaImage {
  const RgbaImage(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

class DecodeRequest {
  const DecodeRequest(this.bytes, this.maxSide);
  final Uint8List bytes;
  final int maxSide;
}

class EncodeRequest {
  const EncodeRequest(this.rgba, this.width, this.height, this.format, this.quality);
  final Uint8List rgba;
  final int width;
  final int height;

  /// 'jpeg' or 'tiff'.
  final String format;
  final int quality;
}

/// Identifies a file by its magic bytes.
String sniffFormat(Uint8List b) {
  bool at(int o, List<int> m) {
    if (b.length < o + m.length) return false;
    for (var i = 0; i < m.length; i++) {
      if (b[o + i] != m[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8])) return 'jpeg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (at(0, const [0x42, 0x4D])) return 'bmp';
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) return 'webp';
  if (at(0, const [0x46, 0x55, 0x4A, 0x49, 0x46, 0x49, 0x4C, 0x4D])) return 'raf';
  if (at(4, const [0x66, 0x74, 0x79, 0x70])) {
    if (at(8, const [0x63, 0x72, 0x78, 0x20])) return 'cr3';
    return 'heic';
  }
  if (b.length > 4 && ((b[0] == 0x49 && b[1] == 0x49) || (b[0] == 0x4D && b[1] == 0x4D))) {
    final le = b[0] == 0x49;
    final magic = le ? (b[2] | (b[3] << 8)) : ((b[2] << 8) | b[3]);
    if (magic == 42 || magic == 0x4F52 || magic == 0x5352 || magic == 0x55) return 'tiff';
  }
  return 'unknown';
}

// ------------------------------------------------------------------- TIFF

class _Entry {
  _Entry(this.tag, this.type, this.count, this.pos);
  final int tag, type, count;

  /// Absolute position of the 4-byte value/offset field.
  final int pos;
}

class _Ifd {
  final Map<int, _Entry> e = {};
  int next = 0;
}

class _Tiff {
  _Tiff(this.b) {
    if (b.length < 8) throw const FormatException('short file');
    if (b[0] == 0x49 && b[1] == 0x49) {
      endian = Endian.little;
    } else if (b[0] == 0x4D && b[1] == 0x4D) {
      endian = Endian.big;
    } else {
      throw const FormatException('not a TIFF');
    }
    bd = ByteData.sublistView(b);
  }

  final Uint8List b;
  late final Endian endian;
  late final ByteData bd;

  static const _sz = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4];

  int u16(int o) => bd.getUint16(o, endian);
  int u32(int o) => bd.getUint32(o, endian);

  _Ifd readIfd(int off) {
    if (off < 8 || off + 2 > b.length) throw const FormatException('bad IFD offset');
    final n = u16(off);
    if (n > 1024 || off + 2 + n * 12 + 4 > b.length) throw const FormatException('bad IFD');
    final ifd = _Ifd();
    for (var i = 0; i < n; i++) {
      final p = off + 2 + i * 12;
      ifd.e[u16(p)] = _Entry(u16(p), u16(p + 2), u32(p + 4), p + 8);
    }
    ifd.next = u32(off + 2 + n * 12);
    return ifd;
  }

  List<double> nums(_Entry e) {
    if (e.type < 1 || e.type >= _sz.length) return const [];
    final size = _sz[e.type];
    final total = size * e.count;
    final at = total <= 4 ? e.pos : u32(e.pos);
    if (at < 0 || at + total > b.length) return const [];
    final n = math.min(e.count, 1 << 22);
    final out = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      final o = at + i * size;
      switch (e.type) {
        case 1:
        case 2:
        case 7:
          out[i] = b[o].toDouble();
        case 6:
          out[i] = bd.getInt8(o).toDouble();
        case 3:
          out[i] = u16(o).toDouble();
        case 4:
        case 13:
          out[i] = u32(o).toDouble();
        case 5:
          final d = u32(o + 4);
          out[i] = d == 0 ? 0.0 : u32(o) / d;
        case 8:
          out[i] = bd.getInt16(o, endian).toDouble();
        case 9:
          out[i] = bd.getInt32(o, endian).toDouble();
        case 10:
          final d = bd.getInt32(o + 4, endian);
          out[i] = d == 0 ? 0.0 : bd.getInt32(o, endian) / d;
        case 11:
          out[i] = bd.getFloat32(o, endian);
        case 12:
          out[i] = bd.getFloat64(o, endian);
      }
    }
    return out;
  }

  int first(_Entry e, [int def = 0]) {
    final n = nums(e);
    return n.isEmpty ? def : n[0].toInt();
  }

  int geti(_Ifd ifd, int tag, [int def = 0]) {
    final e = ifd.e[tag];
    return e == null ? def : first(e, def);
  }

  /// IFD0 plus every chained IFD and SubIFD.
  List<_Ifd> allIfds() {
    final out = <_Ifd>[];
    final seen = <int>{};
    void walk(int off, int depth) {
      var o = off;
      while (o != 0 && depth < 4 && seen.add(o)) {
        _Ifd ifd;
        try {
          ifd = readIfd(o);
        } catch (_) {
          return;
        }
        out.add(ifd);
        final sub = ifd.e[0x14A];
        if (sub != null) {
          for (final so in nums(sub)) {
            walk(so.toInt(), depth + 1);
          }
        }
        o = ifd.next;
      }
    }

    walk(u32(4), 0);
    return out;
  }
}

class TiffProbe {
  const TiffProbe(this.isTiff, this.isDng, this.isRawLike, this.orientation);
  final bool isTiff;
  final bool isDng;

  /// Non-standard TIFF magic or CR2 header (camera RAW).
  final bool isRawLike;

  /// EXIF orientation 1..8 from IFD0.
  final int orientation;
}

TiffProbe probeTiff(Uint8List b) {
  try {
    final t = _Tiff(b);
    final ifd0 = t.readIfd(t.u32(4));
    final cr2 = b.length > 10 && b[8] == 0x43 && b[9] == 0x52;
    return TiffProbe(true, ifd0.e.containsKey(0xC612), t.u16(2) != 42 || cr2, t.geti(ifd0, 274, 1));
  } catch (_) {
    return const TiffProbe(false, false, false, 1);
  }
}

RgbaImage rotateRgba(RgbaImage im, int orientation) {
  if (orientation != 3 && orientation != 6 && orientation != 8) return im;
  final w = im.width, h = im.height;
  final src = im.rgba;
  final swap = orientation != 3;
  final ow = swap ? h : w;
  final oh = swap ? w : h;
  final out = Uint8List(ow * oh * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      int dx, dy;
      if (orientation == 3) {
        dx = w - 1 - x;
        dy = h - 1 - y;
      } else if (orientation == 6) {
        dx = h - 1 - y;
        dy = x;
      } else {
        dx = y;
        dy = w - 1 - x;
      }
      final s = (y * w + x) * 4;
      final d = (dy * ow + dx) * 4;
      out[d] = src[s];
      out[d + 1] = src[s + 1];
      out[d + 2] = src[s + 2];
      out[d + 3] = src[s + 3];
    }
  }
  return RgbaImage(out, ow, oh);
}

// Isolate entry points ----------------------------------------------------

RgbaImage? decodeTiffEntry(DecodeRequest r) {
  try {
    final probe = probeTiff(r.bytes);
    var im = img.decodeTiff(r.bytes);
    if (im == null) return null;
    if (im.format != img.Format.uint8 || im.numChannels != 4) {
      im = im.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
    }
    final big = math.max(im.width, im.height);
    if (big > r.maxSide) {
      final k = r.maxSide / big;
      im = img.copyResize(
        im,
        width: math.max(1, (im.width * k).round()),
        height: math.max(1, (im.height * k).round()),
        interpolation: img.Interpolation.average,
      );
    }
    final out = RgbaImage(im.getBytes(order: img.ChannelOrder.rgba), im.width, im.height);
    return rotateRgba(out, probe.orientation);
  } catch (_) {
    return null;
  }
}

Uint8List encodeEntry(EncodeRequest r) {
  var im = img.Image.fromBytes(
    width: r.width,
    height: r.height,
    bytes: r.rgba.buffer,
    bytesOffset: r.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  if (r.format == 'tiff') return Uint8List.fromList(img.encodeTiff(im));
  im = im.convert(numChannels: 3);
  return Uint8List.fromList(img.encodeJpg(im, quality: r.quality));
}

/// Embedded JPEG previews of a RAW file, largest first.
List<Uint8List> previewEntry(Uint8List b) {
  final out = <Uint8List>[];
  try {
    final t = _Tiff(b);
    final cands = <List<int>>[];
    void cand(int off, int len) {
      if (off > 0 && len > 1024 && off + len <= b.length && b[off] == 0xFF && b[off + 1] == 0xD8) {
        cands.add([off, len]);
      }
    }

    for (final ifd in t.allIfds()) {
      final photo = t.geti(ifd, 262);
      if (photo == 32803 || photo == 34892) continue;
      final jo = ifd.e[0x201], jl = ifd.e[0x202];
      if (jo != null && jl != null) cand(t.first(jo), t.first(jl));
      final comp = t.geti(ifd, 259);
      final so = ifd.e[273], sc = ifd.e[279];
      if ((comp == 6 || comp == 7) && so != null && sc != null) {
        final offs = t.nums(so), cnts = t.nums(sc);
        if (offs.length == 1 && cnts.length == 1) cand(offs[0].toInt(), cnts[0].toInt());
      }
    }
    cands.sort((a, c) => c[1].compareTo(a[1]));
    for (final c in cands) {
      out.add(Uint8List.sublistView(b, c[0], c[0] + c[1]));
    }
  } catch (_) {}
  if (out.isEmpty) out.addAll(_scanJpegs(b));
  return out.length > 6 ? out.sublist(0, 6) : out;
}

int _jpegEnd(Uint8List b, int s) {
  var i = s + 2;
  final n = b.length;
  while (i + 4 <= n) {
    if (b[i] != 0xFF) return -1;
    final m = b[i + 1];
    if (m == 0xFF) {
      i++;
      continue;
    }
    if (m == 0xD9) return i + 2;
    if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    i += 2 + len;
    if (m == 0xDA) {
      while (i + 1 < n) {
        if (b[i] == 0xFF) {
          final nx = b[i + 1];
          if (nx == 0x00 || (nx >= 0xD0 && nx <= 0xD7)) {
            i += 2;
            continue;
          }
          if (nx == 0xFF) {
            i++;
            continue;
          }
          break;
        }
        i++;
      }
    }
  }
  return -1;
}

List<Uint8List> _scanJpegs(Uint8List b) {
  final out = <Uint8List>[];
  var i = 0;
  while (i + 3 < b.length) {
    if (b[i] == 0xFF && b[i + 1] == 0xD8 && b[i + 2] == 0xFF) {
      final e = _jpegEnd(b, i);
      if (e > i + 8192) {
        out.add(Uint8List.sublistView(b, i, e));
        i = e;
        continue;
      }
    }
    i++;
  }
  out.sort((a, c) => c.length.compareTo(a.length));
  return out;
}

// ------------------------------------------------- lossless JPEG (DNG)

class _Lj {
  _Lj(this.samples, this.rowLen, this.rows);
  final Uint16List samples;
  final int rowLen;
  final int rows;
}

Int32List _buildHuff(Uint8List counts, Uint8List syms) {
  final t = Int32List(65536);
  var code = 0, k = 0;
  for (var len = 1; len <= 16; len++) {
    for (var j = 0; j < counts[len - 1]; j++) {
      if (k >= syms.length) throw const FormatException('bad huffman table');
      final sym = syms[k++];
      final shift = 16 - len;
      final start = code << shift;
      final end = start + (1 << shift);
      if (end > 65536) throw const FormatException('bad huffman code');
      final v = (sym << 8) | len;
      for (var q = start; q < end; q++) {
        t[q] = v;
      }
      code++;
    }
    code <<= 1;
  }
  return t;
}

class _BitSrc {
  _BitSrc(this.d, this.pos);
  final Uint8List d;
  int pos;
  int buf = 0;
  int cnt = 0;
  bool hitMarker = false;

  void _fill() {
    while (cnt <= 16) {
      var byte = 0;
      if (!hitMarker && pos < d.length) {
        final b = d[pos];
        if (b == 0xFF) {
          final n = pos + 1 < d.length ? d[pos + 1] : 0xD9;
          if (n == 0x00) {
            byte = 0xFF;
            pos += 2;
          } else {
            hitMarker = true;
          }
        } else {
          byte = b;
          pos++;
        }
      }
      buf = (buf << 8) | byte;
      cnt += 8;
    }
  }

  int huff(Int32List t) {
    _fill();
    final e = t[(buf >> (cnt - 16)) & 0xFFFF];
    final len = e & 0xFF;
    if (len == 0) throw const FormatException('bad huffman symbol');
    cnt -= len;
    buf &= (1 << cnt) - 1;
    return e >> 8;
  }

  int bits(int n) {
    if (n == 0) return 0;
    _fill();
    cnt -= n;
    final v = (buf >> cnt) & ((1 << n) - 1);
    buf &= (1 << cnt) - 1;
    return v;
  }

  void restart() {
    cnt = 0;
    buf = 0;
    while (pos + 1 < d.length && !(d[pos] == 0xFF && d[pos + 1] >= 0xD0 && d[pos + 1] <= 0xD7)) {
      pos++;
    }
    pos += 2;
    hitMarker = false;
  }
}

_Lj _decodeLjpeg(Uint8List d) {
  if (d.length < 4 || d[0] != 0xFF || d[1] != 0xD8) throw const FormatException('not a JPEG');
  var i = 2;
  final tables = List<Int32List?>.filled(4, null);
  final compTable = List<int>.filled(4, 0);
  var prec = 0, ys = 0, xs = 0, nc = 0, pt = 0, predSel = 1, restart = 0;
  var scanStart = -1;
  while (i + 4 <= d.length && scanStart < 0) {
    if (d[i] != 0xFF) {
      i++;
      continue;
    }
    final m = d[i + 1];
    if (m == 0xFF) {
      i++;
      continue;
    }
    if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (d[i + 2] << 8) | d[i + 3];
    final seg = i + 4;
    if (m == 0xC4) {
      var p = seg;
      final end = i + 2 + len;
      while (p + 17 <= end) {
        final th = d[p++] & 15;
        final counts = Uint8List.sublistView(d, p, p + 16);
        p += 16;
        var total = 0;
        for (final c in counts) {
          total += c;
        }
        final syms = Uint8List.sublistView(d, p, math.min(p + total, d.length));
        p += total;
        tables[th & 3] = _buildHuff(counts, syms);
      }
    } else if (m == 0xC3) {
      prec = d[seg];
      ys = (d[seg + 1] << 8) | d[seg + 2];
      xs = (d[seg + 3] << 8) | d[seg + 4];
      nc = d[seg + 5];
    } else if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
      throw const FormatException('not lossless JPEG');
    } else if (m == 0xDD) {
      restart = (d[seg] << 8) | d[seg + 1];
    } else if (m == 0xDA) {
      final ns = d[seg];
      for (var k = 0; k < ns && k < 4; k++) {
        compTable[k] = (d[seg + 2 + 2 * k] >> 4) & 3;
      }
      final p = seg + 1 + 2 * ns;
      predSel = d[p];
      pt = d[p + 2] & 15;
      scanStart = i + 2 + len;
    }
    i += 2 + len;
  }
  if (scanStart < 0 || nc < 1 || nc > 4 || xs < 1 || ys < 1 || prec < 2 || prec > 16) {
    throw const FormatException('bad lossless JPEG header');
  }
  final rowLen = xs * nc;
  final out = Uint16List(rowLen * ys);
  final src = _BitSrc(d, scanStart);
  final total = xs * ys;
  final def = 1 << (prec - pt - 1);
  var startP = 0;
  for (var p = 0; p < total; p++) {
    if (restart > 0 && p > 0 && p % restart == 0) {
      src.restart();
      startP = p;
    }
    final y = p ~/ xs;
    final x = p - y * xs;
    final base = p * nc;
    final rel = p - startP;
    for (var c = 0; c < nc; c++) {
      final tbl = tables[compTable[c]];
      if (tbl == null) throw const FormatException('missing huffman table');
      final s = src.huff(tbl);
      int diff;
      if (s == 0) {
        diff = 0;
      } else if (s == 16) {
        diff = 32768;
      } else {
        var v = src.bits(s);
        if (v < (1 << (s - 1))) v -= (1 << s) - 1;
        diff = v;
      }
      final idx = base + c;
      int pred;
      if (rel == 0) {
        pred = def;
      } else if (rel < xs) {
        pred = out[idx - nc];
      } else if (x == 0) {
        pred = out[idx - rowLen];
      } else {
        final ra = out[idx - nc];
        final rb = out[idx - rowLen];
        final rc = out[idx - rowLen - nc];
        switch (predSel) {
          case 2:
            pred = rb;
          case 3:
            pred = rc;
          case 4:
            pred = ra + rb - rc;
          case 5:
            pred = ra + ((rb - rc) >> 1);
          case 6:
            pred = rb + ((ra - rc) >> 1);
          case 7:
            pred = (ra + rb) >> 1;
          default:
            pred = ra;
        }
      }
      out[idx] = (pred + diff) & 0xFFFF;
    }
  }
  if (pt > 0) {
    for (var k = 0; k < out.length; k++) {
      out[k] = (out[k] << pt) & 0xFFFF;
    }
  }
  return _Lj(out, rowLen, ys);
}

// -------------------------------------------------------------------- DNG

Uint16List _unpack(Uint8List d, int rows, int rowLen, int bps, Endian e) {
  final out = Uint16List(rows * rowLen);
  if (bps == 16) {
    final bd = ByteData.sublistView(d);
    final n = math.min(out.length, d.length ~/ 2);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getUint16(i * 2, e);
    }
  } else if (bps == 8) {
    final n = math.min(out.length, d.length);
    for (var i = 0; i < n; i++) {
      out[i] = d[i];
    }
  } else {
    final rowBytes = (rowLen * bps + 7) >> 3;
    final end = d.length * 8;
    for (var y = 0; y < rows; y++) {
      var bit = y * rowBytes * 8;
      for (var x = 0; x < rowLen; x++) {
        if (bit + bps > end) break;
        var v = 0;
        for (var k = 0; k < bps; k++, bit++) {
          v = (v << 1) | ((d[bit >> 3] >> (7 - (bit & 7))) & 1);
        }
        out[y * rowLen + x] = v;
      }
    }
  }
  return out;
}

const _xyz2srgb = <double>[
  3.1338561, -1.6168667, -0.4906146,
  -0.9787684, 1.9161415, 0.0334540,
  0.0719453, -0.2289914, 1.4052427,
];

List<double> _mul3(List<double> a, List<double> b) {
  final o = List<double>.filled(9, 0.0);
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      var s = 0.0;
      for (var k = 0; k < 3; k++) {
        s += a[i * 3 + k] * b[k * 3 + j];
      }
      o[i * 3 + j] = s;
    }
  }
  return o;
}

List<double>? _inv3(List<double> m) {
  final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det.abs() < 1e-12) return null;
  final k = 1 / det;
  return [
    (e * i - f * h) * k, (c * h - b * i) * k, (b * f - c * e) * k,
    (f * g - d * i) * k, (a * i - c * g) * k, (c * d - a * f) * k,
    (d * h - e * g) * k, (b * g - a * h) * k, (a * e - b * d) * k,
  ];
}

List<double> _normRows(List<double> m) {
  final o = List<double>.of(m);
  for (var r = 0; r < 3; r++) {
    final s = m[r * 3] + m[r * 3 + 1] + m[r * 3 + 2];
    if (s.abs() > 1e-9) {
      for (var c = 0; c < 3; c++) {
        o[r * 3 + c] = m[r * 3 + c] / s;
      }
    }
  }
  return o;
}

class _Sampler {
  _Sampler({
    required this.plane,
    required this.w,
    required this.spp,
    required this.cfa,
    required this.bx,
    required this.by,
    required this.areaTop,
    required this.areaLeft,
    required this.black,
    required this.range,
  });

  final Uint16List plane;
  final int w, spp, bx, by, areaTop, areaLeft;
  final List<int> cfa;
  final List<double> black;
  final double range;

  double _bl(int site) => black.length >= 4 ? black[site] : black[0];

  /// Linear, black-subtracted, 0..1 camera RGB of output cell (i, j).
  void at(int i, int j, Float64List o) {
    if (spp == 1) {
      var r = 0.0, g = 0.0, b = 0.0;
      var gn = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final ry = by + 2 * j + dy;
          final rx = bx + 2 * i + dx;
          final rel = (((ry - areaTop) & 1) << 1) | ((rx - areaLeft) & 1);
          var v = plane[ry * w + rx] - _bl(rel);
          if (v < 0) v = 0;
          switch (cfa[rel]) {
            case 0:
              r = v;
            case 1:
              g += v;
              gn++;
            default:
              b = v;
          }
        }
      }
      if (gn > 1) g /= gn;
      o[0] = r / range;
      o[1] = g / range;
      o[2] = b / range;
    } else {
      final p = ((by + j) * w + (bx + i)) * 3;
      for (var c = 0; c < 3; c++) {
        var v = plane[p + c] - (black.length >= 3 ? black[c] : black[0]);
        if (v < 0) v = 0;
        o[c] = v / range;
      }
    }
  }
}

RgbaImage? decodeDngEntry(DecodeRequest r) {
  try {
    return _decodeDng(r.bytes, r.maxSide);
  } catch (_) {
    return null;
  }
}

RgbaImage? _decodeDng(Uint8List b, int maxSide) {
  final t = _Tiff(b);
  final ifds = t.allIfds();
  if (ifds.isEmpty) return null;
  final ifd0 = ifds.first;

  _Ifd? best;
  var bestArea = 0;
  for (final ifd in ifds) {
    final photo = t.geti(ifd, 262);
    if (photo != 32803 && photo != 34892) continue;
    final area = t.geti(ifd, 256) * t.geti(ifd, 257);
    if (area > bestArea) {
      bestArea = area;
      best = ifd;
    }
  }
  final raw = best;
  if (raw == null) return null;

  List<double>? tag(int id) {
    final e = raw.e[id] ?? ifd0.e[id];
    return e == null ? null : t.nums(e);
  }

  final w = t.geti(raw, 256), h = t.geti(raw, 257);
  final spp = t.geti(raw, 277, 1);
  final photo = t.geti(raw, 262);
  final bps = (tag(258) ?? const [16.0])[0].toInt();
  final comp = t.geti(raw, 259, 1);
  final predictor = t.geti(raw, 317, 1);
  if (t.geti(raw, 339, 1) != 1) return null;
  if (w <= 0 || h <= 0 || w * h > 250000000) return null;
  if ((photo == 32803 && spp != 1) || (photo == 34892 && spp != 3)) return null;

  final plane = Uint16List(w * h * spp);
  final tiled = raw.e.containsKey(324);
  final offEntry = raw.e[tiled ? 324 : 273];
  final cntEntry = raw.e[tiled ? 325 : 279];
  if (offEntry == null || cntEntry == null) return null;
  final offs = [for (final v in t.nums(offEntry)) v.toInt()];
  final cnts = [for (final v in t.nums(cntEntry)) v.toInt()];
  final tw = tiled ? t.geti(raw, 322) : w;
  final th = tiled ? t.geti(raw, 323) : math.min(t.geti(raw, 278, h), h);
  if (tw <= 0 || th <= 0) return null;
  final across = (w + tw - 1) ~/ tw;

  for (var i = 0; i < offs.length && i < cnts.length; i++) {
    final start = offs[i], len = cnts[i];
    if (start < 0 || len <= 0 || start + len > b.length) return null;
    final data = Uint8List.sublistView(b, start, start + len);
    final tx = (i % across) * tw;
    final ty = (i ~/ across) * th;
    final rows = tiled ? th : math.min(th, h - ty);
    if (rows <= 0) break;
    final rowLen = tw * spp;
    Uint16List samples;
    var stride = rowLen;
    var srcRows = rows;
    if (comp == 1) {
      samples = _unpack(data, rows, rowLen, bps, t.endian);
    } else if (comp == 7) {
      final lj = _decodeLjpeg(data);
      samples = lj.samples;
      stride = lj.rowLen;
      srcRows = math.min(rows, lj.rows);
    } else if (comp == 8) {
      final inflated = Uint8List.fromList(ZLibDecoder().decodeBytes(data));
      samples = _unpack(inflated, rows, rowLen, bps, t.endian);
      if (predictor == 2) {
        for (var y = 0; y < rows; y++) {
          final o = y * rowLen;
          for (var x = spp; x < rowLen; x++) {
            samples[o + x] = (samples[o + x] + samples[o + x - spp]) & 0xFFFF;
          }
        }
      } else if (predictor != 1) {
        return null;
      }
    } else {
      return null;
    }
    final copyW = math.min(stride, (w - tx) * spp);
    for (var y = 0; y < srcRows; y++) {
      final py = ty + y;
      if (py >= h) break;
      final dst = (py * w + tx) * spp;
      plane.setRange(dst, dst + copyW, samples, y * stride);
    }
  }

  // Colour parameters.
  final black = tag(50714) ?? const [0.0];
  final white = (tag(50717) ?? [(1 << bps) - 1.0])[0];
  final area = tag(50829) ?? [0.0, 0.0, h.toDouble(), w.toDouble()];
  final cropO = tag(50719) ?? const [0.0, 0.0];
  final cropS = tag(50720) ?? [area[3] - area[1], area[2] - area[0]];
  final areaTop = area[0].round(), areaLeft = area[1].round();
  var x0 = areaLeft + cropO[0].round();
  var y0 = areaTop + cropO[1].round();
  x0 = math.min(math.max(x0, 0), w - 2);
  y0 = math.min(math.max(y0, 0), h - 2);
  final cw = math.min(cropS[0].round(), w - x0);
  final ch = math.min(cropS[1].round(), h - y0);

  var cfa = <int>[];
  int bx, by, ow, oh;
  if (photo == 32803) {
    final dim = tag(33421) ?? const [2.0, 2.0];
    if (dim.length < 2 || dim[0] != 2 || dim[1] != 2) return null;
    final pat = tag(33422);
    if (pat == null || pat.length < 4) return null;
    cfa = [for (var i = 0; i < 4; i++) pat[i].toInt()];
    bx = x0 + (x0 & 1);
    by = y0 + (y0 & 1);
    ow = (x0 + cw - bx) ~/ 2;
    oh = (y0 + ch - by) ~/ 2;
  } else {
    bx = x0;
    by = y0;
    ow = cw;
    oh = ch;
  }
  if (ow < 1 || oh < 1) return null;

  final blackAvg = black.reduce((a, c) => a + c) / black.length;
  final range = math.max(1.0, white - blackAvg);
  final sampler = _Sampler(
    plane: plane,
    w: w,
    spp: spp,
    cfa: cfa,
    bx: bx,
    by: by,
    areaTop: areaTop,
    areaLeft: areaLeft,
    black: black,
    range: range,
  );

  var gains = const [1.0, 1.0, 1.0];
  final an = tag(50728);
  if (an != null && an.length >= 3 && an[0] > 0 && an[1] > 0 && an[2] > 0) {
    gains = [an[1] / an[0], 1.0, an[1] / an[2]];
  }
  var mat = const <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
  final fm = tag(50964);
  final cm = tag(50721);
  if (fm != null && fm.length == 9) {
    mat = _mul3(_xyz2srgb, fm);
  } else if (cm != null && cm.length == 9) {
    final inv = _inv3(cm);
    if (inv != null) mat = _normRows(_mul3(_xyz2srgb, inv));
  }

  final k = math.max(1, (math.max(ow, oh) / maxSide).ceil());
  final outW = ow ~/ k, outH = oh ~/ k;
  if (outW < 1 || outH < 1) return null;

  final tmp = Float64List(3);
  final acc = Float64List(3);
  final px = Float64List(3);
  void cell(int oi, int oj) {
    acc[0] = 0;
    acc[1] = 0;
    acc[2] = 0;
    for (var dj = 0; dj < k; dj++) {
      for (var di = 0; di < k; di++) {
        sampler.at(oi * k + di, oj * k + dj, tmp);
        acc[0] += tmp[0];
        acc[1] += tmp[1];
        acc[2] += tmp[2];
      }
    }
    final inv = 1.0 / (k * k);
    final cr = acc[0] * inv * gains[0];
    final cg = acc[1] * inv * gains[1];
    final cb = acc[2] * inv * gains[2];
    px[0] = mat[0] * cr + mat[1] * cg + mat[2] * cb;
    px[1] = mat[3] * cr + mat[4] * cg + mat[5] * cb;
    px[2] = mat[6] * cr + mat[7] * cg + mat[8] * cb;
  }

  // Exposure: map the 99.5th percentile of luminance to near white.
  final lums = <double>[];
  final sx = math.max(1, outW ~/ 200), sy = math.max(1, outH ~/ 200);
  for (var j = 0; j < outH; j += sy) {
    for (var i = 0; i < outW; i += sx) {
      cell(i, j);
      lums.add(0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2]);
    }
  }
  lums.sort();
  final p995 = lums.isEmpty ? 1.0 : lums[math.min(lums.length - 1, (lums.length * 0.995).floor())];
  final scale = math.min(16.0, math.max(0.5, 0.92 / math.max(p995, 1e-4)));

  final gam = Uint8List(4096);
  for (var i = 0; i < 4096; i++) {
    final v = i / 4095.0;
    final g = v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    gam[i] = math.min(255, math.max(0, (g * 255).round()));
  }
  int enc(double v) {
    final s = v * scale;
    if (s <= 0) return 0;
    if (s >= 1) return 255;
    return gam[(s * 4095).round()];
  }

  final out = Uint8List(outW * outH * 4);
  var o = 0;
  for (var j = 0; j < outH; j++) {
    for (var i = 0; i < outW; i++) {
      cell(i, j);
      out[o++] = enc(px[0]);
      out[o++] = enc(px[1]);
      out[o++] = enc(px[2]);
      out[o++] = 255;
    }
  }
  return rotateRgba(RgbaImage(out, outW, outH), t.geti(ifd0, 274, 1));
}
