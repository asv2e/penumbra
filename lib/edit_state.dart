import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart' show immutable;

import 'lut.dart';
import 'models.dart';
import 'params.dart';
import 'presets.dart';

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

@immutable
class EditState {
  const EditState({
    this.values = const <Param, double>{},
    this.presets = const <String, PresetSel>{},
    this.mono = -1,
    this.curves = const CurveSet(),
    this.crop = fullCrop,
    this.quarterTurns = 0,
    this.flipH = false,
    this.expandFill = 0,
    this.blurCenter = const Offset(0.5, 0.5),
    this.blurShape = 0,
    this.vigCenter = const Offset(0.5, 0.5),
    this.points = const <SelPoint>[],
    this.brush = const <BrushLayer>[],
    this.heal = const <HealSpot>[],
    this.texts = const <TextItem>[],
    this.frameStyle = 0,
    this.frameColor = 0xFFFFFFFF,
    this.deImage = -1,
    this.deBlend = 0,
    this.deOffset = Offset.zero,
  });

  static const Rect fullCrop = Rect.fromLTRB(0, 0, 1, 1);

  final Map<Param, double> values;
  final Map<String, PresetSel> presets;

  /// Index into the mono filter list from the B&W tool, -1 = colour.
  final int mono;
  final CurveSet curves;

  /// Crop in the rotated frame, normalised.
  final Rect crop;
  final int quarterTurns;
  final bool flipH;
  final int expandFill;
  final Offset blurCenter;
  final int blurShape;
  final Offset vigCenter;
  final List<SelPoint> points;
  final List<BrushLayer> brush;
  final List<HealSpot> heal;
  final List<TextItem> texts;
  final int frameStyle;
  final int frameColor;
  final int deImage;
  final int deBlend;
  final Offset deOffset;

  double operator [](Param p) => values[p] ?? 0.0;

  EditState withValue(Param p, double v) => copyWith(values: {...values, p: v});

  EditState withValues(Map<Param, double> m) => copyWith(values: {...values, ...m});

  /// User value plus every active preset's delta, clamped to the param range.
  double effective(Param p) {
    var v = this[p];
    for (final e in presets.entries) {
      final sel = e.value;
      if (sel.index > 0) {
        v += (presetBank[e.key]![sel.index].deltas[p] ?? 0.0) * sel.strength;
      }
    }
    return clampD(v, p.min, p.max);
  }

  int get effectiveMono {
    for (final e in presets.entries) {
      if (e.value.index > 0) {
        final m = presetBank[e.key]![e.value.index].mono;
        if (m >= 0) return m;
      }
    }
    return mono;
  }

  bool anyActive(Iterable<Param> ps) => ps.any((p) => effective(p).abs() > 1e-4);

  EditState copyWith({
    Map<Param, double>? values,
    Map<String, PresetSel>? presets,
    int? mono,
    CurveSet? curves,
    Rect? crop,
    int? quarterTurns,
    bool? flipH,
    int? expandFill,
    Offset? blurCenter,
    int? blurShape,
    Offset? vigCenter,
    List<SelPoint>? points,
    List<BrushLayer>? brush,
    List<HealSpot>? heal,
    List<TextItem>? texts,
    int? frameStyle,
    int? frameColor,
    int? deImage,
    int? deBlend,
    Offset? deOffset,
  }) {
    return EditState(
      values: values ?? this.values,
      presets: presets ?? this.presets,
      mono: mono ?? this.mono,
      curves: curves ?? this.curves,
      crop: crop ?? this.crop,
      quarterTurns: quarterTurns ?? this.quarterTurns,
      flipH: flipH ?? this.flipH,
      expandFill: expandFill ?? this.expandFill,
      blurCenter: blurCenter ?? this.blurCenter,
      blurShape: blurShape ?? this.blurShape,
      vigCenter: vigCenter ?? this.vigCenter,
      points: points ?? this.points,
      brush: brush ?? this.brush,
      heal: heal ?? this.heal,
      texts: texts ?? this.texts,
      frameStyle: frameStyle ?? this.frameStyle,
      frameColor: frameColor ?? this.frameColor,
      deImage: deImage ?? this.deImage,
      deBlend: deBlend ?? this.deBlend,
      deOffset: deOffset ?? this.deOffset,
    );
  }
}
