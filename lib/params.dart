/// A single adjustable value. [id] makes every instance unique (const
/// canonicalisation would otherwise merge params with equal labels/ranges).
class Param {
  const Param(this.id, this.label, this.min, this.max, {this.geo = false});
  final String id;
  final String label;
  final double min;
  final double max;

  /// Geometry params affect the framing pass, not the pixel shaders.
  final bool geo;

  // Adjust
  static const brightness = Param('brightness', 'Brightness', -1, 1);
  static const contrast = Param('contrast', 'Contrast', -1, 1);
  static const saturation = Param('saturation', 'Saturation', -1, 1);
  static const ambiance = Param('ambiance', 'Ambiance', -1, 1);
  static const highlights = Param('highlights', 'Highlights', -1, 1);
  static const shadows = Param('shadows', 'Shadows', -1, 1);
  static const warmth = Param('warmth', 'Warmth', -1, 1);
  // Details / Refine / Fix
  static const structure = Param('structure', 'Structure', -1, 1);
  static const sharpen = Param('sharpen', 'Sharpening', 0, 1);
  static const texture = Param('texture', 'Texture', -1, 1);
  static const clarity = Param('clarity', 'Clarity', -1, 1);
  static const smooth = Param('smooth', 'Smooth', 0, 1);
  static const denoise = Param('denoise', 'Denoise', 0, 1);
  static const deblur = Param('deblur', 'Deblur', 0, 1);
  // Dehaze / Tonality / WB / Color
  static const dehaze = Param('dehaze', 'Dehaze', -1, 1);
  static const tcLow = Param('tcLow', 'Low tones', -1, 1);
  static const tcMid = Param('tcMid', 'Mid tones', -1, 1);
  static const tcHigh = Param('tcHigh', 'High tones', -1, 1);
  static const blacks = Param('blacks', 'Blacks', -1, 1);
  static const whites = Param('whites', 'Whites', -1, 1);
  static const wbTemp = Param('wbTemp', 'Temperature', -1, 1);
  static const wbTint = Param('wbTint', 'Tint', -1, 1);
  static const vibrance = Param('vibrance', 'Vibrance', -1, 1);
  static const hueShift = Param('hueShift', 'Hue shift', -1, 1);
  static const hslNames = ['Red', 'Orange', 'Yellow', 'Green', 'Aqua', 'Blue', 'Purple', 'Magenta'];
  static final List<Param> hslHue = [
    for (var i = 0; i < 8; i++) Param('hslH$i', '${hslNames[i]} hue', -1, 1),
  ];
  static final List<Param> hslSat = [
    for (var i = 0; i < 8; i++) Param('hslS$i', '${hslNames[i]} saturation', -1, 1),
  ];
  static final List<Param> hslLum = [
    for (var i = 0; i < 8; i++) Param('hslL$i', '${hslNames[i]} luminance', -1, 1),
  ];
  // Portrait
  static const skinSmooth = Param('skinSmooth', 'Skin smoothing', 0, 1);
  static const faceLight = Param('faceLight', 'Face light', 0, 1);
  static const eyeBright = Param('eyeBright', 'Eye clarity', 0, 1);
  // Head pose
  static const headRoll = Param('headRoll', 'Tilt', -1, 1);
  static const headYaw = Param('headYaw', 'Turn', -1, 1);
  static const headPitch = Param('headPitch', 'Nod', -1, 1);
  static const smile = Param('smile', 'Smile', -1, 1);
  static const eyeSize = Param('eyeSize', 'Eye size', -1, 1);
  static const faceSlim = Param('faceSlim', 'Face width', -1, 1);
  // Lens blur / vignette / CA / motion
  static const blur = Param('blur', 'Blur', 0, 1);
  static const blurSize = Param('blurSize', 'Focus size', 0, 1);
  static const blurFeather = Param('blurFeather', 'Transition', 0, 1);
  static const vignette = Param('vignette', 'Vignette', -1, 1);
  static const vigSize = Param('vigSize', 'Size', 0, 1);
  static const vigFeather = Param('vigFeather', 'Feather', 0, 1);
  static const caAmount = Param('caAmount', 'Fringe shift', -1, 1);
  static const motion = Param('motion', 'Length', 0, 1);
  static const motionAngle = Param('motionAngle', 'Angle', -1, 1);
  // Film / bloom / halation / glow
  static const fade = Param('fade', 'Fade', 0, 1);
  static const grain = Param('grain', 'Grain', 0, 1);
  static const grainSize = Param('grainSize', 'Grain size', 0, 1);
  static const bloom = Param('bloom', 'Bloom', 0, 1);
  static const bloomThr = Param('bloomThr', 'Threshold', 0, 1);
  static const bloomRad = Param('bloomRad', 'Radius', 0, 1);
  static const halation = Param('halation', 'Halation', 0, 1);
  static const halThr = Param('halThr', 'Threshold', 0, 1);
  static const halRad = Param('halRad', 'Spread', 0, 1);
  static const glow = Param('glow', 'Glow', 0, 1);
  static const glowSat = Param('glowSat', 'Saturation', -1, 1);
  static const glowWarm = Param('glowWarm', 'Warmth', -1, 1);
  // B&W / HDR / Drama / Grunge / Retrolux
  static const bwBright = Param('bwBright', 'Brightness', -1, 1);
  static const bwContrast = Param('bwContrast', 'Contrast', -1, 1);
  static const hdr = Param('hdr', 'Filter strength', 0, 1);
  static const hdrBright = Param('hdrBright', 'Brightness', -1, 1);
  static const hdrSat = Param('hdrSat', 'Saturation', -1, 1);
  static const drama = Param('drama', 'Filter strength', 0, 1);
  static const dramaSat = Param('dramaSat', 'Saturation', -1, 1);
  static const grungeTex = Param('grungeTex', 'Texture', 0, 1);
  static const grungeContrast = Param('grungeContrast', 'Contrast', -1, 1);
  static const grungeSat = Param('grungeSat', 'Saturation', -1, 1);
  static const leaks = Param('leaks', 'Light leaks', 0, 1);
  static const scratches = Param('scratches', 'Scratches', 0, 1);
  // Split toning (preset driven)
  static const stShadowHue = Param('stShadowHue', 'Shadow hue', 0, 1);
  static const stShadowAmt = Param('stShadowAmt', 'Shadow tint', 0, 1);
  static const stHighHue = Param('stHighHue', 'Highlight hue', 0, 1);
  static const stHighAmt = Param('stHighAmt', 'Highlight tint', 0, 1);
  // Double exposure / frames
  static const deOpacity = Param('deOpacity', 'Opacity', 0, 1);
  static const deScale = Param('deScale', 'Scale', -1, 1);
  static const frameSize = Param('frameSize', 'Frame size', 0, 1);
  // Geometry
  static const straighten = Param('straighten', 'Straighten', -45, 45, geo: true);
  static const perspV = Param('perspV', 'Vertical', -1, 1, geo: true);
  static const perspH = Param('perspH', 'Horizontal', -1, 1, geo: true);
  static const expand = Param('expand', 'Expand', 0, 0.5, geo: true);

