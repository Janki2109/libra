import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/dio_client.dart';

// The complete set of extensions this screen accepts, grouped by the file
// type chip that filters the native picker to them. "Other" stays broad but
// still explicit — an unlisted extension is rejected with a clear message
// rather than silently accepted.
const Map<String, List<String>> _allowedExtByType = {
  'Document': ['doc', 'docx', 'txt'],
  'PDF': ['pdf'],
  'Photo': ['jpg', 'jpeg', 'png', 'webp'],
  'Video': ['mp4', 'mov', 'avi', 'mkv', 'webm'],
  'Excel': ['xls', 'xlsx', 'csv'],
  'Other': [
    'pdf', 'doc', 'docx', 'txt',
    'jpg', 'jpeg', 'png', 'webp',
    'mp4', 'mov', 'avi', 'mkv', 'webm',
    'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'zip',
  ],
};

const int _maxUploadFileBytes = 6 * 1024 * 1024; // matches the backend's inline-storage cap

const Map<String, String> _extToMime = {
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

String _extOf(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i == -1 || i == fileName.length - 1) return '';
  return fileName.substring(i + 1).toLowerCase();
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

class PortalDocumentsScreen extends StatefulWidget {
  const PortalDocumentsScreen({super.key});
  @override
  State<PortalDocumentsScreen> createState() => _PortalDocumentsScreenState();
}

class _PortalDocumentsScreenState extends State<PortalDocumentsScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _documents = [];
  bool _loading = true;
  int _selectedFilter = 0;
  late AnimationController _fabCtrl;
  late Animation<double> _fabScale;

  final List<String> _filters = [
    'All',
    'PDF',
    'Photo',
    'Video',
    'Document',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _fabCtrl = AnimationController(
        duration: const Duration(milliseconds: 200), vsync: this);
    _fabScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fabCtrl, curve: Curves.elasticOut));
    _fabCtrl.forward();
    _loadDocuments();
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/portal/my-documents');
      setState(() {
        _documents = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    if (_selectedFilter == 0) return _documents;
    final type = _filters[_selectedFilter].toLowerCase();
    return _documents.where((d) {
      final ft = (d['file_type'] ?? '').toLowerCase();
      final ext = _extOf((d['file_name'] ?? '').toLowerCase());
      if (type == 'pdf') return ft == 'pdf' || ext == 'pdf';
      if (type == 'photo')
        return ft.contains('image') ||
            _allowedExtByType['Photo']!.contains(ext);
      if (type == 'video')
        return ft.contains('video') || _allowedExtByType['Video']!.contains(ext);
      if (type == 'document')
        return ft.contains('doc') || _allowedExtByType['Document']!.contains(ext);
      return true;
    }).toList();
  }

  void _showUploadSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _UploadSheet(onUploaded: () {
        _loadDocuments();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Document uploaded successfully!'),
          ]),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }),
    );
  }

  IconData _fileIcon(String fileType, String fileName) {
    final ft = fileType.toLowerCase();
    final ext = _extOf(fileName.toLowerCase());
    if (ft == 'pdf' || ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (ft.contains('image') || _allowedExtByType['Photo']!.contains(ext))
      return Icons.image_rounded;
    if (ft.contains('video') || _allowedExtByType['Video']!.contains(ext))
      return Icons.videocam_rounded;
    if (ft.contains('doc') || _allowedExtByType['Document']!.contains(ext))
      return Icons.description_rounded;
    if (ft.contains('xls') || ['xls', 'xlsx', 'csv'].contains(ext))
      return Icons.table_chart_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _fileColor(String fileType, String fileName) {
    final ft = fileType.toLowerCase();
    final ext = _extOf(fileName.toLowerCase());
    if (ft == 'pdf' || ext == 'pdf') return const Color(0xFFD9534F);
    if (ft.contains('image') || _allowedExtByType['Photo']!.contains(ext))
      return const Color(0xFF4A90D9);
    if (ft.contains('video') || _allowedExtByType['Video']!.contains(ext))
      return const Color(0xFF7C3AED);
    if (ft.contains('doc') || _allowedExtByType['Document']!.contains(ext))
      return _green;
    if (ft.contains('xls') || ['xls', 'xlsx', 'csv'].contains(ext))
      return const Color(0xFF2E8B57);
    return _textMuted;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          // Green header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child: SafeArea(
                bottom: false,
                child: Column(children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                          onPressed: () => context.pop()),
                      const Expanded(
                          child: Text('My Documents',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          icon: const Icon(Icons.refresh_rounded,
                              color: Colors.white),
                          onPressed: _loadDocuments),
                    ]),
                  ),
                  // Stats bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(children: [
                      _StatPill('${_documents.length}', 'Total', Colors.white),
                      const SizedBox(width: 8),
                      _StatPill(
                          '${_documents.where((d) => (d['file_type'] ?? '').contains('pdf') || (d['file_name'] ?? '').endsWith('.pdf')).length}',
                          'PDFs',
                          const Color(0xFFFFB3B3)),
                      const SizedBox(width: 8),
                      _StatPill(
                          '${_documents.where((d) => (d['file_type'] ?? '').contains('image')).length}',
                          'Photos',
                          const Color(0xFFB3E0FF)),
                      const SizedBox(width: 8),
                      _StatPill(
                          '${_documents.where((d) => (d['file_type'] ?? '').contains('video')).length}',
                          'Videos',
                          const Color(0xFFD9B3FF)),
                    ]),
                  ),
                  // Filter chips
                  SizedBox(
                    height: 44,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      itemCount: _filters.length,
                      itemBuilder: (_, i) {
                        final sel = _selectedFilter == i;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _selectedFilter = i);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: sel
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Text(_filters[i],
                                style: TextStyle(
                                    color: sel ? _green : Colors.white,
                                    fontSize: 12,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w400)),
                          ),
                        );
                      },
                    ),
                  ),
                ])),
          ),

          // Documents list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: Icon(Icons.folder_open_rounded,
                                    color: _green, size: 50)),
                            const SizedBox(height: 16),
                            const Text('No documents yet',
                                style: TextStyle(
                                    color: _textPri,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text('Upload your files, photos & videos',
                                style: TextStyle(
                                    color: _textMuted.withValues(alpha: 0.7),
                                    fontSize: 14)),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _showUploadSheet,
                              icon: const Icon(Icons.upload_rounded,
                                  color: Colors.white),
                              label: const Text('Upload Now',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                            ),
                          ]))
                    : RefreshIndicator(
                        color: _green,
                        backgroundColor: _bgCard,
                        onRefresh: _loadDocuments,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final doc = _filtered[i];
                            final color = _fileColor(
                                doc['file_type'] ?? '', doc['file_name'] ?? '');
                            final icon = _fileIcon(
                                doc['file_type'] ?? '', doc['file_name'] ?? '');
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 200 + (i * 60)),
                              builder: (_, v, child) => Opacity(
                                  opacity: v.clamp(0.0, 1.0),
                                  child: Transform.translate(
                                      offset: Offset(0, 20 * (1 - v)),
                                      child: child)),
                              child:
                                  _DocCard(doc: doc, icon: icon, color: color),
                            );
                          },
                        ),
                      ),
          ),
        ]),
        floatingActionButton: ScaleTransition(
          scale: _fabScale,
          child: FloatingActionButton.extended(
            onPressed: _showUploadSheet,
            backgroundColor: _green,
            icon: const Icon(Icons.upload_rounded, color: Colors.white),
            label: const Text('Upload',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final dynamic doc;
  final IconData icon;
  final Color color;
  const _DocCard({required this.doc, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final name = doc['file_name'] ?? 'Document';
    final category = doc['category'] ?? doc['file_type'] ?? 'General';
    final date = doc['created_at']?.toString().substring(0, 10) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: _green.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Row(children: [
        Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 26)),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(category,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            Text(date, style: const TextStyle(color: _textMuted, fontSize: 11)),
          ]),
        ])),
        GestureDetector(
          onTap: () => _showDocOptions(context, doc, name, color, icon),
          child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.more_vert_rounded, color: color, size: 18)),
        ),
      ]),
    );
  }

  void _showDocOptions(
      BuildContext context, dynamic doc, String name, Color color, IconData icon) {
    final url = doc['file_url'] ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 12),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Text(name,
                      style: const TextStyle(
                          color: _textPri, fontWeight: FontWeight.w700)))),
        ]),
        const SizedBox(height: 16),
        Divider(color: _border, thickness: 0.6),
        ListTile(
          leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.open_in_new_rounded,
                  color: _green, size: 20)),
          title: const Text('Open / View',
              style: TextStyle(color: _textPri, fontWeight: FontWeight.w600)),
          subtitle: const Text('Open or download this document',
              style: TextStyle(color: _textMuted, fontSize: 12)),
          onTap: () async {
            Navigator.pop(context);
            await _openDocument(context, doc);
          },
        ),
        if (url.isNotEmpty)
          ListTile(
            leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: const Color(0xFF2E8B57).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.copy_rounded,
                    color: Color(0xFF2E8B57), size: 20)),
            title: const Text('Copy Link',
                style: TextStyle(color: _textPri, fontWeight: FontWeight.w600)),
            subtitle: const Text('Copy document URL',
                style: TextStyle(color: _textMuted, fontSize: 12)),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Link copied!'),
                    backgroundColor: Color(0xFF2E8B57)));
              }
            },
          ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Future<void> _openDocument(BuildContext context, dynamic doc) async {
    final existingUrl = doc['file_url'] ?? '';
    if (existingUrl.isNotEmpty) {
      final launched = await launchUrl(Uri.parse(existingUrl),
          mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the link'),
            backgroundColor: Color(0xFFD9534F)));
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: _green)),
    );
    try {
      final res = await DioClient.instance.get('/portal/documents/${doc['id']}');
      final data = res.data['data'];
      final content = data?['file_content'] ?? '';
      final mimeType = (data?['mime_type'] ?? '').toString().isNotEmpty
          ? data['mime_type']
          : (_extToMime[_extOf(doc['file_name'] ?? '')] ?? 'application/octet-stream');
      if (context.mounted) Navigator.pop(context); // close loading dialog

      if (content.isEmpty) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('This document has no file content to open'),
              backgroundColor: Color(0xFFD9534F)));
        return;
      }
      final dataUri = Uri.parse('data:$mimeType;base64,$content');
      final launched =
          await launchUrl(dataUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open this file on your device'),
            backgroundColor: Color(0xFFD9534F)));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to load the document'),
            backgroundColor: Color(0xFFD9534F)));
      }
    }
  }
}

