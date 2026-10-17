import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../edit_state.dart';
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
    required this.presetKey,
    required this.selected,
    required this.strength,
    required this.onSelect,
    required this.onStrength,
  });

  final Renderer renderer;
  final ui.Image thumb;
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
  late final List<ui.Image> _thumbs = [
    for (var i = 0; i < _bank.length; i++)
      widget.renderer.render(widget.thumb, EditState(presets: {widget.presetKey: PresetSel(i, 1.0)})),
  ];

  @override
  void dispose() {
    final t = _thumbs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final i in t) {
        i.dispose();
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
          itemBuilder: (_, i) => GestureDetector(
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
                    child: RawImage(image: _thumbs[i], fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 3),
                Text(_bank[i].name, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
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
