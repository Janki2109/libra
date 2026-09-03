import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web build: builds an in-memory Blob and clicks a hidden `<a download>`
/// link, which is the browser's own "Save As" mechanism — no server round
/// trip, no filesystem, works the same as any other website's download
/// button.
bool triggerBrowserDownload(Uint8List bytes, String fileName, String mimeType) {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
