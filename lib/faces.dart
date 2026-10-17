import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'edit_state.dart';
import 'params.dart';

/// A detected face; all coordinates normalised to the source image.
class FaceData {
  const FaceData({
    required this.box,
    this.leftEye,
    this.rightEye,
    this.mouthLeft,
    this.mouthRight,
    this.mouthBottom,
    this.nose,
    this.leftCheek,
    this.rightCheek,
  });
  final Rect box;
  final Offset? leftEye, rightEye, mouthLeft, mouthRight, mouthBottom, nose, leftCheek, rightCheek;
}

/// A face mapped into the current frame's UV space.
class FaceFrame {
  FaceFrame({
    required this.center,
    required this.eyeL,
    required this.eyeR,
    required this.mouthL,
    required this.mouthR,
    required this.nose,
    required this.cheekL,
    required this.cheekR,
    required this.wu,
    required this.hu,
  });

  final Offset center, eyeL, eyeR, mouthL, mouthR, nose, cheekL, cheekR;

  /// Face width / height as fractions of the frame.
  final double wu, hu;

  factory FaceFrame.from(FaceData f, Offset Function(Offset) map) {
    final b = f.box;
    Offset at(double fx, double fy) => Offset(b.left + b.width * fx, b.top + b.height * fy);
    final corners = [map(b.topLeft), map(b.topRight), map(b.bottomLeft), map(b.bottomRight)];
    final minX = corners.map((o) => o.dx).reduce(math.min);
    final maxX = corners.map((o) => o.dx).reduce(math.max);
    final minY = corners.map((o) => o.dy).reduce(math.min);
    final maxY = corners.map((o) => o.dy).reduce(math.max);
    return FaceFrame(
      center: Offset((minX + maxX) / 2, (minY + maxY) / 2),
      eyeL: map(f.leftEye ?? at(0.3, 0.38)),
      eyeR: map(f.rightEye ?? at(0.7, 0.38)),
      mouthL: map(f.mouthLeft ?? at(0.38, 0.78)),
      mouthR: map(f.mouthRight ?? at(0.62, 0.78)),
      nose: map(f.nose ?? at(0.5, 0.6)),
      cheekL: map(f.leftCheek ?? at(0.12, 0.68)),
      cheekR: map(f.rightCheek ?? at(0.88, 0.68)),
      wu: maxX - minX,
      hu: maxY - minY,
    );
  }

  /// Distance between the eyes in height units.
  double eyeDist(double aspect) => (eyeL - eyeR).dx.abs() * aspect;
}

List<double> _h(Offset c, double r, double type, double dx, double dy, double st, double ang) =>
    [c.dx, c.dy, r, type, dx, dy, st, ang];

const _off = <double>[0, 0, 0, 0, 0, 0, 0, 0];

/// 8 warp handles x 8 floats, for the head pose tool.
List<double> buildWarp(FaceFrame f, EditState s, double aspect) {
  double e(Param p) => s.effective(p);
  final faceW = f.wu * aspect;
  final base = math.max(faceW, f.hu);
  final out = <double>[];

  final roll = e(Param.headRoll);
  out.addAll(roll == 0 ? _off : _h(f.center, base * 0.95, 2, 0, 0, 0, roll * 0.35));

  final yaw = e(Param.headYaw);
  final pitch = e(Param.headPitch);
  out.addAll(yaw == 0 && pitch == 0
      ? _off
      : _h(f.nose, base * 0.6, 0, yaw * 0.05 * f.wu, pitch * 0.05 * f.hu, 0, 0));

  final smile = e(Param.smile);
  final mouthW = (f.mouthL - f.mouthR).dx.abs() * aspect;
  final mr = math.max(mouthW * 0.45, 0.01);
  final leftFirst = f.mouthL.dx < f.mouthR.dx;
  if (smile == 0) {
    out.addAll(_off);
    out.addAll(_off);
  } else {
    out.addAll(_h(f.mouthL, mr, 0, (leftFirst ? -1 : 1) * smile * 0.015 * f.wu, -smile * 0.035 * f.hu, 0, 0));
    out.addAll(_h(f.mouthR, mr, 0, (leftFirst ? 1 : -1) * smile * 0.015 * f.wu, -smile * 0.035 * f.hu, 0, 0));
  }

  final eye = e(Param.eyeSize);
  final er = math.max(f.eyeDist(aspect) * 0.35, 0.01);
  if (eye == 0) {
    out.addAll(_off);
    out.addAll(_off);
  } else {
    out.addAll(_h(f.eyeL, er, 1, 0, 0, eye * 0.45, 0));
    out.addAll(_h(f.eyeR, er, 1, 0, 0, eye * 0.45, 0));
  }

  final slim = e(Param.faceSlim);
  final cr = math.max(faceW * 0.4, 0.01);
  if (slim == 0) {
    out.addAll(_off);
    out.addAll(_off);
  } else {
    out.addAll(_h(f.cheekL, cr, 0, (f.cheekL.dx < f.center.dx ? 1 : -1) * slim * 0.04 * f.wu, 0, 0, 0));
    out.addAll(_h(f.cheekR, cr, 0, (f.cheekR.dx < f.center.dx ? 1 : -1) * slim * 0.04 * f.wu, 0, 0, 0));
  }
  return out;
}
