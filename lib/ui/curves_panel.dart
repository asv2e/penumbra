import 'package:flutter/material.dart';

import '../edit_state.dart';
import '../lut.dart';
import 'widgets.dart';

class CurvesPanel extends StatelessWidget {
  const CurvesPanel({
    super.key,
    required this.curves,
    required this.channel,
    required this.onChannel,
    required this.onChanged,
  });
  final CurveSet curves;
  final int channel;
  final ValueChanged<int> onChannel;
  final ValueChanged<CurveSet> onChanged;

  static const _colors = [Colors.white, Colors.redAccent, Colors.greenAccent, Colors.lightBlueAccent];
  static const _presets = <String, List<Offset>>{
    'Contrast': [Offset(0, 0), Offset(0.25, 0.18), Offset(0.75, 0.82), Offset(1, 1)],
    'Lighten': [Offset(0, 0), Offset(0.5, 0.62), Offset(1, 1)],
    'Darken': [Offset(0, 0), Offset(0.5, 0.4), Offset(1, 1)],
    'Fade': [Offset(0, 0.08), Offset(1, 0.92)],
  };

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ChipRow(labels: const ['RGB', 'Red', 'Green', 'Blue'], selected: channel, onSelect: onChannel),
      SizedBox(
        height: 210,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: CurveEditor(
              points: curves.channel(channel),
              color: _colors[channel],
              onChanged: (pts) => onChanged(curves.withChannel(channel, pts)),
            ),
          ),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: const Text('Reset'),
                onPressed: () => onChanged(curves.withChannel(channel, CurveSet.identity)),
              ),
            ),
            for (final e in _presets.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(label: Text(e.key), onPressed: () => onChanged(curves.withChannel(0, e.value))),
              ),
          ],
        ),
      ),
    ]);
  }
}

class CurveEditor extends StatefulWidget {
  const CurveEditor({super.key, required this.points, required this.color, required this.onChanged});
  final List<Offset> points;
  final Color color;
  final ValueChanged<List<Offset>> onChanged;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  int _drag = -1;
  Offset _tapAt = Offset.zero;

  Offset _norm(Offset p, Size s) => Offset(clampD(p.dx / s.width, 0, 1), clampD(1 - p.dy / s.height, 0, 1));

  int _nearest(Offset local, Size s, {bool interiorOnly = false}) {
    final pts = widget.points;
    var best = -1;
    var bestD = 24.0;
    for (var i = 0; i < pts.length; i++) {
      if (interiorOnly && (i == 0 || i == pts.length - 1)) continue;
      final px = Offset(pts[i].dx * s.width, (1 - pts[i].dy) * s.height);
      final d = (px - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _start(Offset local, Size s) {
    _drag = _nearest(local, s);
    if (_drag >= 0) return;
    final pts = List<Offset>.of(widget.points);
    if (pts.length >= 12) return;
    final n = _norm(local, s);
    final nx = clampD(n.dx, 0.03, 0.97);
    var at = pts.indexWhere((o) => o.dx > nx);
    if (at < 1) at = pts.length - 1;
    pts.insert(at, Offset(nx, n.dy));
    _drag = at;
    widget.onChanged(pts);
  }

  void _move(Offset local, Size s) {
    if (_drag < 0) return;
    final pts = List<Offset>.of(widget.points);
    if (_drag >= pts.length) return;
    final n = _norm(local, s);
    var x = pts[_drag].dx;
    if (_drag != 0 && _drag != pts.length - 1) {
      x = clampD(n.dx, pts[_drag - 1].dx + 0.02, pts[_drag + 1].dx - 0.02);
    }
    pts[_drag] = Offset(x, n.dy);
    widget.onChanged(pts);
  }

  void _remove(Size s) {
    final i = _nearest(_tapAt, s, interiorOnly: true);
    if (i < 0) return;
    widget.onChanged(List<Offset>.of(widget.points)..removeAt(i));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final s = box.biggest;
      return GestureDetector(
        onPanStart: (d) => _start(d.localPosition, s),
        onPanUpdate: (d) => _move(d.localPosition, s),
        onPanEnd: (_) => _drag = -1,
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: () => _remove(s),
        child: CustomPaint(size: s, painter: _CurvePainter(widget.points, widget.color)),
      );
    });
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.pts, this.color);
  final List<Offset> pts;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF222222));
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(s.width * i / 4, 0), Offset(s.width * i / 4, s.height), grid);
      canvas.drawLine(Offset(0, s.height * i / 4), Offset(s.width, s.height * i / 4), grid);
    }
    canvas.drawLine(Offset(0, s.height), Offset(s.width, 0), grid);
    final f = curveFn(pts);
    final path = Path();
    for (var i = 0; i <= 64; i++) {
      final x = i / 64;
      final y = clampD(f(x), 0, 1);
      final p = Offset(x * s.width, (1 - y) * s.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    for (final p in pts) {
      final c = Offset(p.dx * s.width, (1 - p.dy) * s.height);
      canvas.drawCircle(c, 6, Paint()..color = Colors.black);
      canvas.drawCircle(c, 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
