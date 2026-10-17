import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show immutable;

const brushModes = ['Dodge', 'Burn', 'Warm', 'Cool', 'Saturate', 'Desaturate', 'Smooth'];
const fontNames = ['Sans', 'Serif', 'Mono', 'Display'];
const frameNames = ['None', 'Solid', 'Rounded', 'Polaroid', 'Film', 'Double'];
const blendNames = ['Normal', 'Screen', 'Lighten', 'Multiply', 'Overlay', 'Soft light'];
const expandFillNames = ['Smart fill', 'Black', 'White'];
const swatches = <int>[
  0xFFFFFFFF, 0xFF000000, 0xFFF5E6C8, 0xFFE53935, 0xFFFB8C00,
  0xFFFDD835, 0xFF43A047, 0xFF1E88E5, 0xFF8E24AA, 0xFFEC407A,
];

@immutable
class PresetSel {
  const PresetSel(this.index, this.strength);
  final int index;
  final double strength;
}

@immutable
class SelPoint {
  const SelPoint({
    required this.pos,
    this.radius = 0.18,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
  });
  final Offset pos;
  final double radius;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  SelPoint copyWith({
    Offset? pos,
    double? radius,
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
  }) =>
      SelPoint(
        pos: pos ?? this.pos,
        radius: radius ?? this.radius,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        warmth: warmth ?? this.warmth,
      );
}

@immutable
class Stroke {
  const Stroke(this.pts, this.size, this.erase);
  final List<Offset> pts;

  /// Brush diameter as a fraction of frame width.
  final double size;
  final bool erase;
}

@immutable
class BrushLayer {
  const BrushLayer(this.mode, this.amount, this.strokes);
  final int mode;
  final double amount;
  final List<Stroke> strokes;

  BrushLayer copyWith({double? amount, List<Stroke>? strokes}) =>
      BrushLayer(mode, amount ?? this.amount, strokes ?? this.strokes);
}

@immutable
class HealSpot {
  const HealSpot(this.pos, this.radius, this.src);
  final Offset pos;

  /// Radius as a fraction of frame height.
  final double radius;

  /// Source patch offset, normalised to frame size.
  final Offset src;
}

@immutable
class TextItem {
  const TextItem({
    required this.text,
    this.pos = const Offset(0.5, 0.5),
    this.size = 0.08,
    this.rotation = 0,
    this.opacity = 1,
    this.font = 0,
    this.color = 0xFFFFFFFF,
    this.shadow = true,
  });
  final String text;
  final Offset pos;

  /// Font size as a fraction of frame height.
  final double size;
  final double rotation;
  final double opacity;
  final int font;
  final int color;
  final bool shadow;

  TextItem copyWith({
    String? text,
    Offset? pos,
    double? size,
    double? rotation,
    double? opacity,
    int? font,
    int? color,
    bool? shadow,
  }) =>
      TextItem(
        text: text ?? this.text,
        pos: pos ?? this.pos,
        size: size ?? this.size,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        font: font ?? this.font,
        color: color ?? this.color,
        shadow: shadow ?? this.shadow,
      );
}
