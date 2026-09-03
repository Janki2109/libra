import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

// ── Premium Navy/Gold Theme (matches LibraTheme) ────
const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D); // primary navy
const _brownLight = Color(0xFF3D2C8D); // purple
const _gold = Color(0xFFD4AF37);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);

const Map<String, List<String>> _docAllowedExtByType = {
  'Document': ['doc', 'docx', 'txt'],
  'PDF': ['pdf'],
  'Photo': ['jpg', 'jpeg', 'png', 'webp'],
  'Video': ['mp4', 'mov', 'avi', 'mkv', 'webm'],
  'Other': [
    'pdf', 'doc', 'docx', 'txt',
    'jpg', 'jpeg', 'png', 'webp',
    'mp4', 'mov', 'avi', 'mkv', 'webm',
    'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'zip',
  ],
};
const int _docMaxUploadFileBytes = 6 * 1024 * 1024;
const Map<String, String> _docExtToMime = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'txt': 'text/plain',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'csv': 'text/csv',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'zip': 'application/zip',
};
String _docExtOf(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i == -1 || i == fileName.length - 1) return '';
  return fileName.substring(i + 1).toLowerCase();
}
String _docFormatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});
  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  List<dynamic> _documents = [];
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/documents');
      setState(() {
        _documents = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  IconData _fileIcon(String t) {
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
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _fileColor(String t) {
    switch (t.toLowerCase()) {
      case 'pdf':
        return const Color(0xFFD9534F);
      case 'doc':
      case 'docx':
        return const Color(0xFF4A90D9);
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Color(0xFF2E8B57);
      case 'xls':
      case 'xlsx':
        return _gold;
      default:
        return _brownLight;
    }
  }

  void _showUploadDialog() {
    final nameCtrl = TextEditingController();
    String category = 'General';
    String selectedType = 'Document';
    PlatformFile? pickedFile;
    bool picking = false;
    bool loading = false;
    double uploadProgress = 0;
    final types = ['Document', 'PDF', 'Photo', 'Video', 'Other'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> pickFile() async {
          setS(() => picking = true);
          try {
            final allowed = _docAllowedExtByType[selectedType] ?? const <String>[];
            final result = await FilePicker.platform.pickFiles(
                type: FileType.custom, allowedExtensions: allowed, withData: true);
            if (result == null || result.files.isEmpty) return;
            final f = result.files.single;
            final ext = _docExtOf(f.name);
            if (!allowed.contains(ext)) {
              if (ctx.mounted)
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(
                        'Unsupported file type for $selectedType. Allowed: ${allowed.join(', ').toUpperCase()}'),
                    backgroundColor: const Color(0xFFD9534F)));
              return;
            }
            if (f.size > _docMaxUploadFileBytes) {
              if (ctx.mounted)
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('File is too large. Maximum size is 6 MB.'),
                    backgroundColor: Color(0xFFD9534F)));
              return;
            }
            if (f.bytes == null) {
              if (ctx.mounted)
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content:
                        Text('Could not read the selected file. Please try again.'),
                    backgroundColor: Color(0xFFD9534F)));
              return;
            }
            setS(() => pickedFile = f);
          } finally {
            setS(() => picking = false);
          }
        }

        return Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: _border,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  const Text('Upload Document',
                      style: TextStyle(
                          color: _textPri,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  SizedBox(
                      height: 50,
                      child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: types.map((t) {
                            final sel = selectedType == t;
                            return GestureDetector(
                              onTap: () => setS(() {
                                selectedType = t;
                                pickedFile = null;
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? _brown.withValues(alpha: 0.1)
                                      : _bg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: sel ? _brown : _border,
                                      width: sel ? 2 : 1),
                                ),
                                child: Text(t,
                                    style: TextStyle(
                                        color: sel ? _brown : _textMuted,
                                        fontWeight: sel
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        fontSize: 12)),
                              ),
                            );
                          }).toList())),
                  const SizedBox(height: 14),
                  _sheetField(nameCtrl, 'Document Name *',
                      Icons.description_outlined),
                  const SizedBox(height: 12),
                  pickedFile == null
                      ? InkWell(
                          onTap: picking ? null : pickFile,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 20, horizontal: 16),
                            decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border, width: 1.2),
                            ),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              if (picking)
                                const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                        color: _brown, strokeWidth: 2.5))
                              else
                                const Icon(Icons.cloud_upload_rounded,
                                    color: _brown, size: 30),
                              const SizedBox(height: 8),
                              Text(
                                  picking
                                      ? 'Opening file picker...'
                                      : 'Tap to select a file',
                                  style: const TextStyle(
                                      color: _textPri,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                  (_docAllowedExtByType[selectedType] ?? [])
                                      .map((e) => e.toUpperCase())
                                      .join(', '),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: _textMuted.withValues(alpha: 0.8),
                                      fontSize: 10)),
                            ]),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _brown, width: 1.2),
                          ),
                          child: Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: _brown.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Icon(
                                  _fileIcon(_docExtOf(pickedFile!.name)),
                                  color: _brown),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(pickedFile!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: _textPri,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                Text(_docFormatSize(pickedFile!.size),
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 11)),
                              ],
                            )),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Color(0xFFD9534F), size: 20),
                              onPressed: () => setS(() => pickedFile = null),
                            ),
                          ]),
                        ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(
                        color: _bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border, width: 0.8)),
                    child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                      value: category,
                      dropdownColor: _bgCard,
                      style: const TextStyle(color: _textPri, fontSize: 14),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _brown),
                      isExpanded: true,
                      items: [
                        'General',
                        'Court Order',
                        'Agreement',
                        'Invoice',
                        'Evidence',
                        'Other'
                      ]
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setS(() => category = v!),
                    )),
                  ),
                  if (loading) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: uploadProgress > 0 ? uploadProgress : null,
                          backgroundColor: _border,
                          color: _brown,
                          minHeight: 6),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: loading
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().isEmpty) return;
                              final file = pickedFile;
                              if (file == null || file.bytes == null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Please select a file to upload'),
                                        backgroundColor: Color(0xFFD9534F)));
                                return;
                              }
                              setS(() {
                                loading = true;
                                uploadProgress = 0;
                              });
                              try {
                                final ext = _docExtOf(file.name);
                                final title = nameCtrl.text.trim();
                                final storedName = ext.isNotEmpty &&
                                        !title.toLowerCase().endsWith('.$ext')
                                    ? '$title.$ext'
                                    : title;
                                await DioClient.instance.post(
                                    '/documents/upload',
                                    data: {
                                      'file_name': storedName,
                                      'file_content': base64Encode(file.bytes!),
                                      'file_type': ext.isNotEmpty
                                          ? ext
                                          : selectedType.toLowerCase(),
                                      'file_size': file.size,
                                      'mime_type': _docExtToMime[ext] ??
                                          'application/octet-stream',
                                      'category': category,
                                    },
                                    onSendProgress: (sent, total) {
                                  if (total > 0)
                                    setS(() => uploadProgress = sent / total);
                                });
                                if (ctx.mounted) Navigator.pop(ctx);
                                _loadDocuments();
                                HapticFeedback.heavyImpact();
                              } catch (e) {
                                setS(() => loading = false);
                                if (ctx.mounted)
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Upload failed. Please try again.'),
                                          backgroundColor: Color(0xFFD9534F)));
                              }
                            },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _brown,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Upload Document',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ),
                ]),
          ),
        );
      }),
    );
  }

  Widget _sheetField(TextEditingController ctrl, String label, IconData icon) =>
      TextField(
          controller: ctrl,
          style: const TextStyle(color: _textPri, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
            prefixIcon: Icon(icon, color: _brown, size: 18),
            filled: true,
            fillColor: _bg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border, width: 0.8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _brown, width: 1.5)),
          ));

  @override
  Widget build(BuildContext context) {
    final filtered = _documents.where((d) {
      final name = (d['file_name'] ?? '').toLowerCase();
      final category = (d['category'] ?? '').toLowerCase();
      return name.contains(_search) || category.contains(_search);
    }).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0B0726), Color(0xFF150E3D), Color(0xFF3D2C8D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Text('Documents',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                    IconButton(
                      icon: const Icon(Icons.upload_file_rounded,
                          color: Color(0xFFFFD700)),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showUploadDialog();
                      },
                    ),
                  ]),
                )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: _textPri, fontSize: 14),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search documents...',
                hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: _brownLight, size: 20),
                filled: true,
                fillColor: _bgCard,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _border, width: 0.8)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _brown, width: 1.5)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                      color: _brown, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('${filtered.length} documents',
                  style: const TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                    color: _brown.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _border)),
                                child: const Icon(Icons.folder_open_rounded,
                                    color: _brownLight, size: 38)),
                            const SizedBox(height: 16),
                            const Text('No documents yet',
                                style: TextStyle(
                                    color: _textPri,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _showUploadDialog,
                              icon: const Icon(Icons.upload_rounded,
                                  color: Colors.white),
                              label: const Text('Upload Document',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _brown,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                            ),
                          ]))
                    : RefreshIndicator(
                        color: _brown,
                        backgroundColor: _bgCard,
                        onRefresh: _loadDocuments,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            final fileType = d['file_type'] ?? '';
                            final color = _fileColor(fileType);
                            final icon = _fileIcon(fileType);
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                context.push('/documents/${d['id']}');
                              },
                              child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: _bgCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: _border, width: 0.8),
                                  boxShadow: [
                                    BoxShadow(
                                        color: _brown.withValues(alpha: 0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2))
                                  ]),
                              child: Row(children: [
                                Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: color.withValues(alpha: 0.3))),
                                    child: Icon(icon, color: color, size: 24)),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(d['file_name'] ?? '',
                                          style: const TextStyle(
                                              color: _textPri,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      if ((d['category'] ?? '').isNotEmpty)
                                        Container(
                                            margin:
                                                const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: _brown.withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(4)),
                                            child: Text(d['category'],
                                                style: const TextStyle(
                                                    color: _brownLight,
                                                    fontSize: 10))),
                                    ])),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: Color(0xFFD9534F), size: 20),
                                  onPressed: () async {
                                    HapticFeedback.lightImpact();
                                    await DioClient.instance
                                        .delete('/documents/${d['id']}');
                                    _loadDocuments();
                                  },
                                ),
                              ]),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ]),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            _showUploadDialog();
          },
          backgroundColor: _brown,
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    );
  }
}
