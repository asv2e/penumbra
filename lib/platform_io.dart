import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'image_io.dart';

bool get _mobile => Platform.isAndroid || Platform.isIOS;

bool get platformHasPhotoPicker => _mobile;
bool get platformCanShare => _mobile || Platform.isMacOS;

Future<PickedFile?> platformPickPhoto({required bool camera}) async {
  final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery);
  if (x == null) return null;
  return PickedFile(await x.readAsBytes(), x.name);
}

Future<void> platformShare(Uint8List bytes, String name, String mime) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path, mimeType: mime)]);
}

Future<String> platformSave(Uint8List bytes, String name, String mime) async {
  if (_mobile) {
    if (mime == 'image/png' || mime == 'image/jpeg') {
      await Gal.putImageBytes(bytes, album: 'Penumbra');
      return 'Saved to your photo library';
    }
    await platformShare(bytes, name, mime);
    return 'Shared $name';
  }
  final ext = name.split('.').last;
  final loc = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
  );
  if (loc == null) return 'Save cancelled';
  await File(loc.path).writeAsBytes(bytes);
  return 'Saved to ${loc.path}';
}
