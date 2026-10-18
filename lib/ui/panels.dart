import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../edit_state.dart';
import '../image_io.dart';
import '../models.dart';
import '../params.dart';
import '../presets.dart';
import '../renderer.dart';
import 'widgets.dart';

class ParamPanel extends StatelessWidget {
  const ParamPanel({
    super.key,
    required this.params,
    required this.state,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final List<Param> params;
  final EditState state;
  final int selected;
  final ValueChanged<int> onSelect;
  final void Function(Param, double) onChanged;

  @override
  Widget build(BuildContext context) {
    final i = math.min(selected, params.length - 1);
    final p = params[i];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (params.length > 1)
        ChipRow(labels: [for (final q in params) q.label], selected: i, onSelect: onSelect),
      LabeledSlider(
        label: p.label,
        value: state[p],
        min: p.min,
        max: p.max,
        display: fmtParam(p, state[p]),
        onChanged: (v) => onChanged(p, v),
      ),
    ]);
  }
}

class SwatchRow extends StatelessWidget {
  const SwatchRow({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final c in swatches)
            GestureDetector(
              onTap: () => onSelect(c),
              child: Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: selected == c ? Colors.tealAccent : Colors.white38, width: selected == c ? 3 : 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AspectOption {
  const AspectOption(this.label, this.ratio);
  final String label;

  /// null = free, 0 = original, otherwise w/h.
  final double? ratio;
}

const aspects = <AspectOption>[
  AspectOption('Free', null),
  AspectOption('Original', 0),
  AspectOption('1:1', 1),
  AspectOption('4:3', 4 / 3),
  AspectOption('3:4', 3 / 4),
  AspectOption('16:9', 16 / 9),
  AspectOption('9:16', 9 / 16),
];

class CropPanel extends StatelessWidget {
  const CropPanel({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onRotate,
    required this.onFlip,
  });
  final int selected;
  final ValueChanged<int> onSelect;

  /// +1 = clockwise, -1 = counter-clockwise.
  final ValueChanged<int> onRotate;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        IconButton(icon: const Icon(Icons.rotate_left), onPressed: () => onRotate(-1)),
        IconButton(icon: const Icon(Icons.rotate_right), onPressed: () => onRotate(1)),
        IconButton(icon: const Icon(Icons.flip), onPressed: onFlip),
      ]),
      ChipRow(labels: [for (final a in aspects) a.label], selected: selected, onSelect: onSelect),
    ]);
  }
}

class PresetPanel extends StatefulWidget {
  const PresetPanel({
    super.key,
    required this.renderer,
    required this.thumb,
    required this.base,
    this.extras = const RenderExtras(),
    required this.presetKey,
    required this.selected,
    required this.strength,
    required this.onSelect,
    required this.onStrength,
  });

  final Renderer renderer;
  final ui.Image thumb;

  /// The edits already applied to the photo. Every preview is this state with
  /// one preset swapped in, so previews match what the photo looks like now.
  final EditState base;
  final RenderExtras extras;
  final String presetKey;
  final int selected;
  final double strength;
  final ValueChanged<int> onSelect;
  final ValueChanged<double> onStrength;

  @override
  State<PresetPanel> createState() => _PresetPanelState();
}

class _PresetPanelState extends State<PresetPanel> {
  late final List<Preset> _bank = presetBank[widget.presetKey]!;
  late final List<ui.Image?> _thumbs = List<ui.Image?>.filled(_bank.length, null);
  ui.Image? _src;
  EditState? _base;
  final List<int> _queue = [];
  final Set<int> _failed = {};
  bool _pumping = false;
  bool _disposed = false;

  /// Called from itemBuilder, so only tiles the list actually builds (the
  /// visible ones plus a little margin) are ever rendered.
  void _request(int i) {
    if (_thumbs[i] != null || _failed.contains(i) || _queue.contains(i)) return;
    _queue.add(i);
    if (!_pumping) _pump();
  }

  /// Renders one preview per frame so opening the panel never blocks the UI
  /// (each render is several synchronous GPU passes, which is slow on web).
  Future<void> _pump() async {
    _pumping = true;
    while (_queue.isNotEmpty) {
      await WidgetsBinding.instance.endOfFrame;
      if (_disposed || !mounted || _queue.isEmpty) break;
      final i = _queue.removeAt(0);
      // Small source: tiles are ~66 logical px, so 128 px is plenty.
      _src ??= scaleToMax(widget.thumb, 128);
      // Previews show the global look. Local layers (heal, brush, text, frame,
      // double exposure) are skipped: they cost the most and barely change a tile.
      final base = _base ??= widget.base.copyWith(
        heal: const [],
        brush: const [],
        texts: const [],
        points: const [],
        frameStyle: 0,
        deImage: -1,
      );
      try {
        final img = widget.renderer.render(
          _src!,
          base.copyWith(presets: {...base.presets, widget.presetKey: PresetSel(i, 1.0)}),
          extras: widget.extras,
        );
        setState(() => _thumbs[i] = img);
      } catch (_) {
        _failed.add(i); // Leave this tile as a placeholder.
      }
    }
    _pumping = false;
  }

  @override
  void dispose() {
    _disposed = true;
    final t = [..._thumbs, _src];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final i in t) {
        i?.dispose();
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: _bank.length,
          itemBuilder: (_, i) {
            _request(i);
            return GestureDetector(
            onTap: () => widget.onSelect(i),
            child: Container(
              width: 72,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: widget.selected == i ? accent : Colors.transparent, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: _thumbs[i] == null
                        ? const ColoredBox(color: Colors.white10)
                        : RawImage(image: _thumbs[i], fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 3),
                Text(_bank[i].name, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            );
          },
        ),
      ),
      if (widget.selected > 0)
        LabeledSlider(
          label: 'Strength',
          value: widget.strength,
          min: 0,
          max: 1,
          display: '${(widget.strength * 100).round()}',
          onChanged: widget.onStrength,
        ),
    ]);
  }
}
