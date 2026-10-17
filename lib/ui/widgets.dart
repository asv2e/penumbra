import 'package:flutter/material.dart';

import '../edit_state.dart';
import '../params.dart';

String fmtParam(Param p, double v) {
  if (p.max > 2) return '${v.round()}°';
  final n = (v * 100).round();
  return n > 0 && p.min < 0 ? '+$n' : '$n';
}

class ChipRow extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.height = 48,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ChoiceChip(
          label: Text(labels[i]),
          selected: i == selected,
          onSelected: (_) => onSelect(i),
        ),
      ),
    );
  }
}

class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? display;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(display ?? value.toStringAsFixed(2), style: const TextStyle(fontSize: 13)),
        ]),
      ),
      SizedBox(
        height: 32,
        child: Slider(value: clampD(value, min, max), min: min, max: max, onChanged: onChanged),
      ),
    ]);
  }
}

/// Converts pointer positions inside [rect] into normalised image coordinates.
class GestureLayer extends StatelessWidget {
  const GestureLayer({
    super.key,
    required this.rect,
    this.onTap,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.child,
  });
  final Rect rect;
  final ValueChanged<Offset>? onTap;
  final ValueChanged<Offset>? onStart;
  final void Function(Offset pos, Offset delta)? onUpdate;
  final VoidCallback? onEnd;
  final Widget? child;

  Offset _n(Offset p) => Offset(
        clampD((p.dx - rect.left) / rect.width, 0, 1),
        clampD((p.dy - rect.top) / rect.height, 0, 1),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onTap == null ? null : (d) => onTap!(_n(d.localPosition)),
      onPanStart: onStart == null ? null : (d) => onStart!(_n(d.localPosition)),
      onPanUpdate: onUpdate == null
          ? null
          : (d) => onUpdate!(
                _n(d.localPosition),
                Offset(d.delta.dx / rect.width, d.delta.dy / rect.height),
              ),
      onPanEnd: onEnd == null ? null : (_) => onEnd!(),
      child: child ?? const SizedBox.expand(),
    );
  }
}
