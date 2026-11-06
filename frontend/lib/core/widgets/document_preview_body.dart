import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Shared in-app document preview body: renders PDFs with pinch-zoom and
/// page scrolling via pdfx, images with pinch-zoom via InteractiveViewer,
/// and falls back to an icon card (caller supplies the Open/Download
/// actions around it) for every other file type. Used by both the
/// lawyer/student ViewDocumentScreen and the client portal's document
/// preview screen so the actual rendering logic exists in exactly one
/// place instead of being duplicated per role.
class DocumentPreviewBody extends StatefulWidget {
  final Uint8List bytes;
  final bool isPdf;
  final bool isImage;
  final Widget unsupportedFallback;
  const DocumentPreviewBody({
    super.key,
    required this.bytes,
    required this.isPdf,
    required this.isImage,
    required this.unsupportedFallback,
  });

  @override
  State<DocumentPreviewBody> createState() => _DocumentPreviewBodyState();
}

class _DocumentPreviewBodyState extends State<DocumentPreviewBody> {
  PdfControllerPinch? _pdfController;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    if (widget.isPdf) {
      try {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openData(widget.bytes),
        );
      } catch (e) {
        _pdfError = 'Could not open this PDF.';
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPdf) {
      if (_pdfError != null || _pdfController == null) {
        return Center(
            child: Text(_pdfError ?? 'Could not open this PDF.',
                style: const TextStyle(color: Colors.white70)));
      }
      return PdfViewPinch(
        controller: _pdfController!,
        onDocumentError: (_) => setState(() {
          _pdfError = 'Could not open this PDF.';
        }),
      );
    }
    if (widget.isImage) {
      return InteractiveViewer(
        maxScale: 5,
        minScale: 0.5,
        child: Center(
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
                child: Text('Could not preview this image.',
                    style: TextStyle(color: Colors.white70))),
          ),
        ),
      );
    }
    return widget.unsupportedFallback;
  }
}
