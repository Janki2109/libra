import 'dart:typed_data';

import 'file_opener_io.dart' if (dart.library.html) 'file_opener_web.dart' as impl;

/// Result of trying to open a document's bytes with the platform's own
/// viewer/app — never throws, so a missing document, an unsupported format,
/// or "no app installed for this file type" all come back as a clear
/// message instead of crashing the Documents screen.
class FileOpenResult {
  final bool success;
  final String? message;
  const FileOpenResult.ok() : success = true, message = null;
  const FileOpenResult.fail(this.message) : success = false;
}

/// Opens [bytes] (already decoded from the server's base64 payload) named
/// [fileName] with content type [mimeType].
///
/// Web: opens an in-memory Blob in a new tab — the browser renders PDFs and
/// images natively, and downloads anything it can't render (DOCX etc.),
/// which is exactly the "open, or fall back to download" behavior this
/// needs without extra branching.
///
/// Mobile/desktop: writes to a temp file and hands it to the OS's own
/// viewer/share sheet via open_filex, so every format the device has an app
/// for just opens — the same as tapping a downloaded file in a file browser.
Future<FileOpenResult> openDocumentBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) =>
    impl.openDocumentBytes(bytes: bytes, fileName: fileName, mimeType: mimeType);
