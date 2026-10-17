import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import 'panels.dart' show SwatchRow;
import 'widgets.dart';

/// Picks a source patch for the healing tool: the nearby area whose
/// surroundings best match the area around the blemish.
Offset pickHealSource(Uint8List px, int w, int h, Offset pos, double r) {
  final rp = math.max(2.0, r * h);
  final cx = pos.dx * w, cy = pos.dy * h;
  List<double> ring(double x, double y) {
    var rr = 0.0, g = 0.0, b = 0.0;
    var n = 0;
    for (var k = 0; k < 16; k++) {
      final a = k * math.pi / 8;
      final sx = (x + math.cos(a) * rp * 1.3).round();
      final sy = (y + math.sin(a) * rp * 1.3).round();
      if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
      final i = (sy * w + sx) * 4;
      rr += px[i];
      g += px[i + 1];
      b += px[i + 2];
      n++;
    }
    return n == 0 ? [0.0, 0.0, 0.0] : [rr / n, g / n, b / n];
  }

  final t = ring(cx, cy);
  var best = const Offset(0.12, 0.0);
  var bestScore = double.infinity;
  for (var k = 0; k < 16; k++) {
    final a = k * math.pi / 8;
    for (final dist in const [2.4, 3.4]) {
      final sx = cx + math.cos(a) * rp * dist;
      final sy = cy + math.sin(a) * rp * dist;
      if (sx - rp < 0 || sy - rp < 0 || sx + rp >= w || sy + rp >= h) continue;
      final s = ring(sx, sy);
      final score = math.pow(s[0] - t[0], 2) + math.pow(s[1] - t[1], 2) + math.pow(s[2] - t[2], 2);
      if (score < bestScore) {
        bestScore = score.toDouble();
        best = Offset((sx - cx) / w, (sy - cy) / h);
      }
    }
  }
  return best;
}

class PointsPainter extends CustomPainter {
  PointsPainter(this.points, this.selected, this.rect);
  final List<SelPoint> points;
  final int selected;
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final c = Offset(rect.left + p.pos.dx * rect.width, rect.top + p.pos.dy * rect.height);
      final sel = i == selected;
      canvas.drawCircle(
        c,
        p.radius * rect.height,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 2 : 1
          ..color = sel ? Colors.tealAccent : Colors.white54,
      );
      canvas.drawCircle(c, 11, Paint()..color = sel ? Colors.tealAccent : Colors.white);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(PointsPainter old) => true;
}

class CenterPainter extends CustomPainter {
  CenterPainter(this.pos, this.rect);
  final Offset pos;
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(rect.left + pos.dx * rect.width, rect.top + pos.dy * rect.height);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawCircle(c, 14, p);
    canvas.drawLine(c - const Offset(22, 0), c + const Offset(22, 0), p);
    canvas.drawLine(c - const Offset(0, 22), c + const Offset(0, 22), p);
  }

  @override
  bool shouldRepaint(CenterPainter old) => old.pos != pos || old.rect != rect;
}

class SelectivePanel extends StatelessWidget {
  const SelectivePanel({
    super.key,
    required this.points,
    required this.selected,
    required this.onSelect,
    required this.onChange,
    required this.onDelete,
  });
  final List<SelPoint> points;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<SelPoint> onChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty || selected < 0 || selected >= points.length) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          points.isEmpty
              ? 'Tap the photo to place a control point (up to 4).'
              : 'Tap a point to select it, or tap the photo to add one.',
          textAlign: TextAlign.center,
        ),
      );
    }
    final p = points[selected];
    Widget s(String label, double v, double min, double max, SelPoint Function(double) f) => LabeledSlider(
          label: label,
          value: v,
          min: min,
          max: max,
          display: '${(v * 100).round()}',
          onChanged: (x) => onChange(f(x)),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: ChipRow(
            labels: [for (var i = 0; i < points.length; i++) 'Point ${i + 1}'],
            selected: selected,
            onSelect: onSelect,
          ),
        ),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      ]),
      s('Brightness', p.brightness, -1, 1, (x) => p.copyWith(brightness: x)),
      s('Contrast', p.contrast, -1, 1, (x) => p.copyWith(contrast: x)),
      s('Saturation', p.saturation, -1, 1, (x) => p.copyWith(saturation: x)),
      s('Warmth', p.warmth, -1, 1, (x) => p.copyWith(warmth: x)),
      s('Size', p.radius, 0.05, 0.5, (x) => p.copyWith(radius: x)),
    ]);
  }
}