  /// Every param, so saved projects can look them up by id.
  static final List<Param> all = [
    brightness,
    contrast,
    saturation,
    ambiance,
    highlights,
    shadows,
    warmth,
    structure,
    sharpen,
    texture,
    clarity,
    smooth,
    denoise,
    deblur,
    dehaze,
    tcLow,
    tcMid,
    tcHigh,
    blacks,
    whites,
    wbTemp,
    wbTint,
    vibrance,
    hueShift,
    skinSmooth,
    faceLight,
    eyeBright,
    headRoll,
    headYaw,
    headPitch,
    smile,
    eyeSize,
    faceSlim,
    blur,
    blurSize,
    blurFeather,
    vignette,
    vigSize,
    vigFeather,
    caAmount,
    motion,
    motionAngle,
    fade,
    grain,
    grainSize,
    bloom,
    bloomThr,
    bloomRad,
    halation,
    halThr,
    halRad,
    glow,
    glowSat,
    glowWarm,
    bwBright,
    bwContrast,
    hdr,
    hdrBright,
    hdrSat,
    drama,
    dramaSat,
    grungeTex,
    grungeContrast,
    grungeSat,
    leaks,
    scratches,
    stShadowHue,
    stShadowAmt,
    stHighHue,
    stHighAmt,
    deOpacity,
    deScale,
    frameSize,
    straighten,
    perspV,
    perspH,
    expand,
    ...hslHue,
    ...hslSat,
    ...hslLum,
  ];
  static final Map<String, Param> byId = {for (final p in all) p.id: p};
}
