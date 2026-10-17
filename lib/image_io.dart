import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;

import 'codecs/tiff_dng.dart';

class PickedFile {
  const PickedFile(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

enum ExportFormat { jpeg, png, tiff }

const rawExts = [
  'dng', 'cr2', 'cr3', 'crw', 'nef', 'nrw', 'arw', 'sr2', 'srf', 'orf', 'rw2', 'raf', 'pef',
  'srw', '3fr', 'iiq', 'erf', 'mef', 'mos', 'kdc', 'dcr', 'rwl', 'raw', 'x3f',
];
const _stdExts = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'heic', 'heif', 'tif', 'tiff'];

/// Opens the system file dialog. Works on every Flutter platform.
Future<PickedFile?> pickImageFile() async {
  final groups = <XTypeGroup>[
    XTypeGroup(
      label: 'Images and RAW',
      extensions: [..._stdExts, ...rawExts],
      mimeTypes: const ['image/*', 'image/tiff', 'image/x-adobe-dng', 'image/dng'],
      uniformTypeIdentifiers: const ['public.image', 'public.camera-raw-image', 'public.tiff'],
    ),
    const XTypeGroup(label: 'All files'),
  ];
  final f = await openFile(acceptedTypeGroups: groups);
  if (f == null) return null;
  return PickedFile(await f.readAsBytes(), f.name);
}

Future<ui.Image> _decodeEngine(Uint8List bytes, int maxSide) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final desc = await ui.ImageDescriptor.encoded(buffer);
    int? tw;
    int? th;
    if (math.max(desc.width, desc.height) > maxSide) {
      if (desc.width >= desc.height) {
        tw = maxSide;
      } else {
        th = maxSide;
      }
    }
    final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    return frame.image;
  } finally {
    buffer.dispose();
  }
}

Future<ui.Image> _fromRgba(RgbaImage r) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(r.rgba, r.width, r.height, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<ui.Image> _finish(RgbaImage r, int maxSide) async {
  final img = await _fromRgba(r);
  return scaleToMax(img, maxSide, disposeSrc: true);
}

ui.Image rotateByOrientation(ui.Image src, int orientation) {
  if (orientation != 3 && orientation != 6 && orientation != 8) return src;
  final w = src.width, h = src.height;
  final swap = orientation != 3;
  final ow = swap ? h : w, oh = swap ? w : h;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.translate(ow / 2, oh / 2);
  c.rotate(orientation == 3 ? math.pi : (orientation == 6 ? math.pi / 2 : -math.pi / 2));
  c.translate(-w / 2, -h / 2);
  c.drawImage(src, ui.Offset.zero, ui.Paint());
  final pic = rec.endRecording();
  final out = pic.toImageSync(ow, oh);
  pic.dispose();
  src.dispose();
  return out;
}

/// Downscales so the longest side is <= [maxSide]. Always returns an image the
/// caller owns (a clone when no scaling is needed).
ui.Image scaleToMax(ui.Image src, int maxSide, {bool disposeSrc = false}) {
  var cur = src;
  var owned = disposeSrc;
  while (math.max(cur.width, cur.height) > maxSide) {
    final big = math.max(cur.width, cur.height);
    final k = math.max(maxSide / big, 0.5);
    final w = math.max(1, (cur.width * k).round());
    final h = math.max(1, (cur.height * k).round());
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawImageRect(
      cur,
      ui.Rect.fromLTWH(0, 0, cur.width.toDouble(), cur.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final pic = rec.endRecording();
    final next = pic.toImageSync(w, h);
    pic.dispose();
    if (owned) cur.dispose();
    cur = next;
    owned = true;
  }
  return owned ? cur : cur.clone();
}

Future<ui.Image> _loadPreview(Uint8List bytes, int maxSide, int orientation) async {
  final cands = await compute(previewEntry, bytes);
  for (final c in cands) {
    try {
      final img = await _decodeEngine(Uint8List.fromList(c), maxSide);
      return rotateByOrientation(img, orientation);
    } catch (_) {}
  }
  throw const FormatException('No readable image or embedded preview found in this file.');
}

/// Decodes JPEG, PNG, WebP, GIF, BMP, HEIC (platform permitting), TIFF, DNG and
/// the embedded previews of other RAW formats into a [ui.Image] <= [maxSide].
Future<ui.Image> loadImage(Uint8List bytes, String name, {int maxSide = 4096}) async {
  final kind = sniffFormat(bytes);
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (kind) {
    case 'jpeg':
    case 'png':
    case 'webp':
    case 'gif':
    case 'bmp':
    case 'heic':
      return _decodeEngine(bytes, maxSide);
    case 'tiff':
      final probe = probeTiff(bytes);
      final rawLike = probe.isDng || probe.isRawLike || rawExts.contains(ext);
      if (probe.isDng) {
        final r = await compute(decodeDngEntry, DecodeRequest(bytes, maxSide));
        if (r != null) return _finish(r, maxSide);
      }
      if (!rawLike) {
        final r = await compute(decodeTiffEntry, DecodeRequest(bytes, maxSide));
        if (r != null) return _finish(r, maxSide);
      }
      return _loadPreview(bytes, maxSide, probe.orientation);
    default:
      try {
        return await _decodeEngine(bytes, maxSide);
      } catch (_) {
        return _loadPreview(bytes, maxSide, 1);
      }
  }
}

Future<Uint8List> encodeExport(ui.Image img, ExportFormat f, {int quality = 92}) async {
  if (f == ExportFormat.png) {
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    return d!.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  }
  final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = raw!.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
  return compute(
    encodeEntry,
    EncodeRequest(bytes, img.width, img.height, f == ExportFormat.jpeg ? 'jpeg' : 'tiff', quality),
  );
}
