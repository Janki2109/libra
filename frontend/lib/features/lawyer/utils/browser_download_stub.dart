import 'dart:typed_data';

/// Non-web build: there's no browser to hand a download to, so the caller
/// falls back to its normal file-system + share-sheet flow instead.
bool triggerBrowserDownload(Uint8List bytes, String fileName, String mimeType) =>
    false;
