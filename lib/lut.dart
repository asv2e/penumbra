import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show immutable;

@immutable
class CurveSet {
  const CurveSet({
    this.master = identity,
    this.red = identity,
    this.green = identity,
    this.blue = identity,
  });

  static const List<Offset> identity = [Offset(0, 0), Offset(1, 1)];

  final List<Offset> master;
  final List<Offset> red;
  final List<Offset> green;
  final List<Offset> blue;

  List<Offset> channel(int i) => [master, red, green, blue][i];

  CurveSet withChannel(int i, List<Offset> pts) => CurveSet(
        master: i == 0 ? pts : master,
        red: i == 1 ? pts : red,
        green: i == 2 ? pts : green,
        blue: i == 3 ? pts : blue,
      );

  static bool _isId(List<Offset> p) => p.length == 2 && p[0] == identity[0] && p[1] == identity[1];

  bool get isIdentity => _isId(master) && _isId(red) && _isId(green) && _isId(blue);

  String get key {
    String k(List<Offset> p) => p.map((o) => '${o.dx.toStringAsFixed(3)},${o.dy.toStringAsFixed(3)}').join(';');
    return '${k(master)}|${k(red)}|${k(green)}|${k(blue)}';
  }
}

/// Monotone cubic (Fritsch-Carlson) interpolation through [p] (sorted by x).
double Function(double) curveFn(List<Offset> p) {
  final n = p.length;
  final x = [for (final o in p) o.dx];
  final y = [for (final o in p) o.dy];
  final d = <double>[
    for (var i = 0; i < n - 1; i++) (y[i + 1] - y[i]) / math.max(1e-6, x[i + 1] - x[i]),
  ];
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i];
    final b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final t = 3 / math.sqrt(s);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  return (double t) {
    if (t <= x.first) return y.first;
    if (t >= x.last) return y.last;
    var i = 0;
    while (i < n - 2 && t > x[i + 1]) {
      i++;
    }
    final h = x[i + 1] - x[i];
    final u = (t - x[i]) / h;
    final u2 = u * u;
    final u3 = u2 * u;
    return (2 * u3 - 3 * u2 + 1) * y[i] +
        (u3 - 2 * u2 + u) * h * m[i] +
        (-2 * u3 + 3 * u2) * y[i + 1] +
        (u3 - u2) * h * m[i + 1];
  };
}

double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// 256x1 RGBA lookup table: each channel holds that channel's composed curve.
Uint8List buildLutBytes(CurveSet c) {
  final fm = curveFn(c.master);
  final fr = curveFn(c.red);
  final fg = curveFn(c.green);
  final fb = curveFn(c.blue);
  final out = Uint8List(256 * 4);
  for (var i = 0; i < 256; i++) {
    final t = i / 255.0;
    out[i * 4] = (_c01(fm(_c01(fr(t)))) * 255).round();
    out[i * 4 + 1] = (_c01(fm(_c01(fg(t)))) * 255).round();
    out[i * 4 + 2] = (_c01(fm(_c01(fb(t)))) * 255).round();
    out[i * 4 + 3] = 255;
  }
  return out;
}

Future<ui.Image> _fromRgba(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

class LutCache {
  LutCache._(this.identityLut);
  final ui.Image identityLut;
  final Map<String, ui.Image> _cache = {};
  final Set<String> _pending = {};

  /// Called when an asynchronously built LUT becomes available.
  void Function()? onReady;

  static Future<LutCache> create() async {
    final bytes = buildLutBytes(const CurveSet());
    return LutCache._(await _fromRgba(bytes, 256, 1));
  }

  /// Returns the LUT for [c] or null while it is still being built.
  ui.Image? get(CurveSet c) {
    final k = c.key;
    final hit = _cache[k];
    if (hit != null) return hit;
    if (_pending.add(k)) {
      _fromRgba(buildLutBytes(c), 256, 1).then((img) {
        _cache[k] = img;
        _pending.remove(k);
        onReady?.call();
      });
    }
    return null;
  }

  Future<ui.Image> ensure(CurveSet c) async {
    if (c.isIdentity) return identityLut;
    final k = c.key;
    return _cache[k] ??= await _fromRgba(buildLutBytes(c), 256, 1);
  }
}
