import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import 'edit_state.dart';
import 'faces.dart';
import 'geometry.dart';
import 'lut.dart';
import 'models.dart';
import 'params.dart';

class RenderExtras {
  const RenderExtras({this.overlays = const {}, this.faces = const []});
  final Map<int, ui.Image> overlays;
  final List<FaceData> faces;
}

class _Mask {
  _Mask(this.img, this.w, this.h);
  final ui.Image img;
  final int w, h;
}

const _expected = {'spatial': 36, 'color': 84, 'fx': 32, 'warp': 64, 'brush': 4};
const _blends = [
  ui.BlendMode.srcOver,
  ui.BlendMode.screen,
  ui.BlendMode.lighten,
  ui.BlendMode.multiply,
  ui.BlendMode.overlay,
  ui.BlendMode.softLight,
];

class Renderer {
  Renderer._(this._prog, this.lut);

  final Map<String, ui.FragmentProgram?> _prog;
  final LutCache lut;
  final Map<BrushLayer, _Mask> _masks = {};

  List<String> get failedShaders => [
        for (final e in _prog.entries)
          if (e.value == null) e.key,
      ];

  static Future<Renderer> load() async {
    final programs = <String, ui.FragmentProgram?>{};
    for (final n in const ['spatial', 'color', 'fx', 'warp', 'brush']) {
      try {
        programs[n] = await ui.FragmentProgram.fromAsset('shaders/$n.frag');
      } catch (e) {
        debugPrint('Shader $n failed to load: $e');
        programs[n] = null;
      }
    }
    return Renderer._(programs, await LutCache.create());
  }

  void clearCaches() {
    for (final m in _masks.values) {
      m.img.dispose();
    }
    _masks.clear();
  }

  // ------------------------------------------------------------------ main

  /// Renders [source] with [s]. Always returns a new image owned by the caller.
  /// With [applyCrop] false the full (rotated) frame is returned (crop tool).
  ui.Image render(
    ui.Image source,
    EditState s, {
    bool applyCrop = true,
    RenderExtras extras = const RenderExtras(),
  }) {
    final sw = source.width.toDouble();
    final sh = source.height.toDouble();
    final pad = s[Param.expand] > 0 ? (s[Param.expand] * math.max(sw, sh)).round() : 0;
    final geo = buildGeometry(ui.Size(sw + 2 * pad, sh + 2 * pad), s, applyCrop);

    var img = _frame(source, s, geo, pad);
    final aspect = img.width / img.height;

    FaceFrame? face;
    if (extras.faces.isNotEmpty) {
      face = FaceFrame.from(extras.faces.first, (n) {
        final o = geo.map(n.dx * sw + pad, n.dy * sh + pad);
        return ui.Offset(o.dx / geo.out.width, o.dy / geo.out.height);
      });
    }

    img = _locals(img, s, extras);
    img = _warp(img, s, face, aspect);
    img = _spatial(img, s, face, aspect);
    img = _color(img, s);
    img = _brush(img, s);
    img = _fx(img, s);
    img = _overlay(img, s);
    return img;
  }

  // ---------------------------------------------------------------- helpers

  ui.Image _swap(ui.Image prev, ui.Image next) {
    prev.dispose();
    return next;
  }

