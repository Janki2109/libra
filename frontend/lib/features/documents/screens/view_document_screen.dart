import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/utils/file_opener.dart';
import '../../lawyer/utils/android_download.dart';

class ViewDocumentScreen extends StatefulWidget {
  final String documentId;
  const ViewDocumentScreen({super.key, required this.documentId});
  @override
  State<ViewDocumentScreen> createState() => _ViewDocumentScreenState();
}

class _ViewDocumentScreenState extends State<ViewDocumentScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _loadError;
  bool _opening = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res =
          await DioClient.instance.get('/documents/${widget.documentId}');
      setState(() {
        _doc = res.data['data'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = DioClient.describeError(e);
      });
    }
  }

  bool get _isImage {
    final mime = (_doc?['mime_type'] ?? '').toString();
    final type = (_doc?['file_type'] ?? '').toString().toLowerCase();
    return mime.startsWith('image/') ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(type);
  }

  Uint8List? get _bytes {
    final b64 = (_doc?['file_content'] ?? '').toString();
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _open() async {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This document has no content to open.'),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _opening = true);
    final fileName = (_doc?['file_name'] ?? 'document').toString();
    final mimeType = (_doc?['mime_type'] ?? '').toString().isNotEmpty
        ? _doc!['mime_type'].toString()
        : 'application/octet-stream';
    final result = await openDocumentBytes(
        bytes: bytes, fileName: fileName, mimeType: mimeType);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.message ?? 'Could not open this file.'),
          backgroundColor: AppColors.error));
    }
  }

  /// Saves straight to the device's Downloads folder on Android (same
  /// mechanism Smart Draft's exports and the client portal's document
  /// download already use); elsewhere falls back to the OS viewer/share
  /// sheet, same as _open, since there's no bare Downloads folder to write
  /// to on iOS/desktop/web.
  Future<void> _download() async {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This document has no content to download.'),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _downloading = true);
    final fileName = (_doc?['file_name'] ?? 'document').toString();
    final mimeType = (_doc?['mime_type'] ?? '').toString().isNotEmpty
        ? _doc!['mime_type'].toString()
        : 'application/octet-stream';

    if (await saveToAndroidDownloads(bytes, fileName, mimeType)) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$fileName saved to Downloads'),
          backgroundColor: const Color(0xFF2E8B57)));
      return;
    }

    final result = await openDocumentBytes(
        bytes: bytes, fileName: fileName, mimeType: mimeType);
    if (!mounted) return;
    setState(() => _downloading = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.message ?? 'Could not download this file.'),
          backgroundColor: AppColors.error));
    }
  }

  IconData _icon(String t) {
    switch (t.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx': return Icons.description_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png': return Icons.image_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  Color _color(String t) {
    switch (t.toLowerCase()) {
      case 'pdf': return AppColors.error;
      case 'doc':
      case 'docx': return AppColors.info;
      case 'jpg':
      case 'jpeg':
      case 'png': return AppColors.success;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: Text(_doc?['file_name'] ?? 'Document',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        actions: [
          if (_doc != null)
            IconButton(
              icon: _opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.gold))
                  : const Icon(Icons.open_in_new_rounded, color: AppColors.gold),
              onPressed: _opening ? null : _open,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _loadError != null
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            color: AppColors.textMuted, size: 40),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(_loadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Retry')),
                      ]))
              : _doc == null
                  ? const Center(
                      child: Text('Document not found',
                          style: TextStyle(color: AppColors.textMuted)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        if (_isImage && _bytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: InteractiveViewer(
                              maxScale: 4,
                              child: Image.memory(_bytes!,
                                  width: double.infinity, fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                      padding: const EdgeInsets.all(32),
                                      alignment: Alignment.center,
                                      child: const Text(
                                          'Could not preview this image.',
                                          style: TextStyle(
                                              color: AppColors.textMuted)))),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: AppColors.bgCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: _color(_doc!['file_type'] ?? '')
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(_icon(_doc!['file_type'] ?? ''),
                                    color: _color(_doc!['file_type'] ?? ''),
                                    size: 40),
                              ),
                              const SizedBox(height: 16),
                              Text(_doc!['file_name'] ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              Text(
                                  '${(_doc!['file_type'] ?? '').toString().toUpperCase()} • ${_doc!['category'] ?? 'General'}',
                                  style: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 12)),
                              if (_bytes == null) ...[
                                const SizedBox(height: 12),
                                const Text(
                                    'This document has no content stored — it may have failed to upload.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.error, fontSize: 12)),
                              ],
                            ]),
                          ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(children: [
                            _Row(Icons.folder_rounded, 'Category',
                                _doc!['category'] ?? 'General'),
                            if ((_doc!['description'] ?? '').toString().isNotEmpty)
                              _Row(Icons.info_rounded, 'Description',
                                  _doc!['description']),
                          ]),
                        ),
                        const SizedBox(height: 20),
                        if (_bytes != null)
                          Row(children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _opening ? null : _open,
                                icon: _opening
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.primary))
                                    : const Icon(Icons.open_in_new_rounded,
                                        color: AppColors.primary, size: 20),
                                label: Text(
                                    _opening ? 'Opening...' : 'Open Document',
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _downloading ? null : _download,
                                icon: _downloading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.gold))
                                    : const Icon(Icons.download_rounded,
                                        color: AppColors.gold, size: 20),
                                label: Text(
                                    _downloading ? 'Saving...' : 'Download',
                                    style: const TextStyle(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.gold),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ]),
                      ]),
                    ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _Row(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.gold, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
                Text(value,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
              ],
            ),
          ),
        ]),
      );
}
