import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;

import 'image_io.dart';

/// Web: downloads only.
bool get platformHasPhotoPicker => false;
bool get platformCanShare => false;

Future<PickedImage?> platformPickPhoto({required bool camera}) async => null;

Future<String> platformSave(Uint8List bytes, String name, String mime) async {
  final f = XFile.fromData(bytes, mimeType: mime, name: name);
  await f.saveTo(name);
  return 'Download started: $name';
}

Future<void> platformShare(Uint8List bytes, String name, String mime) async {}