class _UploadSheet extends StatefulWidget {
  final VoidCallback onUploaded;
  const _UploadSheet({required this.onUploaded});
  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _nameCtrl = TextEditingController();
  String _selectedType = 'Document';
  String _selectedCategory = 'General';
  bool _loading = false;
  bool _picking = false;
  PlatformFile? _pickedFile;
  double _uploadProgress = 0;

  final List<Map<String, dynamic>> _fileTypes = [
    {
      'type': 'Document',
      'icon': Icons.description_rounded,
      'color': _green,
      'emoji': '📄'
    },
    {
      'type': 'PDF',
      'icon': Icons.picture_as_pdf_rounded,
      'color': const Color(0xFFD9534F),
      'emoji': '📕'
    },
    {
      'type': 'Photo',
      'icon': Icons.image_rounded,
      'color': const Color(0xFF4A90D9),
      'emoji': '🖼️'
    },
    {
      'type': 'Video',
      'icon': Icons.videocam_rounded,
      'color': const Color(0xFF7C3AED),
      'emoji': '🎥'
    },
    {
      'type': 'Excel',
      'icon': Icons.table_chart_rounded,
      'color': const Color(0xFF2E8B57),
      'emoji': '📊'
    },
    {
      'type': 'Other',
      'icon': Icons.attach_file_rounded,
      'color': _textMuted,
      'emoji': '📎'
    },
  ];

