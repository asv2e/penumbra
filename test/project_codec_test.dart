import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:penumbra/edit_state.dart';
import 'package:penumbra/lut.dart';
import 'package:penumbra/models.dart';
import 'package:penumbra/params.dart';
import 'package:penumbra/project_codec.dart';

void main() {
  test('every param has a unique id', () {
    expect(Param.byId.length, Param.all.length);
  });

  test('edit state survives a JSON round trip', () {
    final s = const EditState().copyWith(
      values: {Param.brightness: 0.25, Param.hslHue[2]: -0.4, Param.straighten: 7.5},
      presets: {'style': const PresetSel(1, 0.6)},
      mono: 2,
      curves: const CurveSet().withChannel(0, const [Offset(0, 0), Offset(0.4, 0.3), Offset(1, 1)]),
      crop: const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
      quarterTurns: 3,
      flipH: true,
      points: [const SelPoint(pos: Offset(0.3, 0.4), brightness: 0.2)],
      brush: [
        const BrushLayer(1, 0.5, [
          Stroke([Offset(0.1, 0.1), Offset(0.2, 0.25)], 0.05, false),
        ]),
      ],
      heal: [const HealSpot(Offset(0.5, 0.5), 0.04, Offset(0.1, 0.0))],
      texts: [const TextItem(text: 'Hello', color: 0xFFE53935)],
      frameStyle: 3,
      deImage: 2,
      deOffset: const Offset(0.05, -0.02),
    );
    final first = jsonEncode(editToJson(s));
    final back = editFromJson(jsonDecode(first) as Map<String, dynamic>);
    expect(jsonEncode(editToJson(back)), first);
    expect(back[Param.brightness], 0.25);
    expect(back.texts.single.text, 'Hello');
    expect(back.brush.single.strokes.single.pts.length, 2);
  });

  test('bad or unknown data falls back to defaults', () {
    final s = editFromJson({'values': {'nope': 1, 'brightness': 9}, 'crop': [1, 1, 0, 0], 'curves': 5});
    expect(s[Param.brightness], 1.0);
    expect(s.crop, EditState.fullCrop);
    expect(s.curves.isIdentity, isTrue);
  });
}
