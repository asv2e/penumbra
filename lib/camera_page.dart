/// Platform-specific camera capture screens.
///
/// The web screen uses the browser MediaDevices API directly. The stock
/// camera_web implementation probes every camera while listing devices, and
/// a stale or inactive virtual camera can make that entire probe fail.
library;

export 'camera_page_native.dart'
    if (dart.library.html) 'camera_page_web.dart';
