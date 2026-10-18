import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'image_io.dart';

/// Browser-native camera capture for the web build.
///
/// Do not use camera.availableCameras() here: camera_web opens every enumerated
/// input while probing it, so one inactive/virtual device can break the whole
/// scan even if the default webcam is healthy. getUserMedia() opens the chosen
/// camera directly; optional camera enumeration happens only after that works.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  static int _nextViewId = 0;

  late final String _viewType;
  late final html.VideoElement _video;
  html.MediaStream? _stream;
  List<html.MediaDeviceInfo> _devices = [];
  String? _selectedDeviceId;
  String? _error;
  bool _starting = true;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'penumbra-camera-preview-${_nextViewId++}';
    _video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000000';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
    _start();
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  void _stopStream() {
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
    }
    _video.srcObject = null;
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('NotReadableError') ||
        message.contains('TrackStartError') ||
        message.contains('cameraNotReadable')) {
      return 'Chromium was allowed to use the camera, but Windows could not start it. '
          'Close apps that may already be using the webcam (Camera, Teams, Discord, '
          'OBS, or similar), then tap Retry. An inactive virtual camera can also '
          'cause this error.';
    }
    if (message.contains('NotAllowedError') ||
        message.contains('PermissionDeniedError')) {
      return 'Camera access was blocked. Allow camera access for this site in '
          'Chromium and make sure Windows camera privacy settings allow desktop apps.';
    }
    if (message.contains('NotFoundError') ||
        message.contains('DevicesNotFoundError')) {
      return 'No usable camera was found. Connect or enable a webcam, then tap Retry.';
    }
    if (message.contains('OverconstrainedError')) {
      return 'That camera could not be opened with the requested settings. Try another camera.';
    }
    if (message.contains('mediaDevices') || message.contains('insecure')) {
      return 'The browser camera API is unavailable. Open Penumbra over HTTPS or at localhost.';
    }
    return 'Could not start the camera: $message';
  }

  Future<html.MediaStream> _requestStream(
    html.MediaDevices mediaDevices,
    String? deviceId,
  ) {
    final videoConstraints = <String, dynamic>{
      'width': <String, dynamic>{'ideal': 1920},
      'height': <String, dynamic>{'ideal': 1080},
      if (deviceId != null && deviceId.isNotEmpty)
        'deviceId': <String, dynamic>{'exact': deviceId},
    };
    return mediaDevices.getUserMedia(<String, dynamic>{
      'audio': false,
      'video': videoConstraints,
    });
  }

  bool _canTryAnotherCamera(Object error) {
    final message = error.toString();
    return message.contains('NotReadableError') ||
        message.contains('TrackStartError') ||
        message.contains('cameraNotReadable');
  }

  Future<void> _start({String? deviceId}) async {
    if (mounted) {
      setState(() {
        _starting = true;
        _error = null;
      });
    }
    _stopStream();

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw StateError('Camera API unavailable; use HTTPS or localhost.');
      }

      html.MediaStream? stream;
      String? activeDeviceId = deviceId;
      Object? initialError;
      try {
        stream = await _requestStream(mediaDevices, deviceId);
      } catch (error) {
        initialError = error;
      }

      // If Chromium's default camera is an inactive virtual device, try the
      // listed physical/virtual inputs one at a time and skip devices that fail
      // to start. This is deliberately separate from availableCameras(), whose
      // all-or-nothing probe is the source of the reported failure.
      if (stream == null && deviceId == null && initialError != null &&
          _canTryAnotherCamera(initialError)) {
        try {
          final candidates = (await mediaDevices.enumerateDevices())
              .where((d) => d.kind == 'videoinput' && (d.deviceId ?? '').isNotEmpty)
              .toList();
          for (final candidate in candidates) {
            try {
              stream = await _requestStream(mediaDevices, candidate.deviceId);
              activeDeviceId = candidate.deviceId;
              break;
            } catch (_) {
              // Ignore unavailable or busy devices and try the next input.
            }
          }
        } catch (_) {
          // Keep the original, more useful error below.
        }
      }
      if (stream == null) throw initialError ?? StateError('No usable camera found.');

      if (!mounted) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        return;
      }

      _stream = stream;
      _selectedDeviceId = activeDeviceId;
      _video.srcObject = stream;
      await _video.play();

      // Enumerate after capture has started. Unusable devices remain listed,
      // but they can no longer prevent the default working camera from opening.
      var devices = <html.MediaDeviceInfo>[];
      try {
        devices = (await mediaDevices.enumerateDevices())
            .where((d) => d.kind == 'videoinput' && (d.deviceId ?? '').isNotEmpty)
            .toList();
      } catch (_) {
        // A working video stream is enough for capture; device switching is optional.
      }

      if (!mounted) return;
      setState(() {
        _devices = devices;
        _starting = false;
      });
    } catch (error) {
      _stopStream();
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _starting = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_devices.length < 2 || _starting || _taking) return;
    final currentIndex = _devices.indexWhere(
      (device) => device.deviceId == _selectedDeviceId,
    );
    final nextIndex = (currentIndex + 1) % _devices.length;
    await _start(deviceId: _devices[nextIndex].deviceId);
  }

  Future<void> _shoot() async {
    if (_stream == null || _starting || _taking) return;
    if (_video.videoWidth == 0 || _video.videoHeight == 0) {
      setState(() => _error = 'The camera is still starting. Try again in a moment.');
      return;
    }

    setState(() => _taking = true);
    try {
      final canvas = html.CanvasElement(
        width: _video.videoWidth,
        height: _video.videoHeight,
      );
      canvas.context2D.drawImage(_video, 0, 0);
      final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
      final comma = dataUrl.indexOf(',');
      if (comma < 0) throw StateError('Could not encode the camera image.');
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      if (mounted) {
        Navigator.of(context).pop(
          PickedImage(Uint8List.fromList(bytes), 'Camera photo.jpg'),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not capture photo: $error');
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Camera'),
        actions: [
          if (_devices.length > 1)
            IconButton(
              tooltip: 'Switch camera',
              onPressed: _starting || _taking ? null : _switchCamera,
              icon: const Icon(Icons.cameraswitch),
            ),
          IconButton(
            tooltip: 'Retry camera',
            onPressed: _starting || _taking ? null : () => _start(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                HtmlElementView(viewType: _viewType),
                if (_starting)
                  const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  ColoredBox(
                    color: Colors.black87,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: GestureDetector(
                onTap: _stream == null || _starting || _taking ? null : _shoot,
                child: Opacity(
                  opacity: _stream == null || _starting ? 0.4 : 1,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _taking ? Colors.white54 : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
