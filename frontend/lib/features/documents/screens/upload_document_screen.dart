import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/document_provider.dart';

/// Was previously a non-functional stub: _pickFile() only showed a "install
/// file_picker and implement pickFiles()" SnackBar and never actually set a
/// file, so _filePath stayed null forever and every upload attempt failed
/// at the "Please select a file" check — this is why documents could never
/// be uploaded through the Lawyer's Case Documents → Upload action, which
/// pushes this same screen. file_picker was already a dependency used
/// elsewhere in the app; it just was never wired up here.
class UploadDocumentScreen extends StatefulWidget {
  /// Set when pushed from a specific case's Documents tab so the upload is
  /// linked to that case — previously the push never passed this at all, so
  /// even a working picker would have uploaded an orphaned, case-less
  /// document.
  final String? caseId;
  const UploadDocumentScreen({super.key, this.caseId});
  @override
  State<UploadDocumentScreen> createState() => _UploadDocumentScreenState();
}

class _UploadDocumentScreenState extends State<UploadDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  String _category = 'general';
  PlatformFile? _picked;
  bool _picking = false;
  bool _uploading = false;
  // Lawyer uploads default to NOT visible to the client unless explicitly
  // opted in here, per product requirement.
  bool _visibleToClient = false;

  static const _categories = [
    'general', 'petition', 'evidence', 'judgment', 'contract', 'notice', 'other'
  ];
  static const _allowedExt = ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'];
  static const _extToMime = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };
  static const _maxBytes = 6 * 1024 * 1024;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String _extOf(String name) {
    final i = name.lastIndexOf('.');
    return i == -1 || i == name.length - 1
        ? ''
        : name.substring(i + 1).toLowerCase();
  }

  Future<void> _pickFile() async {
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExt,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final ext = _extOf(file.name);
      if (!_allowedExt.contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Unsupported file type. Allowed: ${_allowedExt.join(', ').toUpperCase()}'),
              backgroundColor: AppColors.error));
        }
        return;
      }
      if (file.size > _maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('File is too large. Maximum size is 6 MB.'),
              backgroundColor: AppColors.error));
        }
        return;
      }
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not read the selected file.'),
              backgroundColor: AppColors.error));
        }
        return;
      }
      setState(() => _picked = file);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    final file = _picked;
    if (file == null || file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a file'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      final ext = _extOf(file.name);
      final title = _titleCtrl.text.trim();
      final storedName = ext.isNotEmpty && !title.toLowerCase().endsWith('.$ext')
          ? '$title.$ext'
          : title;
      final ok = await context.read<DocumentProvider>().uploadDocument({
        'file_name': storedName,
        'file_content': base64Encode(file.bytes!),
        'file_type': ext,
        'file_size': file.size,
        'mime_type': _extToMime[ext] ?? 'application/octet-stream',
        'category': _category,
        'visible_to_client': _visibleToClient,
        if (widget.caseId != null && widget.caseId!.isNotEmpty)
          'case_id': widget.caseId,
      });
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Document uploaded successfully'),
              backgroundColor: AppColors.success),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Upload failed: ${context.read<DocumentProvider>().error ?? "unknown error"}'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Upload Document',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(children: [
            GestureDetector(
              onTap: _picking ? null : _pickFile,
              child: Container(
                width: double.infinity,
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _picked != null
                          ? AppColors.gold
                          : AppColors.border,
                      style: BorderStyle.solid),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _picking
                        ? const CircularProgressIndicator(
                            color: AppColors.gold)
                        : Icon(
                            _picked != null
                                ? Icons.check_circle_rounded
                                : Icons.cloud_upload_rounded,
                            color: _picked != null
                                ? AppColors.success
                                : AppColors.textMuted,
                            size: 48,
                          ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _picked != null
                            ? _picked!.name
                            : 'Tap to select a file (PDF, DOC, DOCX, JPG, JPEG, PNG)',
                        style: TextStyle(
                            color: _picked != null
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontSize: 13),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Field(
              controller: _titleCtrl,
              label: 'Document Title',
              hint: 'Enter document title',
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  dropdownColor: AppColors.bgCard,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  items: _categories
                      .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                              c[0].toUpperCase() + c.substring(1))))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _category = v ?? 'general'),
                ),
              ),
            ),
            if (widget.caseId != null && widget.caseId!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  const Expanded(
                    child: Text('Visible to Client',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                  Text(_visibleToClient ? 'YES' : 'NO',
                      style: TextStyle(
                          color: _visibleToClient
                              ? AppColors.success
                              : AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                  Switch(
                    value: _visibleToClient,
                    onChanged: (v) => setState(() => _visibleToClient = v),
                    activeThumbColor: AppColors.success,
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_rounded,
                        color: AppColors.primary, size: 20),
                label: Text(_uploading ? 'Uploading...' : 'Upload Document',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final String? Function(String?)? validator;
  const _Field(
      {required this.controller,
      required this.label,
      required this.hint,
      this.validator});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            validator: validator,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.gold)),
            ),
          ),
        ],
      );
}
