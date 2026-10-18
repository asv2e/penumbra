import 'dart:ui' show Offset, Rect;

import 'edit_state.dart';
import 'lut.dart';
import 'models.dart';
import 'params.dart';
import 'presets.dart';

/// JSON form of an [EditState], used to save projects. Unknown params and
/// out-of-range preset indexes are skipped on load so old projects keep opening
/// after the tool list changes.
const int editFormatVersion = 1;

double _r(double v, [int digits = 5]) => double.parse(v.toStringAsFixed(digits));

List<double> _o(Offset o, [int digits = 5]) => [_r(o.dx, digits), _r(o.dy, digits)];

double _d(Object? v, double def) => v is num && v.isFinite ? v.toDouble() : def;
int _i(Object? v, int def) => v is num ? v.toInt() : def;
bool _b(Object? v, bool def) => v is bool ? v : def;

Offset _off(Object? v, Offset def) {
  if (v is List && v.length >= 2 && v[0] is num && v[1] is num) {
    return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
  }
  return def;
}

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

Map<String, dynamic> editToJson(EditState s) => {
      'v': editFormatVersion,
      'values': {
        for (final e in s.values.entries)
          if (e.value != 0) e.key.id: _r(e.value),
      },
      'presets': {
        for (final e in s.presets.entries) e.key: [e.value.index, _r(e.value.strength)],
      },
      'mono': s.mono,
      'curves': [
        for (var i = 0; i < 4; i++) [for (final o in s.curves.channel(i)) _o(o)],
      ],
      'crop': [_r(s.crop.left), _r(s.crop.top), _r(s.crop.right), _r(s.crop.bottom)],
      'turns': s.quarterTurns,
      'flipH': s.flipH,
      'expandFill': s.expandFill,
      'blurCenter': _o(s.blurCenter),
      'blurShape': s.blurShape,
      'vigCenter': _o(s.vigCenter),
      'points': [
        for (final p in s.points)
          {
            'pos': _o(p.pos),
            'radius': _r(p.radius),
            'brightness': _r(p.brightness),
            'contrast': _r(p.contrast),
            'saturation': _r(p.saturation),
            'warmth': _r(p.warmth),
          },
      ],
      'brush': [
        for (final l in s.brush)
          {
            'mode': l.mode,
            'amount': _r(l.amount),
            'strokes': [
              for (final st in l.strokes)
                {
                  // Flat x,y,x,y list keeps long strokes compact.
                  'pts': [for (final p in st.pts) ..._o(p, 4)],
                  'size': _r(st.size),
                  'erase': st.erase,
                },
            ],
          },
      ],
      'heal': [
        for (final h in s.heal) {'pos': _o(h.pos), 'radius': _r(h.radius), 'src': _o(h.src)},
      ],
      'texts': [
        for (final t in s.texts)
          {
            'text': t.text,
            'pos': _o(t.pos),
            'size': _r(t.size),
            'rotation': _r(t.rotation),
            'opacity': _r(t.opacity),
            'font': t.font,
            'color': t.color,
            'shadow': t.shadow,
          },
      ],
      'frameStyle': s.frameStyle,
      'frameColor': s.frameColor,
      'deImage': s.deImage,
      'deBlend': s.deBlend,
      'deOffset': _o(s.deOffset),
    };

