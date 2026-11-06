import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/widgets/document_preview_body.dart';
import '../../lawyer/utils/android_download.dart';

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);
const _error = Color(0xFFD9534F);

/// In-app preview for a client's own document, fetched via the authorized
/// GET /portal/documents/:id (ownership already enforced server-side: the
/// document must either have been uploaded by this client or belong to
/// their own case). PDFs render with pinch-zoom/paging via pdfx, images
/// with pinch-zoom, and every other type falls back to an icon card with
/// Open-in-external-app / Download actions rather than a blank screen.
class PortalDocumentPreviewScreen extends StatefulWidget {
  final String documentId;
  const PortalDocumentPreviewScreen({super.key, required this.documentId});
  @override
  State<PortalDocumentPreviewScreen> createState() =>
      _PortalDocumentPreviewScreenState();
}

class _PortalDocumentPreviewScreenState
    extends State<PortalDocumentPreviewScreen> {
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
      final res = await DioClient.instance
          .get('/portal/documents/${widget.documentId}');
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

  bool get _isPdf {
    final mime = (_doc?['mime_type'] ?? '').toString();
    final type = (_doc?['file_type'] ?? '').toString().toLowerCase();
    return mime == 'application/pdf' || type == 'pdf';
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

  String get _fileName => (_doc?['file_name'] ?? 'document').toString();
  String get _mimeType {
    final m = (_doc?['mime_type'] ?? '').toString();
    return m.isNotEmpty ? m : 'application/octet-stream';
  }

  Future<void> _open() async {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This document has no content to open.'),
          backgroundColor: _error));
      return;
    }
    setState(() => _opening = true);
    final result = await openDocumentBytes(
        bytes: bytes, fileName: _fileName, mimeType: _mimeType);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.message ?? 'Could not open this file.'),
          backgroundColor: _error));
    }
  }

  Future<void> _download() async {
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This document has no content to download.'),
          backgroundColor: _error));
      return;
    }
    setState(() => _downloading = true);
    if (await saveToAndroidDownloads(bytes, _fileName, _mimeType)) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$_fileName saved to Downloads'),
          backgroundColor: const Color(0xFF2E8B57)));
      return;
    }
    final result = await openDocumentBytes(
        bytes: bytes, fileName: _fileName, mimeType: _mimeType);
    if (!mounted) return;
    setState(() => _downloading = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.message ?? 'Could not download this file.'),
          backgroundColor: _error));
    }
  }

  IconData _icon(String t) {
    switch (t.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isPdf ? Colors.black : _bg,
      appBar: AppBar(
        backgroundColor: _green,
        title: Text(_doc?['file_name'] ?? 'Document',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        actions: [
          if (_doc != null && _bytes != null && !_isPdf)
            IconButton(
              icon: _opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.open_in_new_rounded, color: Colors.white),
              onPressed: _opening ? null : _open,
            ),
          if (_doc != null && _bytes != null)
            IconButton(
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_rounded, color: Colors.white),
              onPressed: _downloading ? null : _download,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _loadError != null
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: _textMuted, size: 40),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: _textMuted, fontSize: 13)),
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
                          style: TextStyle(color: _textMuted)))
                  : (_isPdf || _isImage) && _bytes != null
                      ? DocumentPreviewBody(
                          bytes: _bytes!,
                          isPdf: _isPdf,
                          isImage: _isImage,
                          unsupportedFallback: const SizedBox(),
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: _bgCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _border),
                              ),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: _green.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Icon(
                                          _icon(_doc!['file_type'] ?? ''),
                                          color: _green,
                                          size: 40),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(_fileName,
                                        style: const TextStyle(
                                            color: _textPri,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16),
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 8),
                                    if (_bytes == null)
                                      const Text(
                                          'This document has no content stored — it may have failed to upload.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: _error, fontSize: 12))
                                    else
                                      const Text(
                                          'This file type can\'t be previewed in-app. Use Open or Download above.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: _textMuted,
                                              fontSize: 12)),
                                  ]),
                            ),
                          ),
                        ),
    );
  }
}
