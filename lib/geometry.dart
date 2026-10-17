import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import 'edit_state.dart';
import 'params.dart';

class Geo {
  const Geo(this.m, this.out);

  /// Maps source pixels (of the possibly expanded source) to output pixels.
  final Matrix4 m;
  final Size out;

  Offset map(double x, double y) {
    final v = m.perspectiveTransform(Vector3(x, y, 0));
    return Offset(v.x, v.y);
  }
}

/// Solves the 3x3 homography taking [s] corners to [d] corners.
Matrix4 homography(List<Offset> s, List<Offset> d) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0.0));
  for (var i = 0; i < 4; i++) {
    final x = s[i].dx, y = s[i].dy, u = d[i].dx, v = d[i].dy;
    a[2 * i] = [x, y, 1.0, 0.0, 0.0, 0.0, -x * u, -y * u, u];
    a[2 * i + 1] = [0.0, 0.0, 0.0, x, y, 1.0, -x * v, -y * v, v];
  }
  for (var c = 0; c < 8; c++) {
    var p = c;
    for (var r = c + 1; r < 8; r++) {
      if (a[r][c].abs() > a[p][c].abs()) p = r;
    }
    final t = a[c];
    a[c] = a[p];
    a[p] = t;
    final div = a[c][c];
    for (var k = c; k < 9; k++) {
      a[c][k] /= div;
    }
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = a[r][c];
      if (f == 0) continue;
      for (var k = c; k < 9; k++) {
        a[r][k] -= f * a[c][k];
      }
    }
  }
  final h = [for (var i = 0; i < 8; i++) a[i][8]];
  return Matrix4(
    h[0], h[3], 0, h[6],
    h[1], h[4], 0, h[7],
    0, 0, 1, 0,
    h[2], h[5], 0, 1,
  );
}

Matrix4 _perspective(double fw, double fh, double pv, double ph) {
  final hw = fw / 2, hh = fh / 2;
  final src = [Offset(-hw, -hh), Offset(hw, -hh), Offset(hw, hh), Offset(-hw, hh)];
  var tl = src[0], tr = src[1], br = src[2], bl = src[3];
  final kx = pv.abs() * 0.25 * fw;
  if (pv >= 0) {
    tl = tl.translate(-kx, 0);
    tr = tr.translate(kx, 0);
  } else {
    bl = bl.translate(-kx, 0);
    br = br.translate(kx, 0);
  }
  final ky = ph.abs() * 0.25 * fh;
  if (ph >= 0) {
    tl = tl.translate(0, -ky);
    bl = bl.translate(0, ky);
  } else {
    tr = tr.translate(0, -ky);
    br = br.translate(0, ky);
  }
  return homography(src, [tl, tr, br, bl]);
}

/// Builds the source->output transform for rotate/flip/straighten/perspective/crop.
Geo buildGeometry(Size src, EditState s, bool applyCrop) {
  final sw = src.width, sh = src.height;
  final turned = s.quarterTurns.isOdd;
  final fw = turned ? sh : sw;
  final fh = turned ? sw : sh;
  final crop = applyCrop ? s.crop : EditState.fullCrop;
  final ow = math.max(1, (fw * crop.width).round());
  final oh = math.max(1, (fh * crop.height).round());

  final theta = s[Param.straighten] * math.pi / 180.0;
  final fill = math.cos(theta.abs()) + math.sin(theta.abs()) * math.max(fw / fh, fh / fw);
  final pv = s[Param.perspV];
  final ph = s[Param.perspH];

  final m = Matrix4.identity();
  m.translate(-crop.left * fw, -crop.top * fh);
  m.translate(fw / 2, fh / 2);
  if (pv != 0 || ph != 0) m.multiply(_perspective(fw, fh, pv, ph));
  m.rotateZ(theta);
  m.scale(fill, fill);
  if (s.flipH) m.scale(-1.0, 1.0);
  m.rotateZ(s.quarterTurns * math.pi / 2);
  m.translate(-sw / 2, -sh / 2);
  return Geo(m, Size(ow.toDouble(), oh.toDouble()));
}
