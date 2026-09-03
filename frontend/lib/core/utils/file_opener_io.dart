import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'file_opener.dart' show FileOpenResult;

Future<FileOpenResult> openDocumentBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path, type: mimeType);
    switch (result.type) {
      case ResultType.done:
        return const FileOpenResult.ok();
      case ResultType.noAppToOpen:
        return const FileOpenResult.fail(
            'No app on this device can open this file type.');
      case ResultType.permissionDenied:
        return const FileOpenResult.fail(
            'Permission denied — allow file access to open documents.');
      case ResultType.fileNotFound:
        return const FileOpenResult.fail('The file could not be saved to open.');
      case ResultType.error:
        return FileOpenResult.fail(result.message.isNotEmpty
            ? result.message
            : 'Could not open this file.');
    }
  } catch (e) {
    return FileOpenResult.fail('Could not open this file: $e');
  }
}
