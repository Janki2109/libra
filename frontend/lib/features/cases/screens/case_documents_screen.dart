import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

class CaseDocumentsScreen extends StatefulWidget {
  final String caseId;
  const CaseDocumentsScreen({super.key, required this.caseId});
  @override
  State<CaseDocumentsScreen> createState() => _CaseDocumentsScreenState();
}

class _CaseDocumentsScreenState extends State<CaseDocumentsScreen> {
  List<dynamic> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.instance
          .get('/documents?case_id=${widget.caseId}');
      setState(() {
        _docs = res.data['data'] ?? [];
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
        title: const Text('Case Documents',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded,
                color: AppColors.gold),
            onPressed: () =>
                context.push('/documents/upload').then((_) => _load()),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _docs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_rounded,
                          color: AppColors.textMuted, size: 64),
                      SizedBox(height: 16),
                      Text('No Documents',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _docs.length,
                    itemBuilder: (_, i) {
                      final d = _docs[i];
                      final ft = (d['file_type'] ?? '').toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _color(ft).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_icon(ft),
                                color: _color(ft), size: 22),
                          ),
                          title: Text(d['file_name'] ?? '',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          subtitle: Text(
                              '${ft.toUpperCase()} • ${d['category'] ?? 'General'}',
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.open_in_new_rounded,
                                color: AppColors.gold, size: 20),
                            onPressed: () =>
                                context.push('/documents/${d['id']}'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
