import 'package:flutter/material.dart';

import 'camera_page.dart';
import 'image_io.dart';
import 'platform_api.dart';

/// Asks where to get a photo from (files, photo library, camera) and returns
/// it, or null if the person cancelled or it could not be read.
Future<PickedImage?> choosePhoto(BuildContext context) async {
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
        if (platformHasPhotoPicker || platformHasInAppCamera)
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
      ]),
    ),
  );
  if (choice == null) return null;
  try {
    if (choice == 'file') return await pickImageFile();
    if (choice == 'camera' && !platformHasPhotoPicker) {
      // Web and desktop: capture inside the app.
      return await Navigator.of(context).push<PickedImage>(
        MaterialPageRoute(builder: (_) => const CameraCapturePage()),
      );
    }
    return await platformPickPhoto(camera: choice == 'camera');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
    }
    return null;
  }
}

/// File name without its extension, for naming a new project.
String baseName(String fileName) {
  final slash = fileName.lastIndexOf(RegExp(r'[/\\]'));
  final n = slash >= 0 ? fileName.substring(slash + 1) : fileName;
  final dot = n.lastIndexOf('.');
  final out = dot > 0 ? n.substring(0, dot) : n;
  return out.isEmpty ? 'Untitled' : out;
}
