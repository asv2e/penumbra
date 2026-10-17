import 'params.dart';

class Preset {
  const Preset(this.name, this.deltas, {this.mono = -1});
  final String name;
  final Map<Param, double> deltas;

  /// Index into the mono filter list, or -1 for colour.
  final int mono;
}

/// Preset banks keyed by tool. Index 0 is always "None".
const Map<String, List<Preset>> presetBank = {
  'style': [
    Preset('None', {}),
    Preset('Vivid', {Param.contrast: 0.2, Param.saturation: 0.35, Param.ambiance: 0.2}),
    Preset('Warm', {Param.warmth: 0.35, Param.saturation: 0.1, Param.fade: 0.1}),
    Preset('Cool', {Param.warmth: -0.3, Param.wbTint: -0.05, Param.contrast: 0.1}),
    Preset('Soft', {Param.contrast: -0.15, Param.brightness: 0.05, Param.glow: 0.25}),
    Preset('Crisp', {Param.contrast: 0.15, Param.sharpen: 0.35, Param.structure: 0.3}),
    Preset('Faded', {Param.fade: 0.5, Param.saturation: -0.25, Param.contrast: -0.1}),
    Preset('Matte', {Param.fade: 0.35, Param.shadows: 0.2, Param.saturation: -0.1}),
    Preset('Sunset', {Param.warmth: 0.5, Param.wbTint: 0.15, Param.saturation: 0.2, Param.contrast: 0.1}),
    Preset('Teal & Orange', {
      Param.contrast: 0.15,
      Param.saturation: 0.1,
      Param.stShadowHue: 0.5,
      Param.stShadowAmt: 0.7,
      Param.stHighHue: 0.08,
      Param.stHighAmt: 0.6,
    }),
    Preset('Pastel', {Param.brightness: 0.1, Param.saturation: -0.2, Param.fade: 0.25, Param.contrast: -0.15}),
    Preset('Moody', {
      Param.contrast: 0.25,
      Param.brightness: -0.1,
      Param.saturation: -0.2,
      Param.vignette: 0.35,
      Param.stShadowHue: 0.58,
      Param.stShadowAmt: 0.4,
    }),
  ],
  'vintage': [
    Preset('None', {}),
    Preset('Sepia', {
      Param.fade: 0.15,
      Param.vignette: 0.2,
      Param.stShadowHue: 0.08,
      Param.stShadowAmt: 0.6,
      Param.stHighHue: 0.11,
      Param.stHighAmt: 0.5,
    }, mono: 0),
    Preset('70s', {
      Param.warmth: 0.3,
      Param.fade: 0.3,
      Param.saturation: -0.1,
      Param.stShadowHue: 0.6,
      Param.stShadowAmt: 0.3,
      Param.vignette: 0.2,
    }),
    Preset('Polaroid', {
      Param.contrast: -0.1,
      Param.fade: 0.25,
      Param.saturation: 0.1,
      Param.warmth: 0.15,
      Param.vignette: 0.3,
      Param.grain: 0.15,
    }),
    Preset('Kodak', {Param.contrast: 0.2, Param.saturation: 0.3, Param.warmth: 0.15, Param.grain: 0.1}),
    Preset('Cross process', {
      Param.contrast: 0.3,
      Param.saturation: 0.2,
      Param.stShadowHue: 0.5,
      Param.stShadowAmt: 0.6,
      Param.stHighHue: 0.15,
      Param.stHighAmt: 0.6,
    }),
    Preset('Faded film', {Param.fade: 0.45, Param.saturation: -0.3, Param.grain: 0.25, Param.vignette: 0.25}),
  ],
  'noir': [
    Preset('None', {}),
    Preset('Classic', {Param.contrast: 0.25, Param.grain: 0.2, Param.vignette: 0.25}, mono: 0),
    Preset('Red filter', {Param.contrast: 0.3, Param.grain: 0.2, Param.vignette: 0.3}, mono: 1),
    Preset('High contrast', {Param.contrast: 0.6, Param.grain: 0.3, Param.vignette: 0.4}, mono: 2),
    Preset('Wash', {Param.fade: 0.4, Param.contrast: -0.05, Param.grain: 0.15}, mono: 0),
    Preset('Grainy', {Param.grain: 0.7, Param.grainSize: 0.4, Param.contrast: 0.3}, mono: 3),
    Preset('Dark', {Param.brightness: -0.15, Param.contrast: 0.4, Param.vignette: 0.55, Param.grain: 0.25}, mono: 5),
  ],
  'retrolux': [
    Preset('None', {}),
    Preset('Retro 1', {Param.leaks: 0.6, Param.scratches: 0.4, Param.fade: 0.2, Param.warmth: 0.2, Param.grain: 0.25, Param.vignette: 0.3}),
    Preset('Retro 2', {Param.leaks: 0.5, Param.scratches: 0.6, Param.fade: 0.3, Param.saturation: -0.1, Param.grain: 0.35, Param.vignette: 0.25}),
    Preset('Retro 3', {Param.leaks: 0.7, Param.scratches: 0.3, Param.contrast: 0.15, Param.warmth: 0.1, Param.grain: 0.2, Param.vignette: 0.35}),
    Preset('Retro 4', {Param.leaks: 0.55, Param.scratches: 0.5, Param.fade: 0.25, Param.warmth: -0.15, Param.grain: 0.3, Param.vignette: 0.3}),
    Preset('Retro 5', {Param.leaks: 0.8, Param.scratches: 0.7, Param.fade: 0.35, Param.saturation: 0.15, Param.grain: 0.4, Param.vignette: 0.4}),
  ],
  'grunge': [
    Preset('None', {}),
    Preset('Concrete', {Param.grungeTex: 0.7, Param.grungeContrast: 0.2, Param.grungeSat: -0.2, Param.contrast: 0.1}),
    Preset('Paper', {Param.grungeTex: 0.6, Param.grungeContrast: 0.0, Param.grungeSat: -0.1, Param.warmth: 0.15}),
    Preset('Brushed', {Param.grungeTex: 0.65, Param.grungeContrast: 0.3, Param.grungeSat: -0.3}),
    Preset('Stains', {Param.grungeTex: 0.8, Param.grungeContrast: 0.1, Param.grungeSat: 0.0, Param.vignette: 0.3}),
    Preset('Dust', {Param.grungeTex: 0.55, Param.grungeContrast: 0.4, Param.grungeSat: -0.15, Param.grain: 0.2}),
  ],
  'hdr': [
    Preset('None', {}),
    Preset('Nature', {Param.hdr: 0.6, Param.hdrSat: 0.2}),
    Preset('People', {Param.hdr: 0.4, Param.hdrSat: -0.1}),
    Preset('Fine', {Param.hdr: 0.35, Param.hdrBright: 0.05}),
    Preset('Strong', {Param.hdr: 0.9, Param.hdrSat: 0.3}),
  ],
  'drama': [
    Preset('None', {}),
    Preset('Drama 1', {Param.drama: 0.6, Param.dramaSat: -0.1}),
    Preset('Drama 2', {Param.drama: 0.85, Param.dramaSat: -0.2, Param.contrast: 0.1}),
    Preset('Bright 1', {Param.drama: 0.5, Param.brightness: 0.15}),
    Preset('Bright 2', {Param.drama: 0.7, Param.brightness: 0.2, Param.dramaSat: 0.1}),
    Preset('Dark 1', {Param.drama: 0.6, Param.brightness: -0.15, Param.vignette: 0.3}),
    Preset('Dark 2', {Param.drama: 0.8, Param.brightness: -0.25, Param.vignette: 0.45, Param.dramaSat: -0.2}),
  ],
  'film': [
    Preset('None', {}),
    Preset('Portra', {Param.warmth: 0.1, Param.fade: 0.15, Param.saturation: -0.05, Param.grain: 0.2, Param.contrast: -0.05}),
    Preset('Ektar', {Param.saturation: 0.3, Param.contrast: 0.15, Param.grain: 0.1}),
    Preset('Tri-X', {Param.contrast: 0.3, Param.grain: 0.5, Param.grainSize: 0.3}, mono: 0),
    Preset('Cinestill', {Param.halation: 0.5, Param.warmth: -0.1, Param.grain: 0.25, Param.contrast: 0.1}),
    Preset('Velvia', {Param.saturation: 0.5, Param.contrast: 0.2, Param.grain: 0.08}),
  ],
};
