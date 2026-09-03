import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/dio_client.dart';

// Shared with cases/screens/case_details_screen.dart so client-scoped and
// case-scoped document uploads go through the exact same picker, validation
// and /documents/upload contract instead of two diverging implementations.
const Map<String, List<String>> documentUploadAllowedExtByType = {
  'PDF': ['pdf'],
  'Excel': ['xls', 'xlsx', 'csv'],
  'Photo': ['jpg', 'jpeg', 'png', 'webp'],
  'Video': ['mp4', 'mov', 'avi', 'mkv', 'webm'],
};
const int documentUploadMaxFileBytes = 6 * 1024 * 1024;
const Map<String, String> documentUploadExtToMime = {
  'pdf': 'application/pdf',
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
};
String documentUploadExtOf(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i == -1 || i == fileName.length - 1) return '';
  return fileName.substring(i + 1).toLowerCase();
}
String documentUploadFormatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _textMuted),
      prefixIcon: Icon(icon, color: _brown, size: 20),
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
    );

/// Opens the shared "Upload Document" bottom sheet. Pass exactly one of
/// [caseId] / [clientId] so the uploaded document is associated with the
/// right record; [description] is stored on the document for context.
/// [onUploaded] is called after a successful upload so the caller can
/// refresh its list.
void showDocumentUploadSheet(
  BuildContext context, {
  String? caseId,
  String? clientId,
  String description = '',
  required VoidCallback onUploaded,
}) {
  final nameCtrl = TextEditingController();
  String category = 'General';
  String selectedType = 'PDF';
  PlatformFile? pickedFile;
  bool picking = false;
  bool loading = false;

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
          final allowed =
              documentUploadAllowedExtByType[selectedType] ?? const <String>[];
          final result = await FilePicker.platform.pickFiles(
              type: FileType.custom, allowedExtensions: allowed, withData: true);
          if (result == null || result.files.isEmpty) return;
          final f = result.files.single;
          final ext = documentUploadExtOf(f.name);
          if (!allowed.contains(ext)) {
            if (ctx.mounted)
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(
                      'Unsupported file type for $selectedType. Allowed: ${allowed.join(', ').toUpperCase()}'),
                  backgroundColor: const Color(0xFFD9534F)));
            return;
          }
          if (f.size > documentUploadMaxFileBytes) {
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
                const SizedBox(height: 4),
                const Text('Pick a file from this device',
                    style: TextStyle(color: _textMuted, fontSize: 12)),
                const SizedBox(height: 16),
                Row(
                    children: documentUploadAllowedExtByType.keys
                        .expand((t) => [
                              _FileTypeChip(
                                label: t,
                                color:
                                    selectedType == t ? _brown : const Color(0xFF3D2C8D),
                                onTap: () => setS(() {
                                  selectedType = t;
                                  pickedFile = null;
                                }),
                              ),
                              const SizedBox(width: 8),
                            ])
                        .toList()
                      ..removeLast()),
                const SizedBox(height: 14),
                TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: _textPri),
                    decoration: _inputDeco(
                        'Document Name *', Icons.description_outlined)),
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
                                (documentUploadAllowedExtByType[selectedType] ?? [])
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
                            child: const Icon(Icons.insert_drive_file_rounded,
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
                              Text(documentUploadFormatSize(pickedFile!.size),
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
                      color: _bg,
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
                      'Petition',
                      'Court Order',
                      'Agreement',
                      'Evidence',
                      'Affidavit',
                      'Other'
                    ]
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setS(() => category = v!),
                  )),
                ),
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
                            setS(() => loading = true);
                            try {
                              final ext = documentUploadExtOf(file.name);
                              await DioClient.instance
                                  .post('/documents/upload', data: {
                                'file_name': nameCtrl.text.trim(),
                                'file_content': base64Encode(file.bytes!),
                                'file_type': ext,
                                'file_size': file.size,
                                'mime_type': documentUploadExtToMime[ext] ??
                                    'application/octet-stream',
                                'category': category,
                                if (caseId != null) 'case_id': caseId,
                                if (clientId != null) 'client_id': clientId,
                                'description': description,
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              onUploaded();
                              HapticFeedback.heavyImpact();
                              if (context.mounted)
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text('Document uploaded!'),
                                  backgroundColor: Color(0xFF2E8B57),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(12))),
                                ));
                            } catch (e) {
                              setS(() => loading = false);
                              if (context.mounted)
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(DioClient.describeError(e)),
                                  backgroundColor: const Color(0xFFD9534F),
                                ));
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

class _FileTypeChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _FileTypeChip({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
          child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ));
}
