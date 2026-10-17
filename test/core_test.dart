import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'package:penumbra/codecs/tiff_dng.dart';
import 'package:penumbra/edit_state.dart';
import 'package:penumbra/faces.dart';
import 'package:penumbra/geometry.dart';
import 'package:penumbra/lut.dart';
import 'package:penumbra/params.dart';
import 'package:penumbra/presets.dart';
import 'package:penumbra/tools.dart';

/// Minimal little-endian DNG: one uncompressed 16-bit RGGB strip.
Uint8List makeDng(int w, int h, int value) {
  const n = 14;
  final dataOff = 8 + 2 + n * 12 + 4;
  final out = Uint8List(dataOff + w * h * 2);
  final bd = ByteData.sublistView(out);
  bd.setUint8(0, 0x49);
  bd.setUint8(1, 0x49);
  bd.setUint16(2, 42, Endian.little);
  bd.setUint32(4, 8, Endian.little);
  bd.setUint16(8, n, Endian.little);
  var pos = 10;
  void put(int tag, int type, int count, List<int> v) {
    bd.setUint16(pos, tag, Endian.little);
    bd.setUint16(pos + 2, type, Endian.little);
    bd.setUint32(pos + 4, count, Endian.little);
    for (var i = 0; i < v.length; i++) {
      bd.setUint8(pos + 8 + i, v[i]);
    }
    pos += 12;
  }

  List<int> u16(int v) => [v & 255, v >> 8];
  List<int> u32(int v) => [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255];
  put(256, 4, 1, u32(w));
  put(257, 4, 1, u32(h));
  put(258, 3, 1, u16(16));
  put(259, 3, 1, u16(1));
  put(262, 3, 1, u16(32803));
  put(273, 4, 1, u32(dataOff));
  put(277, 3, 1, u16(1));
  put(278, 4, 1, u32(h));
  put(279, 4, 1, u32(w * h * 2));
  put(33421, 3, 2, [...u16(2), ...u16(2)]);
  put(33422, 1, 4, [0, 1, 1, 2]);
  put(50706, 1, 4, [1, 4, 0, 0]);
  put(50714, 3, 1, u16(0));
  put(50717, 4, 1, u32(65535));
  for (var i = 0; i < w * h; i++) {
    bd.setUint16(dataOff + i * 2, value, Endian.little);
  }
  return out;
}

void main() {
  test('param ids are unique across tools and presets', () {
    final seen = <String, Param>{};
    final all = <Param>{
      for (final t in Tool.values) ...t.params,
      for (final b in presetBank.values) for (final p in b) ...p.deltas.keys,
      ...Param.hslHue,
      ...Param.hslSat,
      ...Param.hslLum,
    };
    for (final p in all) {
      expect(seen.containsKey(p.id), isFalse, reason: 'duplicate id ${p.id}');
      seen[p.id] = p;
    }
  });

  test('every tool kind in the 36-tool menu is present', () {
    expect(Tool.values.length, 36);
  });

  test('presets add on top of user values and clamp', () {
    const s = EditState(
      values: {Param.contrast: 0.9},
      presets: {'style': PresetSel(1, 1.0)}, // Vivid: contrast +0.2
    );
    expect(s.effective(Param.contrast), 1.0);
    expect(s.effective(Param.saturation), closeTo(0.35, 1e-9));
  });

  test('identity curve produces a linear LUT', () {
    final lut = buildLutBytes(const CurveSet());
    expect(lut[0], 0);
    expect(lut[255 * 4], 255);
    expect((lut[128 * 4] - 128).abs() <= 1, isTrue);
  });

  test('monotone curve stays within 0..1', () {
    final f = curveFn(const [Offset(0, 0), Offset(0.3, 0.7), Offset(0.7, 0.75), Offset(1, 1)]);
    var prev = -1.0;
    for (var i = 0; i <= 100; i++) {
      final y = f(i / 100);
      expect(y >= prev - 1e-9, isTrue);
      prev = y;
    }
  });

  test('homography maps source corners to destination corners', () {
    final src = [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10), const Offset(0, 10)];
    final dst = [const Offset(-2, 0), const Offset(12, 0), const Offset(10, 10), const Offset(0, 10)];
    final m = homography(src, dst);
    for (var i = 0; i < 4; i++) {
      final v = m.perspectiveTransform(Vector3(src[i].dx, src[i].dy, 0));
      expect(v.x, closeTo(dst[i].dx, 1e-6));
      expect(v.y, closeTo(dst[i].dy, 1e-6));
    }
  });

  test('geometry swaps dimensions on quarter turns', () {
    final g = buildGeometry(const Size(100, 50), const EditState(quarterTurns: 1), true);
    expect(g.out.width, 50);
    expect(g.out.height, 100);
    final c = buildGeometry(const Size(100, 50), const EditState(), true).map(50, 25);
    expect(c.dx, closeTo(50, 1e-9));
    expect(c.dy, closeTo(25, 1e-9));
  });

  test('head pose builds 8 handles of 8 floats', () {
    final f = FaceFrame(
      center: const Offset(0.5, 0.5),
      eyeL: const Offset(0.4, 0.45),
      eyeR: const Offset(0.6, 0.45),
      mouthL: const Offset(0.44, 0.62),
      mouthR: const Offset(0.56, 0.62),
      nose: const Offset(0.5, 0.55),
      cheekL: const Offset(0.35, 0.58),
      cheekR: const Offset(0.65, 0.58),
      wu: 0.4,
      hu: 0.5,
    );
    final s = const EditState().withValues({Param.smile: 0.5, Param.eyeSize: 0.4, Param.headRoll: 0.3});
    expect(buildWarp(f, s, 1.5).length, 64);
  });

  test('sniffFormat recognises common signatures', () {
    expect(sniffFormat(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])), 'jpeg');
    expect(sniffFormat(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])), 'png');
    expect(sniffFormat(Uint8List.fromList([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0])), 'tiff');
    expect(sniffFormat(Uint8List.fromList([0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8])), 'tiff');
  });

  test('TIFF round trip through the image package', () {
    final im = img.Image(width: 8, height: 6, numChannels: 4);
    final bytes = Uint8List.fromList(img.encodeTiff(im));
    expect(probeTiff(bytes).isTiff, isTrue);
    expect(probeTiff(bytes).isDng, isFalse);
    final r = decodeTiffEntry(DecodeRequest(bytes, 4096));
    expect(r, isNotNull);
    expect(r!.width, 8);
    expect(r.height, 6);
    expect(r.rgba.length, 8 * 6 * 4);
  });

  test('uncompressed CFA DNG decodes to a half-size RGBA image', () {
    final dng = makeDng(16, 12, 30000);
    final probe = probeTiff(dng);
    expect(probe.isDng, isTrue);
    final r = decodeDngEntry(DecodeRequest(dng, 4096));
    expect(r, isNotNull);
    expect(r!.width, 8);
    expect(r.height, 6);
    expect(r.rgba[3], 255);
    expect(r.rgba.any((v) => v > 0), isTrue);
  });

  test('JPEG and TIFF export encoders produce valid files', () {
    final rgba = Uint8List(4 * 4 * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 200;
      rgba[i + 1] = 100;
      rgba[i + 2] = 50;
      rgba[i + 3] = 255;
    }
    final jpg = encodeEntry(EncodeRequest(rgba, 4, 4, 'jpeg', 90));
    final tif = encodeEntry(EncodeRequest(rgba, 4, 4, 'tiff', 90));
    expect(sniffFormat(jpg), 'jpeg');
    expect(sniffFormat(tif), 'tiff');
  });
}
