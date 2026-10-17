import 'dart:math' as math;

import 'package:flutter/material.dart';

double _c(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

Rect fitRect(Size box, Size img, {double padding = 0}) {
  final aw = box.width - padding * 2;
  final ah = box.height - padding * 2;
  final s = math.min(aw / img.width, ah / img.height);
  final w = img.width * s;
  final h = img.height * s;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

/// Largest centred normalised rect with pixel aspect [aspectPx] (w/h) in [frame].
Rect fitAspect(double aspectPx, Size frame) {
  final an = aspectPx * frame.height / frame.width;
  final w = an >= 1 ? 1.0 : an;
  final h = an >= 1 ? 1 / an : 1.0;
  return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
}

Rect _resize(Rect r, int corner, Offset d, double? an) {
  const minSize = 0.08;
  final isLeft = corner == 0 || corner == 2;
  final isTop = corner == 0 || corner == 1;
  var l = r.left, t = r.top, rt = r.right, b = r.bottom;
  if (isLeft) {
    l = _c(l + d.dx, 0, rt - minSize);
  } else {
    rt = _c(rt + d.dx, l + minSize, 1);
  }
  if (isTop) {
    t = _c(t + d.dy, 0, b - minSize);
  } else {
    b = _c(b + d.dy, t + minSize, 1);
  }
  if (an != null) {
    var w = rt - l;
    var h = w / an;
    final maxH = isTop ? b : 1 - t;
    if (h > maxH) {
      h = maxH;
      w = h * an;
    }
    if (isLeft) {
      l = rt - w;
    } else {
      rt = l + w;
    }
    if (isTop) {
      t = b - h;
    } else {
      b = t + h;
    }
  }
  return Rect.fromLTRB(l, t, rt, b);
}

class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.imageRect,
    required this.frame,
    required this.crop,
    required this.aspect,
    required this.onChanged,
  });

  final Rect imageRect;
  final Size frame;
  final Rect crop;

  /// Locked pixel aspect (w/h), or null for free.
  final double? aspect;
  final ValueChanged<Rect> onChanged;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  late Rect _crop = widget.crop;
  int _handle = -1;

  @override
  void didUpdateWidget(CropOverlay old) {
    super.didUpdateWidget(old);
    if (old.crop != widget.crop) _crop = widget.crop;
  }

  void _start(Offset p, Rect r) {
    final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
    _handle = -1;
    var best = 44.0;
    for (var i = 0; i < 4; i++) {
      final dist = (corners[i] - p).distance;
      if (dist < best) {
        best = dist;
        _handle = i;
      }
    }
    if (_handle == -1 && r.contains(p)) _handle = 4;
  }

  void _update(DragUpdateDetails d) {
    if (_handle < 0) return;
    final ir = widget.imageRect;
    final n = Offset(d.delta.dx / ir.width, d.delta.dy / ir.height);
    Rect next;
    if (_handle == 4) {
      final dx = _c(n.dx, -_crop.left, 1 - _crop.right);
      final dy = _c(n.dy, -_crop.top, 1 - _crop.bottom);
      next = _crop.shift(Offset(dx, dy));
    } else {
      final a = widget.aspect;
      final an = a == null ? null : a * widget.frame.height / widget.frame.width;
      next = _resize(_crop, _handle, n, an);
    }
    setState(() => _crop = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ir = widget.imageRect;
    final r = Rect.fromLTRB(
      ir.left + _crop.left * ir.width,
      ir.top + _crop.top * ir.height,
      ir.left + _crop.right * ir.width,
      ir.top + _crop.bottom * ir.height,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _start(d.localPosition, r),
      onPanUpdate: _update,
      child: CustomPaint(painter: _CropPainter(r, ir), size: Size.infinite),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect, this.bounds);
  final Rect rect;
  final Rect bounds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addRect(rect),
      Paint()..color = const Color(0x99000000),
    );
    final grid = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
    final hp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square
      ..color = Colors.white;
    const len = 20.0;
    void corner(Offset o, double sx, double sy) {
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy + sy * len)
          ..lineTo(o.dx, o.dy)
          ..lineTo(o.dx + sx * len, o.dy),
        hp,
      );
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect || old.bounds != bounds;
}
