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
      final res =
          await DioClient.instance.get('/documents?case_id=${widget.caseId}');
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
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  // The toggle is optimistic (flips immediately) but reverts on failure —
  // e.g. the backend rejects turning OFF a client's own upload (it must
  // always stay visible to that client), which the SnackBar explains rather
  // than leaving the switch silently stuck in the wrong state.
  Future<void> _setVisibility(int index, bool visible) async {
    final previous = _docs[index]['visible_to_client'] ?? false;
    setState(() => _docs[index]['visible_to_client'] = visible);
    try {
      await DioClient.instance.put('/documents/${_docs[index]['id']}/visibility',
          data: {'visible_to_client': visible});
    } catch (e) {
      if (!mounted) return;
      setState(() => _docs[index]['visible_to_client'] = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DioClient.describeError(e)),
          backgroundColor: AppColors.error));
    }
  }

  Color _color(String t) {
    switch (t.toLowerCase()) {
      case 'pdf':
        return AppColors.error;
      case 'doc':
      case 'docx':
        return AppColors.info;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return AppColors.success;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Case Documents',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded, color: AppColors.gold),
            onPressed: () => context
                .push('/documents/upload', extra: {'caseId': widget.caseId})
                .then((_) => _load()),
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
                          onTap: () => context.push('/documents/${d['id']}'),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _color(ft).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_icon(ft), color: _color(ft), size: 22),
                          ),
                          title: Text(d['file_name'] ?? '',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    '${ft.toUpperCase()} • ${d['category'] ?? 'General'}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                                if ((d['uploader_name'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Text(
                                      'Uploaded by: ${d['uploader_name']}'
                                      '${(d['uploaded_by_role'] ?? '').toString().isNotEmpty ? ' • ${(d['uploaded_by_role'] as String).replaceAll('_', ' ').toUpperCase()}' : ''}',
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600)),
                              ]),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.open_in_new_rounded,
                                    color: AppColors.gold, size: 20),
                                onPressed: () =>
                                    context.push('/documents/${d['id']}'),
                              ),
                              _VisibilityToggle(
                                doc: d,
                                onChanged: (v) => _setVisibility(i, v),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ── Visible to Client toggle ───────────────────────
// A client's own upload (uploaded_by_role == 'client') is always visible to
// them — the backend rejects turning it off, so the switch is disabled for
// those rows rather than letting the lawyer tap something that will just
// bounce back with an error.
class _VisibilityToggle extends StatelessWidget {
  final Map<String, dynamic> doc;
  final ValueChanged<bool> onChanged;
  const _VisibilityToggle({required this.doc, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final visible = doc['visible_to_client'] == true;
    final isClientUpload = (doc['uploaded_by_role'] ?? '') == 'client';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Visible to Client:',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      const SizedBox(width: 4),
      Text(visible ? 'YES' : 'NO',
          style: TextStyle(
              color: visible ? AppColors.success : AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
      Transform.scale(
        scale: 0.7,
        child: Switch(
          value: visible,
          onChanged: isClientUpload ? null : onChanged,
          activeThumbColor: AppColors.success,
        ),
      ),
    ]);
  }
}
