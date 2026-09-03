import 'dart:typed_data';

import 'browser_download_stub.dart'
    if (dart.library.html) 'browser_download_web.dart' as impl;

/// Triggers a real browser "Save As" download of [bytes] as [fileName] with
/// the given [mimeType]. Returns true if the download was actually
/// triggered (web only); returns false everywhere else so the caller can
/// fall back to its normal mobile/desktop file handling (temp file + OS
/// share sheet) instead.
///
/// dart:io's File/path_provider have no real filesystem to write to on Flutter
/// Web — constructing a File there throws at runtime, which is what made
/// every "Word"/"PDF" export button fail with a generic error on the web
/// build. This bypasses that path entirely on web.
bool triggerBrowserDownload(Uint8List bytes, String fileName, String mimeType) =>
    impl.triggerBrowserDownload(bytes, fileName, mimeType);
