import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_opener.dart' show FileOpenResult;

Future<FileOpenResult> openDocumentBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  try {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    // A renderable type (pdf/image) opens directly in the new tab; anything
    // else the browser can't display it just downloads instead — still a
    // successful "open", just via the browser's own fallback.
    web.window.open(url, '_blank');
    // The object URL only needs to outlive the tab's initial load, not the
    // whole session — revoke it shortly after instead of leaking it forever.
    Future.delayed(const Duration(minutes: 5), () => web.URL.revokeObjectURL(url));
    return const FileOpenResult.ok();
  } catch (e) {
    return FileOpenResult.fail('Could not open this file: $e');
  }
}
