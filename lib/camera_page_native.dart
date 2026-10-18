import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'image_io.dart';

/// Takes one photo with the device camera and returns it as a [PickedImage].
/// Used on web and desktop; phones use the system camera instead.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  List<CameraDescription> _cams = [];
  int _index = 0;
  CameraController? _ctl;
  String? _error;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        _fail('No camera found.');
        return;
      }
      await _open(0);
    } on CameraException catch (e) {
      _fail(_describe(e));
    } catch (e) {
      _fail('$e');
    }
  }

  String _describe(CameraException e) {
    final c = e.code.toLowerCase();
    if (c.contains('denied') || c.contains('permission') || c.contains('notallowed')) {
      return 'Camera access was blocked. Allow it for Penumbra (or this site) and try again.';
    }
    return e.description ?? e.code;
  }

  void _fail(String m) {
    if (mounted) setState(() => _error = m);
  }

  Future<void> _open(int i) async {
    final old = _ctl;
    // Take the old preview off screen before its controller is disposed.
    setState(() {
      _ctl = null;
      _index = i;
    });
    await old?.dispose();
    final c = CameraController(_cams[i], ResolutionPreset.high, enableAudio: false);
    try {
      await c.initialize();
    } catch (e) {
      await c.dispose();
      rethrow;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _ctl = c);
  }

  Future<void> _switch() async {
    try {
      await _open((_index + 1) % _cams.length);
    } on CameraException catch (e) {
      _fail(_describe(e));
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _shoot() async {
    final c = _ctl;
    if (c == null || _taking) return;
    setState(() => _taking = true);
    try {
      final x = await c.takePicture();
      final bytes = await x.readAsBytes();
      if (mounted) Navigator.of(context).pop(PickedImage(bytes, 'Camera photo.jpg'));
    } on CameraException catch (e) {
      _fail(_describe(e));
    } catch (e) {
      _fail('$e');
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('Camera')),
      body: Column(children: [
        Expanded(
          child: Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  )
                : (c == null ? const CircularProgressIndicator() : CameraPreview(c)),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Stack(alignment: Alignment.center, children: [
              GestureDetector(
                onTap: c == null || _taking ? null : _shoot,
                child: Opacity(
                  opacity: c == null ? 0.4 : 1,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _taking ? Colors.white54 : Colors.white),
                    ),
                  ),
                ),
              ),
              if (_cams.length > 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: IconButton(
                      onPressed: c == null || _taking ? null : _switch,
                      icon: const Icon(Icons.cameraswitch, color: Colors.white),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
