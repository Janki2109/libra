import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.libra.law/downloads');

/// Saves [bytes] as [fileName] directly into the device's Downloads folder
/// via MediaStore (see MainActivity.kt) — the same place a browser download
/// would land. Returns true if it actually saved; false on iOS, on pre-Android
/// 10 devices without storage access, or on any platform error, so the caller
/// can fall back to its existing temp-file + OS share sheet flow.
Future<bool> saveToAndroidDownloads(
    Uint8List bytes, String fileName, String mimeType) async {
  if (!Platform.isAndroid) return false;
  try {
    final ok = await _channel.invokeMethod<bool>('saveToDownloads', {
      'fileName': fileName,
      'mimeType': mimeType,
      'bytes': bytes,
    });
    return ok ?? false;
  } catch (_) {
    return false;
  }
}
