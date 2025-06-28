library;

/// Export the appropriate storage implementation based on platform
export 'storage_interface.dart';
export 'storage_stub.dart'
    if (dart.library.io) 'storage_io.dart'
    if (dart.library.html) 'storage_web.dart';