class BrushPanel extends StatelessWidget {
  const BrushPanel({
    super.key,
    required this.mode,
    required this.onMode,
    required this.size,
    required this.onSize,
    required this.amount,
    required this.onAmount,
    required this.erase,
    required this.onErase,
    required this.onUndo,
    required this.onClear,
  });
  final int mode;
  final ValueChanged<int> onMode;
  final double size;
  final ValueChanged<double> onSize;
  final double amount;
  final ValueChanged<double> onAmount;
  final bool erase;
  final ValueChanged<bool> onErase;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ChipRow(labels: brushModes, selected: mode, onSelect: onMode),
      LabeledSlider(
        label: 'Brush size',
        value: size,
        min: 0.01,
        max: 0.2,
        display: '${(size * 100).round()}',
        onChanged: onSize,
      ),
      LabeledSlider(
        label: 'Strength',
        value: amount,
        min: 0.05,
        max: 1,
        display: '${(amount * 100).round()}',
        onChanged: onAmount,
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        FilterChip(label: const Text('Erase'), selected: erase, onSelected: onErase),
        TextButton.icon(onPressed: onUndo, icon: const Icon(Icons.undo), label: const Text('Undo stroke')),
        TextButton.icon(onPressed: onClear, icon: const Icon(Icons.layers_clear), label: const Text('Clear')),
      ]),
    ]);
  }
}

class HealPanel extends StatelessWidget {
  const HealPanel({
    super.key,
    required this.radius,
    required this.onRadius,
    required this.count,
    required this.onUndo,
    required this.onClear,
  });
  final double radius;
  final ValueChanged<double> onRadius;
  final int count;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Tap a blemish to heal it from a nearby patch.', style: TextStyle(fontSize: 13)),
      ),
      LabeledSlider(
        label: 'Spot size',
        value: radius,
        min: 0.01,
        max: 0.12,
        display: '${(radius * 100).round()}',
        onChanged: onRadius,
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        TextButton.icon(
          onPressed: count > 0 ? onUndo : null,
          icon: const Icon(Icons.undo),
          label: Text('Undo spot ($count)'),
        ),
        TextButton.icon(onPressed: count > 0 ? onClear : null, icon: const Icon(Icons.layers_clear), label: const Text('Clear')),
      ]),
    ]);
  }
}

class TextPanel extends StatelessWidget {
  const TextPanel({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onChange,
    required this.onDelete,
  });
  final List<TextItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final ValueChanged<TextItem> onChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final has = selected >= 0 && selected < items.length;
    final t = has ? items[selected] : null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Add text, then drag it on the photo.'),
                )
              : ChipRow(
                  labels: [for (var i = 0; i < items.length; i++) items[i].text.isEmpty ? 'Text ${i + 1}' : items[i].text],
                  selected: selected,
                  onSelect: onSelect,
                ),
        ),
        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: onAdd),
        if (has) IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
        if (has) IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      ]),
      if (t != null) ...[
        ChipRow(labels: fontNames, selected: t.font, onSelect: (i) => onChange(t.copyWith(font: i)), height: 44),
        SwatchRow(selected: t.color, onSelect: (c) => onChange(t.copyWith(color: c))),
        LabeledSlider(
          label: 'Size',
          value: t.size,
          min: 0.03,
          max: 0.3,
          display: '${(t.size * 100).round()}',
          onChanged: (v) => onChange(t.copyWith(size: v)),
        ),
        LabeledSlider(
          label: 'Rotation',
          value: t.rotation,
          min: -180,
          max: 180,
          display: '${t.rotation.round()}°',
          onChanged: (v) => onChange(t.copyWith(rotation: v)),
        ),
        LabeledSlider(
          label: 'Opacity',
          value: t.opacity,
          min: 0.1,
          max: 1,
          display: '${(t.opacity * 100).round()}',
          onChanged: (v) => onChange(t.copyWith(opacity: v)),
        ),
      ],
    ]);
  }
}
