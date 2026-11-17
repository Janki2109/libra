import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/dio_client.dart';
import '../../../core/widgets/document_preview_body.dart';
import '../../lawyer/utils/android_download.dart';
import '../certificate_pdf.dart';

const _bg = Color(0xFFF0F4FF);
const _navy = Color(0xFF0A1628);
const _gold = Color(0xFFD4AF37);
const _textMuted = Color(0xFF546E7A);
const _errColor = Color(0xFFD9534F);
const _success = Color(0xFF2E8B57);

/// Real certificate preview, download and share -- replaces the old
/// in-dialog fake certificate (a static gradient box with a Share button
/// that only ever copied a sentence to the clipboard). Fetches the actual
/// certificate record (GET /student/certificates/:id -- real student name,
/// course name, certificate number, issue date, scoped to the
/// authenticated student's own certificates), generates a real PDF from
/// it, and renders that same PDF in-app before the student downloads or
/// shares it, so what's previewed is exactly what gets saved/shared.
class CertificatePreviewScreen extends StatefulWidget {
  final String certificateId;
  const CertificatePreviewScreen({super.key, required this.certificateId});
  @override
  State<CertificatePreviewScreen> createState() =>
      _CertificatePreviewScreenState();
}

class _CertificatePreviewScreenState extends State<CertificatePreviewScreen> {
  Map<String, dynamic>? _cert;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await DioClient.instance
          .get('/student/certificates/${widget.certificateId}');
      final data = res.data['data'] as Map<String, dynamic>;
      final issuedAt = DateTime.tryParse((data['issued_at'] ?? '').toString());
      final dateLabel = issuedAt != null
          ? '${issuedAt.day} ${_month(issuedAt.month)} ${issuedAt.year}'
          : '';
      final doc = await buildCertificatePdf(
        studentName: (data['student_name'] ?? '').toString(),
        courseName: (data['course_name'] ?? '').toString(),
        certificateNumber: (data['certificate_number'] ?? '').toString(),
        issueDateLabel: dateLabel,
        instructorName: (data['instructor_name'] ?? '').toString(),
        directorName: (data['director_name'] ?? '').toString(),
      );
      final bytes = await doc.save();
      if (!mounted) return;
      setState(() {
        _cert = data;
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

  String _month(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][(m - 1).clamp(0, 11)];

  String get _fileName {
    final student = (_cert?['student_name'] ?? 'Student')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final course = (_cert?['course_name'] ?? 'Course')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'OneLegal_Certificate_${student}_$course.pdf';
  }

  Future<void> _download() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    HapticFeedback.mediumImpact();
    if (await saveToAndroidDownloads(bytes, _fileName, 'application/pdf')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Certificate downloaded successfully!'),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating));
      return;
    }
    // iOS / older Android without Downloads access: save to a temp file and
    // hand it to the OS (Save to Files / another app) -- same fallback the
    // rest of this app already uses for every other download.
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Certificate downloaded successfully!'),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not download certificate: $e'),
          backgroundColor: _errColor));
    }
  }

  Future<void> _share() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    HapticFeedback.mediumImpact();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          text: 'My ${_cert?['course_name'] ?? ''} certificate from OneLegal');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not share certificate: $e'),
          backgroundColor: _errColor));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Certificate'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline_rounded,
                          color: _textMuted, size: 44),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _textMuted)),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Row(children: [
                      Icon(Icons.celebration_rounded, color: _gold, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Congratulations! Your OneLegal Certificate is ready.',
                            style: TextStyle(
                                color: _navy,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: DocumentPreviewBody(
                          bytes: _pdfBytes!,
                          isPdf: true,
                          isImage: false,
                          unsupportedFallback: const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.share_rounded,
                              color: _navy, size: 18),
                          label: const Text('Share Certificate',
                              style: TextStyle(
                                  color: _navy, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _navy),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _download,
                          icon: const Icon(Icons.download_rounded,
                              color: Colors.white, size: 18),
                          label: const Text('Download Certificate',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                    ]),
                  ),
                ]),
    );
  }
}