  final List<String> _categories = [
    'General',
    'Court Order',
    'Petition',
    'Agreement',
    'Evidence',
    'Identity Proof',
    'Property Document',
    'Medical Record',
    'Financial Record',
    'Other'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: const Color(0xFFD9534F)));
  }

  Future<void> _pickFile() async {
    final allowed = _allowedExtByType[_selectedType] ?? const <String>[];
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowed,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final ext = _extOf(file.name);

      // The OS picker's extension filter is advisory on some platforms, so
      // the same allow-list is re-checked here before anything is accepted.
      if (!allowed.contains(ext)) {
        _showError(
            'Unsupported file type for $_selectedType. Allowed: ${allowed.join(', ').toUpperCase()}');
        return;
      }
      if (file.size > _maxUploadFileBytes) {
        _showError('File is too large. Maximum size is 6 MB.');
        return;
      }
      if (file.bytes == null) {
        _showError('Could not read the selected file. Please try again.');
        return;
      }
      setState(() => _pickedFile = file);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeFile() => setState(() => _pickedFile = null);

  Future<void> _upload() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Please enter document name');
      return;
    }
    final file = _pickedFile;
    if (file == null || file.bytes == null) {
      _showError('Please select a file to upload');
      return;
    }
    setState(() {
      _loading = true;
      _uploadProgress = 0;
    });
    try {
      final ext = _extOf(file.name);
      final title = _nameCtrl.text.trim();
      // The extension is kept on the stored file name (even though the user
      // never typed it) so downstream type detection — icons, the type
      // filter chips, and opening the file later — has something real to
      // key off, instead of only the free-text title the user entered.
      final storedName = ext.isNotEmpty && !title.toLowerCase().endsWith('.$ext')
          ? '$title.$ext'
          : title;
      await DioClient.instance.post('/portal/documents/upload',
          data: {
            'file_name': storedName,
            'file_content': base64Encode(file.bytes!),
            'file_type': ext.isNotEmpty ? ext : _selectedType.toLowerCase(),
            'file_size': file.size,
            'mime_type': _extToMime[ext] ?? 'application/octet-stream',
            'category': _selectedCategory,
            'description': 'Uploaded by client',
          },
          onSendProgress: (sent, total) {
            if (total > 0 && mounted) {
              setState(() => _uploadProgress = sent / total);
            }
          });
      if (mounted) {
        Navigator.pop(context);
        widget.onUploaded();
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Upload failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
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
              Row(children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: _green, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.upload_rounded,
                        color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload Document',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      Text('Share files with your lawyer',
                          style: TextStyle(color: _textMuted, fontSize: 12)),
                    ]),
              ]),
              const SizedBox(height: 16),
              const Text('File Type',
                  style: TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                  height: 70,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _fileTypes.length,
                    itemBuilder: (_, i) {
                      final ft = _fileTypes[i];
                      final sel = _selectedType == ft['type'];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _selectedType = ft['type'];
                            // A file picked under the old type filter may no
                            // longer match the newly selected one.
                            _pickedFile = null;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? (ft['color'] as Color).withValues(alpha: 0.12)
                                : _bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: sel ? ft['color'] as Color : _border,
                                width: sel ? 2 : 1),
                          ),
                          child: Column(children: [
                            Text(ft['emoji'],
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(height: 4),
                            Text(ft['type'],
                                style: TextStyle(
                                    color:
                                        sel ? ft['color'] as Color : _textMuted,
                                    fontSize: 10,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w400)),
                          ]),
                        ),
                      );
                    },
                  )),
              const SizedBox(height: 14),
              _field(_nameCtrl, 'Document Name *',
                  Icons.drive_file_rename_outline_rounded),
              const SizedBox(height: 12),
              const Text('File',
                  style: TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _pickedFile == null
                  ? _PickFileButton(
                      loading: _picking,
                      allowedExt: _allowedExtByType[_selectedType] ?? const [],
                      onTap: _picking ? null : _pickFile,
                    )
                  : _PickedFilePreview(
                      file: _pickedFile!,
                      onRemove: _removeFile,
                      onChange: _pickFile,
                    ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border, width: 0.8)),
                child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                  value: _selectedCategory,
                  dropdownColor: _bgCard,
                  style: const TextStyle(color: _textPri, fontSize: 14),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: _green),
                  isExpanded: true,
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v!),
                )),
              ),
              if (_loading) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: _uploadProgress > 0 ? _uploadProgress : null,
                      backgroundColor: _border,
                      color: _green,
                      minHeight: 6),
                ),
                const SizedBox(height: 6),
                Text(
                    _uploadProgress > 0
                        ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                        : 'Uploading...',
                    style: const TextStyle(color: _textMuted, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _upload,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                              Icon(Icons.upload_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text('Upload Document',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ]),
                ),
              ),
            ]),
      );

  Widget _field(TextEditingController ctrl, String label, IconData icon) =>
      TextField(
        controller: ctrl,
        style: const TextStyle(color: _textPri, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: _green, size: 18),
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
              borderSide: const BorderSide(color: _green, width: 1.5)),
        ),
      );
}