EditState editFromJson(Map<String, dynamic> j) {
  final values = <Param, double>{};
  final rawValues = j['values'];
  if (rawValues is Map) {
    rawValues.forEach((k, v) {
      final p = Param.byId[k];
      if (p != null && v is num) values[p] = clampD(v.toDouble(), p.min, p.max);
    });
  }

  final presets = <String, PresetSel>{};
  final rawPresets = j['presets'];
  if (rawPresets is Map) {
    rawPresets.forEach((k, v) {
      final bank = presetBank[k];
      if (bank != null && v is List && v.length >= 2 && v[0] is num && v[1] is num) {
        final idx = (v[0] as num).toInt();
        if (idx > 0 && idx < bank.length) {
          presets[k as String] = PresetSel(idx, clampD((v[1] as num).toDouble(), 0, 1));
        }
      }
    });
  }

  var curves = const CurveSet();
  final rawCurves = j['curves'];
  if (rawCurves is List && rawCurves.length == 4) {
    final ch = <List<Offset>>[];
    for (final c in rawCurves) {
      final pts = c is List ? [for (final o in c) _off(o, Offset.zero)] : <Offset>[];
      ch.add(pts.length >= 2 ? pts : CurveSet.identity);
    }
    curves = CurveSet(master: ch[0], red: ch[1], green: ch[2], blue: ch[3]);
  }

  var crop = EditState.fullCrop;
  final rc = j['crop'];
  if (rc is List && rc.length == 4 && rc.every((e) => e is num)) {
    final l = clampD((rc[0] as num).toDouble(), 0, 1);
    final t = clampD((rc[1] as num).toDouble(), 0, 1);
    final r = clampD((rc[2] as num).toDouble(), 0, 1);
    final b = clampD((rc[3] as num).toDouble(), 0, 1);
    if (r > l && b > t) crop = Rect.fromLTRB(l, t, r, b);
  }

  final points = [
    for (final m in _maps(j['points']))
      SelPoint(
        pos: _off(m['pos'], const Offset(0.5, 0.5)),
        radius: _d(m['radius'], 0.18),
        brightness: _d(m['brightness'], 0),
        contrast: _d(m['contrast'], 0),
        saturation: _d(m['saturation'], 0),
        warmth: _d(m['warmth'], 0),
      ),
  ];

  final brush = [
    for (final m in _maps(j['brush']))
      BrushLayer(
        _i(m['mode'], 0).clamp(0, brushModes.length - 1).toInt(),
        _d(m['amount'], 0.6),
        [
          for (final st in _maps(m['strokes']))
            Stroke(
              () {
                final flat = st['pts'];
                if (flat is! List) return <Offset>[];
                return [
                  for (var i = 0; i + 1 < flat.length; i += 2)
                    Offset(_d(flat[i], 0), _d(flat[i + 1], 0)),
                ];
              }(),
              _d(st['size'], 0.06),
              _b(st['erase'], false),
            ),
        ],
      ),
  ];

  final heal = [
    for (final m in _maps(j['heal']))
      HealSpot(_off(m['pos'], Offset.zero), _d(m['radius'], 0.04), _off(m['src'], Offset.zero)),
  ];

  final texts = [
    for (final m in _maps(j['texts']))
      TextItem(
        text: m['text'] is String ? m['text'] as String : '',
        pos: _off(m['pos'], const Offset(0.5, 0.5)),
        size: _d(m['size'], 0.08),
        rotation: _d(m['rotation'], 0),
        opacity: _d(m['opacity'], 1),
        font: _i(m['font'], 0).clamp(0, fontNames.length - 1).toInt(),
        color: _i(m['color'], 0xFFFFFFFF),
        shadow: _b(m['shadow'], true),
      ),
  ];

  return EditState(
    values: values,
    presets: presets,
    mono: _i(j['mono'], -1),
    curves: curves,
    crop: crop,
    quarterTurns: _i(j['turns'], 0) % 4,
    flipH: _b(j['flipH'], false),
    expandFill: _i(j['expandFill'], 0),
    blurCenter: _off(j['blurCenter'], const Offset(0.5, 0.5)),
    blurShape: _i(j['blurShape'], 0),
    vigCenter: _off(j['vigCenter'], const Offset(0.5, 0.5)),
    points: points,
    brush: brush,
    heal: heal,
    texts: texts,
    frameStyle: _i(j['frameStyle'], 0),
    frameColor: _i(j['frameColor'], 0xFFFFFFFF),
    deImage: _i(j['deImage'], -1),
    deBlend: _i(j['deBlend'], 0),
    deOffset: _off(j['deOffset'], Offset.zero),
  );
}
