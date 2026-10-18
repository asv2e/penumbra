import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'edit_state.dart';
import 'faces_api.dart';
import 'faces.dart';
import 'image_io.dart';
import 'models.dart';
import 'params.dart';
import 'platform_api.dart';
import 'renderer.dart';
import 'tools.dart';
import 'ui/color_panel.dart';
import 'ui/crop_overlay.dart';
import 'ui/curves_panel.dart';
import 'ui/local_tools.dart';
import 'ui/panels.dart';
import 'ui/widgets.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  Renderer? _renderer;
  ui.Image? _full;
  ui.Image? _preview;
  ui.Image? _thumb;
  ui.Image? _shown;

  final Map<int, ui.Image> _overlays = {};
  int _nextOverlay = 1;
  List<FaceData> _faces = [];
  bool _facesLoaded = false;
  Uint8List? _frameBytes;
  int _frameW = 0, _frameH = 0;

  final List<EditState> _history = [const EditState()];
  int _cursor = 0;

  Tool? _tool;
  EditState _draft = const EditState();
  int _paramIndex = 0;
  int _aspectIndex = 0;
  int _curveChannel = 0;
  int _band = -1;
  int _selPoint = -1;
  int _brushMode = 0;
  double _brushSize = 0.06;
  double _brushAmount = 0.6;
  bool _erase = false;
  double _healRadius = 0.04;
  int _textIndex = -1;

  bool _comparing = false;
  bool _busy = false;
  bool _renderErrorShown = false;

  double _dragX = 0, _dragY = 0;
  Axis? _axis;

  RenderExtras get _extras => RenderExtras(overlays: _overlays, faces: _faces);
  EditState get _current => _tool == null ? _history[_cursor] : _draft;
  List<Param> get _params => _tool?.params ?? const <Param>[];

  @override
  void initState() {
    super.initState();
    Renderer.load().then((r) {
      if (!mounted) return;
      r.lut.onReady = _rerender;
      setState(() => _renderer = r);
      if (r.failedShaders.isNotEmpty) {
        _toast('Some effects are unavailable on this device: ${r.failedShaders.join(', ')}');
      }
    });
  }

  @override
  void dispose() {
    for (final i in [_full, _preview, _thumb, _shown, ..._overlays.values]) {
      _retire(i);
    }
    super.dispose();
  }

  void _retire(ui.Image? img) {
    if (img == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => img.dispose());
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------------------------------------------------------- loading

  Future<void> _showOpen() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Browse files (JPEG, PNG, TIFF, DNG, RAW)'),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          if (platformHasPhotoPicker)
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo library'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          if (platformHasPhotoPicker)
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
        ]),
      ),
    );
    if (choice == null) return;
    try {
      final f = choice == 'file' ? await pickImageFile() : await platformPickPhoto(camera: choice == 'camera');
      if (f != null) await _loadBytes(f.bytes, f.name);
    } catch (e) {
      _toast('Could not open file: $e');
    }
  }

  Future<void> _loadBytes(Uint8List bytes, String name) async {
    setState(() => _busy = true);
    try {
      final full = await loadImage(bytes, name);
      // Web re-runs every shader pass on each edit, so keep its working size smaller.
      final preview = scaleToMax(full, kIsWeb ? 1024 : 1600);
      final thumb = scaleToMax(preview, 180);
      final old = [_full, _preview, _thumb, _shown, ..._overlays.values];
      _renderer?.clearCaches();
      setState(() {
        _full = full;
        _preview = preview;
        _thumb = thumb;
        _shown = null;
        _overlays.clear();
        _faces = [];
        _facesLoaded = false;
        _frameBytes = null;
        _history
          ..clear()
          ..add(const EditState());
        _cursor = 0;
        _tool = null;
      });
      for (final i in old) {
        _retire(i);
      }
      _rerender();
    } catch (e) {
      _toast('Could not open image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------- rendering

  void _rerender() {
    final r = _renderer;
    final src = _preview;
    if (r == null || src == null || !mounted) return;
    try {
      final next = r.render(src, _current, applyCrop: _tool != Tool.crop, extras: _extras);
      final old = _shown;
      setState(() => _shown = next);
      _retire(old);
    } catch (e) {
      if (!_renderErrorShown) {
        _renderErrorShown = true;
        _toast('Render error: $e');
      }
    }
  }

  // ------------------------------------------------------------------ tools

  void _openTool(Tool t) {
    _tool = t;
    _draft = _history[_cursor];
    _paramIndex = 0;
    _aspectIndex = 0;
    _selPoint = -1;
    _band = -1;
    _textIndex = _draft.texts.isEmpty ? -1 : 0;
    _rerender();
    if (t.faces) _ensureFaces();
    if (t.kind == ToolKind.heal) _captureFrame();
  }

  void _cancelTool() {
    _tool = null;
    _rerender();
  }

  void _applyTool() {
    setState(() {
      _history.removeRange(_cursor + 1, _history.length);
      _history.add(_draft);
      _cursor++;
      _tool = null;
    });
    _rerender();
  }

  void _undo() {
    if (_cursor == 0) return;
    _cursor--;
    _rerender();
  }

  void _redo() {
    if (_cursor >= _history.length - 1) return;
    _cursor++;
    _rerender();
  }

  void _update(EditState s) {
    _draft = s;
    _rerender();
  }

  Future<void> _ensureFaces() async {
    if (_facesLoaded || _preview == null) return;
    _facesLoaded = true;
    try {
      final f = await detectFaces(_preview!);
      if (!mounted) return;
      _faces = f;
      _rerender();
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _captureFrame() async {
    final shown = _shown;
    if (shown == null) return;
    final bd = await shown.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return;
    _frameBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    _frameW = shown.width;
    _frameH = shown.height;
  }

  Size get _frameSize => Size((_shown?.width ?? 1).toDouble(), (_shown?.height ?? 1).toDouble());

  // Presets ---------------------------------------------------------------

  void _selectPreset(String key, int i) {
    final cur = _draft.presets[key];
    final next = Map<String, PresetSel>.of(_draft.presets);
    if (i == 0) {
      next.remove(key);
    } else {
      next[key] = PresetSel(i, cur?.strength ?? 1.0);
    }
    _update(_draft.copyWith(presets: next));
  }

  void _presetStrength(String key, double v) {
    final cur = _draft.presets[key];
    if (cur == null) return;
    _update(_draft.copyWith(presets: {..._draft.presets, key: PresetSel(cur.index, v)}));
  }

  // Crop ------------------------------------------------------------------

  double? get _lockedAspect {
    final o = aspects[_aspectIndex];
    if (o.ratio == null) return null;
    return o.ratio == 0 ? _frameSize.width / _frameSize.height : o.ratio;
  }

  void _selectAspect(int i) {
    setState(() => _aspectIndex = i);
    final a = _lockedAspect;
    if (a == null) return;
    _update(_draft.copyWith(crop: fitAspect(a, _frameSize)));
  }

  void _rotate(int dir) {
    _update(_draft.copyWith(quarterTurns: (_draft.quarterTurns + (dir > 0 ? 1 : 3)) % 4, crop: EditState.fullCrop));
  }

  // Generic drag-to-adjust ---------------------------------------------------

  void _onPan(DragUpdateDetails d, double width) {
    final params = _params;
    if (params.isEmpty) return;
    _dragX += d.delta.dx;
    _dragY += d.delta.dy;
    _axis ??= (_dragX.abs() + _dragY.abs() > 12)
        ? (_dragX.abs() > _dragY.abs() ? Axis.horizontal : Axis.vertical)
        : null;
    if (_axis == Axis.horizontal) {
      final p = params[_paramIndex];
      final v = _draft[p] + d.delta.dx / width * (p.max - p.min) * 1.5;
      _update(_draft.withValue(p, clampD(v, p.min, p.max)));
    } else if (_axis == Axis.vertical && _dragY.abs() > 40) {
      final next = _paramIndex + (_dragY > 0 ? 1 : -1);
      _dragY = 0;
      setState(() => _paramIndex = next < 0 ? 0 : (next >= params.length ? params.length - 1 : next));
    }
  }

  // Selective -------------------------------------------------------------

  int _hitPoint(Offset p) {
    final a = _frameSize.width / _frameSize.height;
    for (var i = 0; i < _draft.points.length; i++) {
      final q = _draft.points[i].pos;
      final dx = (p.dx - q.dx) * a, dy = p.dy - q.dy;
      if (dx * dx + dy * dy < 0.0036) return i;
    }
    return -1;
  }

  void _selTap(Offset p) {
    final hit = _hitPoint(p);
    if (hit >= 0) {
      setState(() => _selPoint = hit);
    } else if (_draft.points.length < 4) {
      _update(_draft.copyWith(points: [..._draft.points, SelPoint(pos: p)]));
      setState(() => _selPoint = _draft.points.length - 1);
    }
  }

  void _selStart(Offset p) {
    final hit = _hitPoint(p);
    if (hit >= 0) setState(() => _selPoint = hit);
  }

  void _selMove(Offset p, Offset d) {
    if (_selPoint < 0 || _selPoint >= _draft.points.length) return;
    final pts = List<SelPoint>.of(_draft.points);
    pts[_selPoint] = pts[_selPoint].copyWith(pos: p);
    _update(_draft.copyWith(points: pts));
  }

  void _selChange(SelPoint np) {
    final pts = List<SelPoint>.of(_draft.points);
    pts[_selPoint] = np;
    _update(_draft.copyWith(points: pts));
  }

  void _selDelete() {
    final pts = List<SelPoint>.of(_draft.points)..removeAt(_selPoint);
    _update(_draft.copyWith(points: pts));
    setState(() => _selPoint = pts.isEmpty ? -1 : 0);
  }

  // Brush -------------------------------------------------------------------

  void _brushStart(Offset p) {
    final layers = List<BrushLayer>.of(_draft.brush);
    if (layers.isEmpty || layers.last.mode != _brushMode) {
      if (layers.length >= 6) {
        _toast('Brush layer limit reached');
        return;
      }
      layers.add(BrushLayer(_brushMode, _brushAmount, const []));
    }
    final last = layers.last;
    layers[layers.length - 1] = last.copyWith(strokes: [...last.strokes, Stroke([p], _brushSize, _erase)]);
    _update(_draft.copyWith(brush: layers));
  }

  void _brushMove(Offset p) {
    if (_draft.brush.isEmpty || _draft.brush.last.strokes.isEmpty) return;
    final layers = List<BrushLayer>.of(_draft.brush);
    final last = layers.last;
    final strokes = List<Stroke>.of(last.strokes);
    final st = strokes.last;
    strokes[strokes.length - 1] = Stroke([...st.pts, p], st.size, st.erase);
    layers[layers.length - 1] = last.copyWith(strokes: strokes);
    _update(_draft.copyWith(brush: layers));
  }

  void _brushAmountChanged(double v) {
    setState(() => _brushAmount = v);
    if (_draft.brush.isNotEmpty && _draft.brush.last.mode == _brushMode) {
      final layers = List<BrushLayer>.of(_draft.brush);
      layers[layers.length - 1] = layers.last.copyWith(amount: v);
      _update(_draft.copyWith(brush: layers));
    }
  }

  void _brushUndo() {
    if (_draft.brush.isEmpty) return;
    final layers = List<BrushLayer>.of(_draft.brush);
    final last = layers.last;
    if (last.strokes.length <= 1) {
      layers.removeLast();
    } else {
      layers[layers.length - 1] = last.copyWith(strokes: last.strokes.sublist(0, last.strokes.length - 1));
    }
    _update(_draft.copyWith(brush: layers));
  }

  // Healing -----------------------------------------------------------------

  void _healTap(Offset p) {
    final bytes = _frameBytes;
    final src = bytes == null
        ? const Offset(0.12, 0.0)
        : pickHealSource(bytes, _frameW, _frameH, p, _healRadius);
    _update(_draft.copyWith(heal: [..._draft.heal, HealSpot(p, _healRadius, src)]));
  }

  // Text --------------------------------------------------------------------

  Future<String?> _askText([String initial = '']) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Text'),
        content: TextField(controller: ctl, autofocus: true, maxLines: 3, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _addText() async {
    final s = await _askText();
    if (s == null || s.trim().isEmpty) return;
    _update(_draft.copyWith(texts: [..._draft.texts, TextItem(text: s)]));
    setState(() => _textIndex = _draft.texts.length - 1);
  }

  Future<void> _editText() async {
    if (_textIndex < 0) return;
    final s = await _askText(_draft.texts[_textIndex].text);
    if (s == null) return;
    _changeText(_draft.texts[_textIndex].copyWith(text: s));
  }

  void _changeText(TextItem t) {
    final list = List<TextItem>.of(_draft.texts);
    list[_textIndex] = t;
    _update(_draft.copyWith(texts: list));
  }

  void _moveText(Offset d) {
    if (_textIndex < 0 || _textIndex >= _draft.texts.length) return;
    final t = _draft.texts[_textIndex];
    _changeText(t.copyWith(pos: Offset(clampD(t.pos.dx + d.dx, 0, 1), clampD(t.pos.dy + d.dy, 0, 1))));
  }

  void _deleteText() {
    final list = List<TextItem>.of(_draft.texts)..removeAt(_textIndex);
    _update(_draft.copyWith(texts: list));
    setState(() => _textIndex = list.isEmpty ? -1 : 0);
  }

  // Double exposure ---------------------------------------------------------

  Future<void> _pickOverlay() async {
    try {
      final f = await pickImageFile();
      if (f == null) return;
      setState(() => _busy = true);
      final img = await loadImage(f.bytes, f.name, maxSide: 2048);
      final id = _nextOverlay++;
      _overlays[id] = img;
      var d = _draft.copyWith(deImage: id);
      if (d[Param.deOpacity] == 0) d = d.withValue(Param.deOpacity, 0.5);
      _update(d);
    } catch (e) {
      _toast('Could not open overlay: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Fix ---------------------------------------------------------------------

  Future<void> _autoFix() async {
    final t = _thumb;
    if (t == null) return;
    final bd = await t.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return;
    final px = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    final hist = List<int>.filled(256, 0);
    var r = 0.0, g = 0.0, b = 0.0;
    final n = px.length ~/ 4;
    for (var i = 0; i < n; i++) {
      r += px[i * 4];
      g += px[i * 4 + 1];
      b += px[i * 4 + 2];
      hist[(px[i * 4] * 299 + px[i * 4 + 1] * 587 + px[i * 4 + 2] * 114) ~/ 1000]++;
    }
    if (n == 0) return;
    r /= n * 255;
    g /= n * 255;
    b /= n * 255;
    int pct(double q) {
      var acc = 0;
      for (var i = 0; i < 256; i++) {
        acc += hist[i];
        if (acc >= n * q) return i;
      }
      return 255;
    }

    final lo = pct(0.01) / 255, hi = pct(0.99) / 255;
    final mean = 0.299 * r + 0.587 * g + 0.114 * b;
    _update(_draft.withValues({
      Param.brightness: clampD((0.45 - mean) * 0.9, -0.5, 0.5),
      Param.contrast: clampD((0.85 - (hi - lo)) * 0.8, -0.2, 0.5),
      Param.wbTemp: clampD((b - r) * 1.5, -0.6, 0.6),
      Param.wbTint: clampD((g - (r + b) / 2) * 1.5, -0.5, 0.5),
      Param.vibrance: 0.2,
    }));
  }

  // ----------------------------------------------------------------- export

  Future<void> _export(ExportFormat f) async {
    final full = _full;
    final r = _renderer;
    if (full == null || r == null || _busy) return;
    setState(() => _busy = true);
    try {
      final state = _history[_cursor];
      await r.lut.ensure(state.curves);
      final out = r.render(full, state, extras: _extras);
      final bytes = await encodeExport(out, f);
      out.dispose();
      final ext = f == ExportFormat.jpeg ? 'jpg' : (f == ExportFormat.png ? 'png' : 'tif');
      final mime = f == ExportFormat.jpeg ? 'image/jpeg' : (f == ExportFormat.png ? 'image/png' : 'image/tiff');
      _toast(await platformSave(bytes, 'edit_${DateTime.now().millisecondsSinceEpoch}.$ext', mime));
    } catch (e) {
      _toast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final full = _full;
    final r = _renderer;
    if (full == null || r == null || _busy) return;
    setState(() => _busy = true);
    try {
      final state = _history[_cursor];
      await r.lut.ensure(state.curves);
      final out = r.render(full, state, extras: _extras);
      final bytes = await encodeExport(out, ExportFormat.jpeg);
      out.dispose();
      await platformShare(bytes, 'edit_${DateTime.now().millisecondsSinceEpoch}.jpg', 'image/jpeg');
    } catch (e) {
      _toast('Share failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onMenu(String v) {
    switch (v) {
      case 'open':
        _showOpen();
      case 'jpg':
        _export(ExportFormat.jpeg);
      case 'png':
        _export(ExportFormat.png);
      case 'tif':
        _export(ExportFormat.tiff);
      case 'share':
        _share();
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final editing = _preview != null;
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B1B),
        title: const Text('Penumbra'),
        actions: editing ? _actions() : null,
      ),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: editing ? _imageArea() : _welcome()),
        if (editing) _bottom(),
      ]),
    );
  }

  List<Widget> _actions() => [
        Listener(
          onPointerDown: (_) => setState(() => _comparing = true),
          onPointerUp: (_) => setState(() => _comparing = false),
          onPointerCancel: (_) => setState(() => _comparing = false),
          child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.compare)),
        ),
        if (_tool == null) ...[
          IconButton(icon: const Icon(Icons.undo), onPressed: _cursor > 0 ? _undo : null),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _cursor < _history.length - 1 ? _redo : null,
          ),
          PopupMenuButton<String>(
            onSelected: _onMenu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: Text('Open…')),
              const PopupMenuItem(value: 'jpg', child: Text('Save as JPEG')),
              const PopupMenuItem(value: 'png', child: Text('Save as PNG')),
              const PopupMenuItem(value: 'tif', child: Text('Save as TIFF')),
              if (platformCanShare) const PopupMenuItem(value: 'share', child: Text('Share')),
            ],
          ),
        ],
      ];

  Widget _welcome() {
    final ready = _renderer != null && !_busy;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.photo_library_outlined, size: 72, color: Colors.white38),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: ready ? _showOpen : null,
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Open photo'),
        ),
        const SizedBox(height: 12),
        const Text('JPEG · PNG · TIFF · DNG and other RAW', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  Widget? _overlay(Rect rect) {
    final t = _tool;
    if (t == null || _comparing) return null;
    switch (t.kind) {
      case ToolKind.crop:
        return CropOverlay(
          imageRect: rect,
          frame: _frameSize,
          crop: _draft.crop,
          aspect: _lockedAspect,
          onChanged: (r) => _update(_draft.copyWith(crop: r)),
        );
      case ToolKind.selective:
        return GestureLayer(
          rect: rect,
          onTap: _selTap,
          onStart: _selStart,
          onUpdate: _selMove,
          child: CustomPaint(painter: PointsPainter(_draft.points, _selPoint, rect), size: Size.infinite),
        );
      case ToolKind.brush:
        return GestureLayer(rect: rect, onStart: _brushStart, onUpdate: (p, d) => _brushMove(p));
      case ToolKind.heal:
        return GestureLayer(rect: rect, onTap: _healTap);
      case ToolKind.text:
        return GestureLayer(rect: rect, onUpdate: (p, d) => _moveText(d));
      case ToolKind.doubleExposure:
        return GestureLayer(
          rect: rect,
          onUpdate: (p, d) => _update(_draft.copyWith(deOffset: _draft.deOffset + d)),
        );
      case ToolKind.lensBlur:
        return GestureLayer(
          rect: rect,
          onTap: (p) => _update(_draft.copyWith(blurCenter: p)),
          onUpdate: (p, d) => _update(_draft.copyWith(blurCenter: p)),
          child: CustomPaint(painter: CenterPainter(_draft.blurCenter, rect), size: Size.infinite),
        );
      case ToolKind.vignette:
        return GestureLayer(
          rect: rect,
          onTap: (p) => _update(_draft.copyWith(vigCenter: p)),
          onUpdate: (p, d) => _update(_draft.copyWith(vigCenter: p)),
          child: CustomPaint(painter: CenterPainter(_draft.vigCenter, rect), size: Size.infinite),
        );
      default:
        return null;
    }
  }

  bool get _genericDrag {
    final t = _tool;
    if (t == null || t.params.isEmpty) return false;
    return const {
      ToolKind.params,
      ToolKind.bw,
      ToolKind.fix,
      ToolKind.expand,
      ToolKind.frames,
    }.contains(t.kind);
  }

  Widget _imageArea() {
    final img = _comparing ? _preview : _shown;
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      Widget content;
      if (img == null) {
        content = const Center(child: CircularProgressIndicator());
      } else {
        final imgSize = Size(img.width.toDouble(), img.height.toDouble());
        final rect = fitRect(size, imgSize, padding: 12);
        final overlay = _overlay(rect);
        final params = _params;
        content = SizedBox.expand(
          child: Stack(children: [
            Positioned.fromRect(
              rect: rect,
              child: RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            ),
            if (overlay != null) Positioned.fill(child: overlay),
            if (_genericDrag && !_comparing)
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Text(
                          '${params[_paramIndex < params.length ? _paramIndex : 0].label}  '
                          '${fmtParam(params[_paramIndex < params.length ? _paramIndex : 0], _draft[params[_paramIndex < params.length ? _paramIndex : 0]])}',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        );
      }
      final drag = _genericDrag;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: drag
            ? (_) {
                _dragX = 0;
                _dragY = 0;
                _axis = null;
              }
            : null,
        onPanUpdate: drag ? (d) => _onPan(d, size.width) : null,
        child: content,
      );
    });
  }

  Widget _bottom() => _tool == null ? _mainBar() : _toolPanel();

  Widget _mainBar() {
    return Container(
      color: const Color(0xFF1B1B1B),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton.icon(
              onPressed: () => _openTool(Tool.style),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('STYLE'),
            ),
            FilledButton.tonalIcon(
              onPressed: _showTools,
              icon: const Icon(Icons.apps),
              label: const Text('TOOLS'),
            ),
            PopupMenuButton<String>(
              onSelected: _onMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'jpg', child: Text('Save as JPEG')),
                const PopupMenuItem(value: 'png', child: Text('Save as PNG')),
                const PopupMenuItem(value: 'tif', child: Text('Save as TIFF')),
                if (platformCanShare) const PopupMenuItem(value: 'share', child: Text('Share')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.ios_share), SizedBox(width: 6), Text('EXPORT')]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showTools() async {
    final t = await showModalBottomSheet<Tool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.92,
        builder: (c, sc) => GridView.count(
          controller: sc,
          crossAxisCount: 4,
          childAspectRatio: 0.95,
          padding: const EdgeInsets.all(8),
          children: [
            for (final t in Tool.values)
              InkWell(
                onTap: () => Navigator.pop(ctx, t),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(t.icon, size: 28),
                  const SizedBox(height: 6),
                  Text(t.label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center, maxLines: 2),
                ]),
              ),
          ],
        ),
      ),
    );
    if (t != null) _openTool(t);
  }

  Widget _paramPanel(Tool tool) => ParamPanel(
        params: tool.params,
        state: _draft,
        selected: _paramIndex,
        onSelect: (i) => setState(() => _paramIndex = i),
        onChanged: (p, v) => _update(_draft.withValue(p, v)),
      );

  Widget _toolPanel() {
    final tool = _tool!;
    final key = tool.presetKey;
    Widget body;
    switch (tool.kind) {
      case ToolKind.curves:
        body = CurvesPanel(
          curves: _draft.curves,
          channel: _curveChannel,
          onChannel: (i) => setState(() => _curveChannel = i),
          onChanged: (c) => _update(_draft.copyWith(curves: c)),
        );
      case ToolKind.color:
        body = ColorPanel(
          state: _draft,
          band: _band,
          onBand: (i) => setState(() => _band = i),
          onChanged: (p, v) => _update(_draft.withValue(p, v)),
        );
      case ToolKind.selective:
        body = SelectivePanel(
          points: _draft.points,
          selected: _selPoint,
          onSelect: (i) => setState(() => _selPoint = i),
          onChange: _selChange,
          onDelete: _selDelete,
        );
      case ToolKind.brush:
        body = BrushPanel(
          mode: _brushMode,
          onMode: (i) => setState(() => _brushMode = i),
          size: _brushSize,
          onSize: (v) => setState(() => _brushSize = v),
          amount: _brushAmount,
          onAmount: _brushAmountChanged,
          erase: _erase,
          onErase: (v) => setState(() => _erase = v),
          onUndo: _brushUndo,
          onClear: () => _update(_draft.copyWith(brush: const [])),
        );
      case ToolKind.heal:
        body = HealPanel(
          radius: _healRadius,
          onRadius: (v) => setState(() => _healRadius = v),
          count: _draft.heal.length,
          onUndo: () => _update(_draft.copyWith(heal: _draft.heal.sublist(0, _draft.heal.length - 1))),
          onClear: () => _update(_draft.copyWith(heal: const [])),
        );
      case ToolKind.text:
        body = TextPanel(
          items: _draft.texts,
          selected: _textIndex,
          onSelect: (i) => setState(() => _textIndex = i),
          onAdd: _addText,
          onEdit: _editText,
          onChange: _changeText,
          onDelete: _deleteText,
        );
      case ToolKind.crop:
        body = CropPanel(
          selected: _aspectIndex,
          onSelect: _selectAspect,
          onRotate: _rotate,
          onFlip: () => _update(_draft.copyWith(flipH: !_draft.flipH, crop: EditState.fullCrop)),
        );
      case ToolKind.expand:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          ChipRow(
            labels: expandFillNames,
            selected: _draft.expandFill,
            onSelect: (i) => _update(_draft.copyWith(expandFill: i)),
          ),
          _paramPanel(tool),
        ]);
      case ToolKind.frames:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          ChipRow(
            labels: frameNames,
            selected: _draft.frameStyle,
            onSelect: (i) => _update(_draft.copyWith(frameStyle: i)),
          ),
          SwatchRow(selected: _draft.frameColor, onSelect: (c) => _update(_draft.copyWith(frameColor: c))),
          _paramPanel(tool),
        ]);
      case ToolKind.doubleExposure:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton.tonalIcon(
              onPressed: _pickOverlay,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(_draft.deImage < 0 ? 'Choose second photo' : 'Change second photo'),
            ),
          ),
          ChipRow(labels: blendNames, selected: _draft.deBlend, onSelect: (i) => _update(_draft.copyWith(deBlend: i))),
          _paramPanel(tool),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Drag on the photo to move the second image.', style: TextStyle(fontSize: 12, color: Colors.white54)),
          ),
        ]);
      case ToolKind.bw:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          ChipRow(
            labels: ['Color', ...[for (final m in const ['Neutral', 'Red', 'Orange', 'Yellow', 'Green', 'Blue']) m]],
            selected: _draft.mono + 1,
            onSelect: (i) => _update(_draft.copyWith(mono: i - 1)),
          ),
          _paramPanel(tool),
        ]);
      case ToolKind.fix:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton.tonalIcon(
              onPressed: _autoFix,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Auto fix'),
            ),
          ),
          _paramPanel(tool),
        ]);
      case ToolKind.lensBlur:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          ChipRow(
            labels: const ['Elliptical', 'Linear'],
            selected: _draft.blurShape,
            onSelect: (i) => _update(_draft.copyWith(blurShape: i)),
          ),
          _paramPanel(tool),
        ]);
      case ToolKind.vignette:
      case ToolKind.params:
      case ToolKind.rotate:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          if (key != null)
            PresetPanel(
              key: ValueKey('presets-$key'),
              renderer: _renderer!,
              thumb: _thumb!,
              base: _history[_cursor],
              extras: _extras,
              presetKey: key,
              selected: _draft.presets[key]?.index ?? 0,
              strength: _draft.presets[key]?.strength ?? 1.0,
              onSelect: (i) => _selectPreset(key, i),
              onStrength: (v) => _presetStrength(key, v),
            ),
          if (tool.params.isNotEmpty) _paramPanel(tool),
          if (tool.faces && _facesLoaded && _faces.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                tool == Tool.headPose
                    ? 'No face detected. Head Pose needs face detection (Android or iOS).'
                    : 'No face detected: smoothing applies to skin tones across the photo.',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ),
        ]);
    }
    return Container(
      color: const Color(0xFF1B1B1B),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: SingleChildScrollView(child: body),
          ),
          Row(children: [
            IconButton(icon: const Icon(Icons.close), onPressed: _cancelTool),
            Expanded(child: Center(child: Text(tool.label))),
            IconButton(icon: const Icon(Icons.check), onPressed: _applyTool),
          ]),
        ]),
      ),
    );
  }
}