class _PickFileButton extends StatelessWidget {
  final bool loading;
  final List<String> allowedExt;
  final VoidCallback? onTap;
  const _PickFileButton(
      {required this.loading, required this.allowedExt, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _border, width: 1.2, style: BorderStyle.solid),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (loading)
              const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: _green, strokeWidth: 2.5))
            else
              const Icon(Icons.cloud_upload_rounded, color: _green, size: 32),
            const SizedBox(height: 8),
            Text(loading ? 'Opening file picker...' : 'Tap to select a file',
                style: const TextStyle(
                    color: _textPri, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(allowedExt.map((e) => e.toUpperCase()).join(', '),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _textMuted.withValues(alpha: 0.8), fontSize: 10)),
          ]),
        ),
      );
}

class _PickedFilePreview extends StatelessWidget {
  final PlatformFile file;
  final VoidCallback onRemove;
  final VoidCallback onChange;
  const _PickedFilePreview(
      {required this.file, required this.onRemove, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final ext = _extOf(file.name);
    final isImage = _allowedExtByType['Photo']!.contains(ext);
    final isVideo = _allowedExtByType['Video']!.contains(ext);

    Widget thumb;
    if (isImage && file.bytes != null) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(file.bytes!,
            width: 52, height: 52, fit: BoxFit.cover),
      );
    } else {
      final icon = isVideo
          ? Icons.videocam_rounded
          : ext == 'pdf'
              ? Icons.picture_as_pdf_rounded
              : Icons.insert_drive_file_rounded;
      thumb = Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Stack(alignment: Alignment.center, children: [
          Icon(icon, color: _green, size: 26),
          if (isVideo)
            const Positioned(
                bottom: 4,
                right: 4,
                child: Icon(Icons.play_circle_fill_rounded,
                    color: _green, size: 16)),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green, width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Selected File',
            style: TextStyle(
                color: _textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Text('${ext.toUpperCase()} · ${_formatFileSize(file.size)}',
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFD9534F), size: 16),
              label: const Text('Remove',
                  style: TextStyle(
                      color: Color(0xFFD9534F), fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD9534F)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onChange,
              icon: const Icon(Icons.sync_alt_rounded, color: _green, size: 16),
              label: const Text('Change File',
                  style: TextStyle(color: _green, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _green),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatPill(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10)),
        ]),
      );
}
