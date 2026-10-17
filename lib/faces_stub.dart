import 'dart:ui' as ui;

import 'faces.dart';

/// Web / unsupported platforms: no face detection.
Future<List<FaceData>> detectFaces(ui.Image preview) async => const [];