  ui.Image _run(
    String name,
    ui.Image src,
    List<double> u, {
    List<ui.Image> extra = const [],
  }) {
    final prog = _prog[name]!;
    assert(u.length == _expected[name], '$name expects ${_expected[name]} floats, got ${u.length}');
    final w = src.width, h = src.height;
    final sh = prog.fragmentShader();
    sh.setFloat(0, w.toDouble());
    sh.setFloat(1, h.toDouble());
    for (var i = 0; i < u.length; i++) {
      sh.setFloat(i + 2, u[i]);
    }
    sh.setImageSampler(0, src);
    for (var i = 0; i < extra.length; i++) {
      sh.setImageSampler(i + 1, extra[i]);
    }
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..shader = sh,
    );
    final pic = rec.endRecording();
    final out = pic.toImageSync(w, h);
    pic.dispose();
    sh.dispose();
    return out;
  }

  // ----------------------------------------------------------------- frame

  ui.Image _expandImage(ui.Image src, int pad, int fill) {
    final w = src.width + 2 * pad, h = src.height + 2 * pad;
    final full = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, full);
    if (fill == 0) {
      final sg = math.max(w, h) * 0.02;
      c.save();
      c.clipRect(full);
      c.saveLayer(
        full,
        ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sg, sigmaY: sg, tileMode: ui.TileMode.mirror),
      );
      final sc = math.max(w / src.width, h / src.height) * 1.05;
      c.translate(w / 2, h / 2);
      c.scale(sc, sc);
      c.translate(-src.width / 2, -src.height / 2);
      c.drawImage(src, ui.Offset.zero, ui.Paint());
      c.restore();
      c.restore();
    } else {
      c.drawRect(full, ui.Paint()..color = ui.Color(fill == 1 ? 0xFF000000 : 0xFFFFFFFF));
    }
    c.drawImage(src, ui.Offset(pad.toDouble(), pad.toDouble()), ui.Paint());
    final pic = rec.endRecording();
    final out = pic.toImageSync(w, h);
    pic.dispose();
    return out;
  }

  ui.Image _frame(ui.Image src, EditState s, Geo geo, int pad) {
    ui.Image base = src;
    ui.Image? tmp;
    if (pad > 0) {
      tmp = _expandImage(src, pad, s.expandFill);
      base = tmp;
    }
    final w = geo.out.width.round(), h = geo.out.height.round();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    c.clipRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    c.transform(geo.m.storage);
    c.drawImage(base, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.high);
    final pic = rec.endRecording();
    final out = pic.toImageSync(w, h);
    pic.dispose();
    tmp?.dispose();
    return out;
  }

  // ----------------------------------------------- heal + double exposure

  ui.Image _locals(ui.Image img, EditState s, RenderExtras ex) {
    final de = ex.overlays[s.deImage];
    final hasDe = de != null && s[Param.deOpacity] > 0;
    if (s.heal.isEmpty && !hasDe) return img;
    final w = img.width.toDouble(), h = img.height.toDouble();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w, h));
    c.drawImage(img, ui.Offset.zero, ui.Paint());
    for (final spot in s.heal) {
      final ctr = ui.Offset(spot.pos.dx * w, spot.pos.dy * h);
      final r = spot.radius * h;
      final dst = ui.Rect.fromCircle(center: ctr, radius: r);
      c.saveLayer(dst.inflate(2), ui.Paint());
      c.drawImageRect(
        img,
        dst.shift(ui.Offset(spot.src.dx * w, spot.src.dy * h)),
        dst,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      c.drawRect(
        dst,
        ui.Paint()
          ..blendMode = ui.BlendMode.dstIn
          ..shader = ui.Gradient.radial(
            ctr,
            r,
            const [ui.Color(0xFFFFFFFF), ui.Color(0xFFFFFFFF), ui.Color(0x00FFFFFF)],
            const [0.0, 0.55, 1.0],
          ),
      );
      c.restore();
    }
    if (hasDe) {
      final ow = de.width.toDouble(), oh = de.height.toDouble();
      final sc = math.max(w / ow, h / oh) * math.pow(2, s[Param.deScale]);
      c.save();
      c.clipRect(ui.Rect.fromLTWH(0, 0, w, h));
      c.translate(w / 2 + s.deOffset.dx * w, h / 2 + s.deOffset.dy * h);
      c.scale(sc.toDouble(), sc.toDouble());
      c.translate(-ow / 2, -oh / 2);
      c.drawImage(
        de,
        ui.Offset.zero,
        ui.Paint()
          ..blendMode = _blends[math.min(math.max(s.deBlend, 0), _blends.length - 1)]
          ..colorFilter = ui.ColorFilter.mode(
            ui.Color.fromRGBO(255, 255, 255, s[Param.deOpacity]),
            ui.BlendMode.modulate,
          )
          ..filterQuality = ui.FilterQuality.medium,
      );
      c.restore();
    }
    final pic = rec.endRecording();
    final out = pic.toImageSync(img.width, img.height);
    pic.dispose();
    return _swap(img, out);
  }

  // ------------------------------------------------------------------ warp

  ui.Image _warp(ui.Image img, EditState s, FaceFrame? f, double aspect) {
    if (_prog['warp'] == null || f == null) return img;
    const hp = [
      Param.headRoll, Param.headYaw, Param.headPitch, Param.smile, Param.eyeSize, Param.faceSlim,
    ];
    if (!s.anyActive(hp)) return img;
    return _swap(img, _run('warp', img, buildWarp(f, s, aspect)));
  }

  // --------------------------------------------------------------- spatial

  static const _spatialParams = <Param>[
    Param.sharpen, Param.structure, Param.clarity, Param.texture, Param.dehaze,
    Param.tcLow, Param.tcMid, Param.tcHigh, Param.smooth, Param.denoise, Param.deblur,
    Param.caAmount, Param.blur, Param.motion, Param.skinSmooth, Param.faceLight,
    Param.eyeBright, Param.ambiance,
  ];

  ui.Image _spatial(ui.Image img, EditState s, FaceFrame? f, double aspect) {
    if (_prog['spatial'] == null || !s.anyActive(_spatialParams)) return img;
    double e(Param q) => s.effective(q);
    final eyeR = f == null ? 0.0 : f.eyeDist(aspect) * 0.35;
    final face = f == null
        ? <double>[0.5, 0.5, -1.0, -1.0, -10.0, -10.0, -10.0, -10.0]
        : <double>[f.center.dx, f.center.dy, f.wu / 2, f.hu / 2, f.eyeL.dx, f.eyeL.dy, f.eyeR.dx, f.eyeR.dy];
    return _swap(
      img,
      _run('spatial', img, <double>[
        e(Param.sharpen), e(Param.structure), e(Param.clarity), e(Param.texture),
        e(Param.dehaze), e(Param.tcLow), e(Param.tcMid), e(Param.tcHigh),
        e(Param.smooth), e(Param.denoise), e(Param.deblur), e(Param.caAmount),
        e(Param.blur), e(Param.blurSize), e(Param.blurFeather), s.blurShape.toDouble(),
        s.blurCenter.dx, s.blurCenter.dy, e(Param.motion), e(Param.motionAngle) * math.pi / 2,
        e(Param.skinSmooth), e(Param.faceLight), e(Param.eyeBright), eyeR,
        ...face,
        e(Param.ambiance), 0.0, 0.0, 0.0,
      ]),
    );
  }

  // ----------------------------------------------------------------- color

  static final _colorParams = <Param>[
    Param.brightness, Param.contrast, Param.saturation, Param.ambiance, Param.highlights,
    Param.shadows, Param.warmth, Param.blacks, Param.whites, Param.wbTemp, Param.wbTint,
    Param.vibrance, Param.hueShift, Param.stShadowAmt, Param.stHighAmt,
    ...Param.hslHue, ...Param.hslSat, ...Param.hslLum,
  ];

  static const _monoWeights = <List<double>>[
    [0.299, 0.587, 0.114],
    [0.65, 0.30, 0.05],
    [0.55, 0.38, 0.07],
    [0.40, 0.55, 0.05],
    [0.15, 0.70, 0.15],
    [0.10, 0.30, 0.60],
  ];

  ui.Image _color(ui.Image img, EditState s) {
    if (_prog['color'] == null) return img;
    final lutImg = s.curves.isIdentity ? lut.identityLut : lut.get(s.curves);
    final curvesOn = !s.curves.isIdentity && lutImg != null;
    final mono = s.effectiveMono;
    final hslOn = s.anyActive([...Param.hslHue, ...Param.hslSat, ...Param.hslLum]);
    if (!s.anyActive(_colorParams) && mono < 0 && !curvesOn && s.points.isEmpty) return img;
    double e(Param q) => s.effective(q);
    List<double> hsl(List<Param> ps) => [for (final p in ps) e(p)];
    final mw = mono < 0 ? const [0.0, 0.0, 0.0] : _monoWeights[math.min(math.max(mono, 0), 5)];
    final pts = <double>[];
    for (var i = 0; i < 4; i++) {
      if (i < s.points.length) {
        final p = s.points[i];
        pts.addAll([p.pos.dx, p.pos.dy, p.radius, 1.0, p.brightness, p.contrast, p.saturation, p.warmth]);
      } else {
        pts.addAll(const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
      }
    }
    return _swap(
      img,
      _run(
        'color',
        img,
        <double>[
          e(Param.brightness), e(Param.contrast), e(Param.saturation), e(Param.ambiance),
          e(Param.highlights), e(Param.shadows), e(Param.warmth), e(Param.blacks),
          e(Param.whites), e(Param.wbTemp), e(Param.wbTint), e(Param.vibrance),
          e(Param.hueShift), e(Param.stShadowHue), e(Param.stShadowAmt), e(Param.stHighHue),
          e(Param.stHighAmt), curvesOn ? 1.0 : 0.0, hslOn ? 1.0 : 0.0, mono < 0 ? 0.0 : 1.0,
          mw[0], mw[1], mw[2], e(Param.bwBright),
          e(Param.bwContrast), 0.0, 0.0, 0.0,
          ...hsl(Param.hslHue.sublist(0, 4)), ...hsl(Param.hslHue.sublist(4)),
          ...hsl(Param.hslSat.sublist(0, 4)), ...hsl(Param.hslSat.sublist(4)),
          ...hsl(Param.hslLum.sublist(0, 4)), ...hsl(Param.hslLum.sublist(4)),
          ...pts,
        ],
        extra: [curvesOn ? lutImg! : lut.identityLut],
      ),
    );
  }

  // ----------------------------------------------------------------- brush

  ui.Image _mask(BrushLayer l, double fw, double fh) {
    final k = 1024 / math.max(fw, fh);
    final mw = math.max(1, (fw * k).round());
    final mh = math.max(1, (fh * k).round());
    final cached = _masks[l];
    if (cached != null && cached.w == mw && cached.h == mh) return cached.img;
    _masks.remove(l)?.img.dispose();
    if (_masks.length > 8) {
      final first = _masks.keys.first;
      _masks.remove(first)?.img.dispose();
    }
    final bounds = ui.Rect.fromLTWH(0, 0, mw.toDouble(), mh.toDouble());
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, bounds);
    c.saveLayer(bounds, ui.Paint());
    for (final st in l.strokes) {
      final width = math.max(1.0, st.size * mw);
      final p = ui.Paint()
        ..color = const ui.Color(0xFFFFFFFF)
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..strokeWidth = width
        ..blendMode = st.erase ? ui.BlendMode.dstOut : ui.BlendMode.srcOver
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, width * 0.18);
      final pts = [for (final o in st.pts) ui.Offset(o.dx * mw, o.dy * mh)];
      if (pts.length == 1) {
        c.drawPoints(ui.PointMode.points, pts, p);
      } else if (pts.length > 1) {
        final path = ui.Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final o in pts.skip(1)) {
          path.lineTo(o.dx, o.dy);
        }
        c.drawPath(path, p);
      }
    }
    c.restore();
    final pic = rec.endRecording();
    final out = pic.toImageSync(mw, mh);
    pic.dispose();
    _masks[l] = _Mask(out, mw, mh);
    return out;
  }

  ui.Image _brush(ui.Image img, EditState s) {
    if (_prog['brush'] == null || s.brush.isEmpty) return img;
    var out = img;
    for (final l in s.brush) {
      if (l.strokes.isEmpty || l.amount <= 0) continue;
      final m = _mask(l, out.width.toDouble(), out.height.toDouble());
      out = _swap(out, _run('brush', out, [l.mode.toDouble(), l.amount, 0.0, 0.0], extra: [m]));
    }
    return out;
  }

  // -------------------------------------------------------------------- fx

  static const _fxParams = <Param>[
    Param.bloom, Param.glow, Param.halation, Param.hdr, Param.drama, Param.grungeTex,
    Param.leaks, Param.scratches, Param.fade, Param.vignette, Param.grain,
  ];

  ui.Image _fx(ui.Image img, EditState s) {
    if (_prog['fx'] == null || !s.anyActive(_fxParams)) return img;
    double e(Param q) => s.effective(q);
    final grungeStyle = (s.presets['grunge']?.index ?? 0).toDouble();
    final retroStyle = (s.presets['retrolux']?.index ?? 0).toDouble();
    return _swap(
      img,
      _run('fx', img, <double>[
        e(Param.bloom), e(Param.bloomThr), e(Param.bloomRad), e(Param.glow),
        e(Param.glowSat), e(Param.glowWarm), e(Param.halation), e(Param.halThr),
        e(Param.halRad), e(Param.hdr), e(Param.hdrBright), e(Param.hdrSat),
        e(Param.drama), e(Param.dramaSat), e(Param.grungeTex), e(Param.grungeContrast),
        e(Param.grungeSat), grungeStyle, e(Param.leaks), e(Param.scratches),
        retroStyle, e(Param.fade), e(Param.grain), e(Param.grainSize),
        e(Param.vignette), e(Param.vigSize), e(Param.vigFeather), 0.0,
        s.vigCenter.dx, s.vigCenter.dy, 0.37, 0.0,
      ]),
    );
  }

  // --------------------------------------------------------------- overlay

  String? _family(int f) {
    final apple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
    switch (f) {
      case 1:
        return apple ? 'Georgia' : 'serif';
      case 2:
        return apple ? 'Courier' : 'monospace';
      default:
        return null;
    }
  }

  void _drawText(ui.Canvas c, TextItem t, double w, double h) {
    final fs = t.size * h;
    final style = TextStyle(
      fontSize: fs,
      height: 1.1,
      color: ui.Color(t.color).withAlpha((255 * t.opacity).round()),
      fontFamily: _family(t.font),
      fontWeight: t.font == 3 ? ui.FontWeight.w800 : ui.FontWeight.w500,
      fontStyle: t.font == 3 ? ui.FontStyle.italic : ui.FontStyle.normal,
      shadows: t.shadow
          ? [ui.Shadow(blurRadius: fs * 0.12, color: const ui.Color(0x99000000), offset: ui.Offset(0, fs * 0.04))]
          : null,
    );
    final tp = TextPainter(
      text: TextSpan(text: t.text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: ui.TextAlign.center,
    )..layout(maxWidth: w * 0.92);
    c.save();
    c.translate(t.pos.dx * w, t.pos.dy * h);
    c.rotate(t.rotation * math.pi / 180);
    tp.paint(c, ui.Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  void _drawFrame(ui.Canvas c, double w, double h, EditState s) {
    if (s.frameStyle == 0) return;
    final t = (0.02 + 0.12 * s[Param.frameSize]) * math.min(w, h);
    final fill = ui.Paint()..color = ui.Color(s.frameColor);
    final outer = ui.Rect.fromLTWH(0, 0, w, h);
    ui.Path ring(ui.Rect inner, {double r = 0}) {
      final p = ui.Path()
        ..fillType = ui.PathFillType.evenOdd
        ..addRect(outer);
      if (r > 0) {
        p.addRRect(ui.RRect.fromRectAndRadius(inner, ui.Radius.circular(r)));
      } else {
        p.addRect(inner);
      }
      return p;
    }

    switch (s.frameStyle) {
      case 1:
        c.drawPath(ring(outer.deflate(t)), fill);
      case 2:
        c.drawPath(ring(outer.deflate(t), r: t * 1.4), fill);
      case 3:
        c.drawPath(ring(ui.Rect.fromLTRB(t, t, w - t, h - t * 3.2)), fill);
      case 4:
        final band = t * 1.6;
        c.drawRect(ui.Rect.fromLTWH(0, 0, band, h), fill);
        c.drawRect(ui.Rect.fromLTWH(w - band, 0, band, h), fill);
        final hole = ui.Paint()..color = const ui.Color(0xCCFFFFFF);
        final step = band * 1.4;
        for (var y = step * 0.4; y < h - band * 0.6; y += step) {
          for (final x in [band * 0.28, w - band * 0.72]) {
            c.drawRRect(
              ui.RRect.fromRectAndRadius(
                ui.Rect.fromLTWH(x, y, band * 0.44, band * 0.6),
                ui.Radius.circular(band * 0.1),
              ),
              hole,
            );
          }
        }
      case 5:
        c.drawPath(ring(outer.deflate(t * 0.5)), fill);
        c.drawRect(
          outer.deflate(t * 1.3),
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, t * 0.12)
            ..color = ui.Color(s.frameColor),
        );
    }
  }

  ui.Image _overlay(ui.Image img, EditState s) {
    if (s.frameStyle == 0 && s.texts.isEmpty) return img;
    final w = img.width.toDouble(), h = img.height.toDouble();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w, h));
    c.drawImage(img, ui.Offset.zero, ui.Paint());
    _drawFrame(c, w, h, s);
    for (final t in s.texts) {
      if (t.text.trim().isNotEmpty) _drawText(c, t, w, h);
    }
    final pic = rec.endRecording();
    final out = pic.toImageSync(img.width, img.height);
    pic.dispose();
    return _swap(img, out);
  }
}
