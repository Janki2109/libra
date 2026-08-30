import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/document_provider.dart';

class UploadDocumentScreen extends StatefulWidget {
  const UploadDocumentScreen({super.key});
  @override
  State<UploadDocumentScreen> createState() => _UploadDocumentScreenState();
}

class _UploadDocumentScreenState extends State<UploadDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  String _category = 'general';
  String? _filePath;
  bool _uploading = false;

  static const _categories = [
    'general', 'petition', 'evidence', 'judgment', 'contract', 'notice', 'other'
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('File picker: install file_picker and implement pickFiles()'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a file'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      await context.read<DocumentProvider>().uploadDocument({
        'file_path': _filePath!,
        'title': _titleCtrl.text.trim(),
        'category': _category,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Document uploaded successfully'),
              backgroundColor: AppColors.success),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed: $e'),
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
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _filePath != null
                          ? AppColors.gold
                          : AppColors.border,
                      style: BorderStyle.solid),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _filePath != null
                          ? Icons.check_circle_rounded
                          : Icons.cloud_upload_rounded,
                      color: _filePath != null
                          ? AppColors.success
                          : AppColors.textMuted,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _filePath != null
                          ? _filePath!.split('/').last
                          : 'Tap to select a file',
                      style: TextStyle(
                          color: _filePath != null
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
