import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'faces.dart';

/// Face detection via ML Kit (Android and iOS only; empty elsewhere).
Future<List<FaceData>> detectFaces(ui.Image preview) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return const [];
  final data = await preview.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) return const [];
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/face_probe.png');
  await file.writeAsBytes(data.buffer.asUint8List());
  final detector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  try {
    final faces = await detector.processImage(InputImage.fromFilePath(file.path));
    final w = preview.width.toDouble();
    final h = preview.height.toDouble();
    ui.Offset? lm(Face f, FaceLandmarkType t) {
      final p = f.landmarks[t]?.position;
      return p == null ? null : ui.Offset(p.x / w, p.y / h);
    }

    final out = <FaceData>[
      for (final f in faces)
        FaceData(
          box: ui.Rect.fromLTRB(
            f.boundingBox.left / w,
            f.boundingBox.top / h,
            f.boundingBox.right / w,
            f.boundingBox.bottom / h,
          ),
          leftEye: lm(f, FaceLandmarkType.leftEye),
          rightEye: lm(f, FaceLandmarkType.rightEye),
          mouthLeft: lm(f, FaceLandmarkType.leftMouth),
          mouthRight: lm(f, FaceLandmarkType.rightMouth),
          mouthBottom: lm(f, FaceLandmarkType.bottomMouth),
          nose: lm(f, FaceLandmarkType.noseBase),
          leftCheek: lm(f, FaceLandmarkType.leftCheek),
          rightCheek: lm(f, FaceLandmarkType.rightCheek),
        ),
    ];
    out.sort((a, b) => (b.box.width * b.box.height).compareTo(a.box.width * a.box.height));
    return out;
  } finally {
    await detector.close();
  }
}
