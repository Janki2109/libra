import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

class ViewDocumentScreen extends StatefulWidget {
  final String documentId;
  const ViewDocumentScreen({super.key, required this.documentId});
  @override
  State<ViewDocumentScreen> createState() => _ViewDocumentScreenState();
}

class _ViewDocumentScreenState extends State<ViewDocumentScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await DioClient.instance.get('/documents/${widget.documentId}');
      setState(() {
        _doc = res.data['data'];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
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
              icon: const Icon(Icons.download_rounded, color: AppColors.gold),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Download: use url_launcher to open file URL'),
                      backgroundColor: AppColors.info),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _doc == null
              ? const Center(
                  child: Text('Document not found',
                      style: TextStyle(color: AppColors.textMuted)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
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
                          child: Icon(
                              _icon(_doc!['file_type'] ?? ''),
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
                        _Row(Icons.calendar_today_rounded, 'Uploaded',
                            _safe(_doc!['created_at'])),
                        if ((_doc!['description'] ?? '').isNotEmpty)
                          _Row(Icons.info_rounded, 'Description',
                              _doc!['description']),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    if ((_doc!['file_url'] ?? '').isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Open: ${_doc!['file_url']}'),
                                  backgroundColor: AppColors.info),
                            );
                          },
                          icon: const Icon(Icons.open_in_new_rounded,
                              color: AppColors.primary, size: 20),
                          label: const Text('Open Document',
                              style: TextStyle(
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
                  ]),
                ),
    );
  }

  String _safe(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
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
