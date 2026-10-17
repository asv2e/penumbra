import 'package:flutter/material.dart';

import '../edit_state.dart';
import '../params.dart';
import 'widgets.dart';

class ColorPanel extends StatelessWidget {
  const ColorPanel({
    super.key,
    required this.state,
    required this.band,
    required this.onBand,
    required this.onChanged,
  });
  final EditState state;

  /// -1 = global (vibrance, hue shift), 0..7 = colour band.
  final int band;
  final ValueChanged<int> onBand;
  final void Function(Param, double) onChanged;

  static const _dots = [
    Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFDD835), Color(0xFF43A047),
    Color(0xFF00ACC1), Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFFEC407A),
  ];

  Widget _slider(Param p, String label) => LabeledSlider(
        label: label,
        value: state[p],
        min: p.min,
        max: p.max,
        display: fmtParam(p, state[p]),
        onChanged: (v) => onChanged(p, v),
      );

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: const Text('All'), selected: band < 0, onSelected: (_) => onBand(-1)),
            ),
            for (var i = 0; i < 8; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: CircleAvatar(radius: 7, backgroundColor: _dots[i]),
                  label: Text(Param.hslNames[i]),
                  selected: band == i,
                  onSelected: (_) => onBand(i),
                ),
              ),
          ],
        ),
      ),
      if (band < 0) ...[
        _slider(Param.vibrance, 'Vibrance'),
        _slider(Param.hueShift, 'Hue shift'),
      ] else ...[
        _slider(Param.hslHue[band], 'Hue'),
        _slider(Param.hslSat[band], 'Saturation'),
        _slider(Param.hslLum[band], 'Luminance'),
      ],
    ]);
  }
}
