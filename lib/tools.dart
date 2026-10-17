import 'package:flutter/material.dart';

import 'params.dart';

enum ToolKind {
  params,
  curves,
  color,
  selective,
  brush,
  heal,
  text,
  crop,
  rotate,
  expand,
  frames,
  doubleExposure,
  bw,
  fix,
  lensBlur,
  vignette,
}

enum Tool {
  adjust('Adjust', Icons.tune, ToolKind.params, params: [
    Param.brightness, Param.contrast, Param.saturation, Param.ambiance,
    Param.highlights, Param.shadows, Param.warmth,
  ]),
  details('Details', Icons.deblur, ToolKind.params, params: [Param.structure, Param.sharpen]),
  dehaze('Dehaze', Icons.cloud_queue, ToolKind.params, params: [Param.dehaze]),
  tonality('Tonality', Icons.contrast, ToolKind.params, params: [
    Param.tcLow, Param.tcMid, Param.tcHigh, Param.blacks, Param.whites,
  ]),
  curves('Curves', Icons.show_chart, ToolKind.curves),
  portrait('Portrait', Icons.face_retouching_natural, ToolKind.params,
      params: [Param.skinSmooth, Param.faceLight, Param.eyeBright], faces: true),
  whiteBalance('White Balance', Icons.wb_auto, ToolKind.params, params: [Param.wbTemp, Param.wbTint]),
  color('Color', Icons.palette, ToolKind.color),
  lensBlur('Lens Blur', Icons.blur_circular, ToolKind.lensBlur,
      params: [Param.blur, Param.blurSize, Param.blurFeather]),
  vignette('Vignette', Icons.vignette, ToolKind.vignette,
      params: [Param.vignette, Param.vigSize, Param.vigFeather]),
  selective('Selective', Icons.gps_fixed, ToolKind.selective),
  brush('Brush', Icons.brush, ToolKind.brush),
  healing('Healing', Icons.healing, ToolKind.heal),
  headPose('Head Pose', Icons.face, ToolKind.params, params: [
    Param.headRoll, Param.headYaw, Param.headPitch, Param.smile, Param.eyeSize, Param.faceSlim,
  ], faces: true),
  chromaticAberration('Chromatic Aberration', Icons.looks, ToolKind.params, params: [Param.caAmount]),
  vintage('Vintage', Icons.photo_filter, ToolKind.params,
      presetKey: 'vintage', params: [Param.vignette, Param.grain]),
  noir('Noir', Icons.nightlight_round, ToolKind.params,
      presetKey: 'noir', params: [Param.grain, Param.fade, Param.vignette]),
  text('Text', Icons.text_fields, ToolKind.text),
  refine('Refine', Icons.auto_fix_high, ToolKind.params, params: [Param.texture, Param.clarity, Param.smooth]),
  fix('Fix', Icons.build, ToolKind.fix, params: [Param.denoise, Param.deblur]),
  style('Style', Icons.auto_awesome, ToolKind.params, presetKey: 'style'),
  crop('Crop', Icons.crop, ToolKind.crop),
  perspective('Perspective', Icons.transform, ToolKind.params,
      params: [Param.perspV, Param.perspH, Param.straighten]),
  expand('Expand', Icons.open_in_full, ToolKind.expand, params: [Param.expand]),
  film('Film', Icons.movie_filter, ToolKind.params,
      presetKey: 'film', params: [Param.grain, Param.grainSize, Param.fade]),
  bloom('Bloom', Icons.wb_twilight, ToolKind.params, params: [Param.bloom, Param.bloomThr, Param.bloomRad]),
  halation('Halation', Icons.brightness_high, ToolKind.params,
      params: [Param.halation, Param.halThr, Param.halRad]),
  motionBlur('Motion Blur', Icons.motion_photos_on, ToolKind.params,
      params: [Param.motion, Param.motionAngle]),
  glow('Glow', Icons.light_mode, ToolKind.params, params: [Param.glow, Param.glowSat, Param.glowWarm]),
  retrolux('Retrolux', Icons.camera_roll, ToolKind.params,
      presetKey: 'retrolux', params: [Param.leaks, Param.scratches, Param.grain, Param.fade, Param.vignette]),
  blackWhite('Black & White', Icons.filter_b_and_w, ToolKind.bw,
      params: [Param.bwBright, Param.bwContrast, Param.grain]),
  hdrScape('HDR Scape', Icons.hdr_on, ToolKind.params,
      presetKey: 'hdr', params: [Param.hdr, Param.hdrBright, Param.hdrSat]),
  drama('Drama', Icons.theater_comedy, ToolKind.params, presetKey: 'drama', params: [Param.drama, Param.dramaSat]),
  grunge('Grunge', Icons.grain, ToolKind.params,
      presetKey: 'grunge', params: [Param.grungeTex, Param.grungeContrast, Param.grungeSat]),
  doubleExposure('Double Exposure', Icons.layers, ToolKind.doubleExposure,
      params: [Param.deOpacity, Param.deScale]),
  frames('Frames', Icons.filter_frames, ToolKind.frames, params: [Param.frameSize]);

  const Tool(
    this.label,
    this.icon,
    this.kind, {
    this.params = const <Param>[],
    this.presetKey,
    this.faces = false,
  });

  final String label;
  final IconData icon;
  final ToolKind kind;
  final List<Param> params;
  final String? presetKey;

  /// Needs face detection.
  final bool faces;
}
