import 'dart:convert';

import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Admin → Verification. Reuses the existing lawyer-verification endpoints
/// (GET /admin/lawyers?status=, GET /admin/lawyers/:id/document,
/// PUT /admin/lawyers/:id/verify) unchanged — AdminVerifyLawyer already
/// notifies the lawyer via the app's existing notification pipeline on
/// every status change, so nothing new is needed here for that either.
class AdminVerifyLawyersScreen extends StatefulWidget {
  const AdminVerifyLawyersScreen({super.key});
  @override
  State<AdminVerifyLawyersScreen> createState() => _AdminVerifyLawyersScreenState();
}

class _AdminVerifyLawyersScreenState extends State<AdminVerifyLawyersScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  String _status = 'pending';

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
      final res = await _repo.lawyers(status: _status);
      setState(() {
        _rows = (res['data'] as List?) ?? [];
        _loading = false;
      });
    } on AdminException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _viewDocument(dynamic lawyer) async {
    if ((lawyer['document_id'] ?? '').toString().isEmpty) {
      _showVerifyDialog(lawyer, hasDoc: false);
      return;
    }
    showDialog(
      context: context,
      builder: (_) => FutureBuilder<Map<String, dynamic>>(
        future: _repo.lawyerDocument(lawyer['id']).then((r) => (r['data'] as Map<String, dynamic>?) ?? {}),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Dialog(child: SizedBox(height: 200, width: 200, child: Center(child: CircularProgressIndicator())));
          }
          final d = snap.data!;
          final content = (d['file_content'] ?? '').toString();
          final mime = (d['mime_type'] ?? '').toString();
          final isImage = mime.startsWith('image/');
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(d['file_name'] ?? 'Document', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 12),
                if (isImage && content.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(content.contains(',') ? content.split(',').last : content),
                      fit: BoxFit.contain,
                      height: 360,
                      errorBuilder: (_, __, ___) => const Text('Could not render document preview.'),
                    ),
                  )
                else
                  Container(
                    height: 120,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kAdminBg, borderRadius: BorderRadius.circular(10)),
                    child: Text('Preview not available for $mime', style: const TextStyle(color: kAdminTextMuted)),
                  ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showVerifyDialog(lawyer, hasDoc: true, reject: true);
                      },
                      icon: const Icon(Icons.close_rounded, color: kAdminRed, size: 16),
                      label: const Text('Reject', style: TextStyle(color: kAdminRed)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: kAdminRed)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _verify(lawyer['id'], 'verified');
                      },
                      icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                      label: const Text('Approve', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: kAdminGreen),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _showVerifyDialog(dynamic lawyer, {required bool hasDoc, bool reject = false}) {
    if (!hasDoc && !reject) {
      // No document at all — surface that instead of pretending one exists.
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No verification document uploaded for this lawyer.')));
      return;
    }
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Verification'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Reason for rejection (optional)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _verify(lawyer['id'], 'rejected', reason: reasonCtrl.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: kAdminRed),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _verify(String id, String status, {String reason = ''}) async {
    try {
      await _repo.verifyLawyer(id, status, rejectionReason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(status == 'verified' ? 'Lawyer verified.' : 'Verification rejected.')));
      }
      _load();
    } on AdminException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/verify-lawyers',
      title: 'Verification',
      actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, children: [
            for (final s in const [('pending', 'Pending'), ('verified', 'Verified'), ('rejected', 'Rejected')])
              AdminFilterChip(
                  label: s.$2,
                  selected: _status == s.$1,
                  onTap: () {
                    setState(() => _status = s.$1);
                    _load();
                  }),
          ]),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            AdminEmptyState(message: _error!)
          else if (_rows.isEmpty)
            const AdminEmptyState()
          else
            ..._rows.map((l) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: kAdminBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kAdminBorder)),
                  child: Row(children: [
                    CircleAvatar(
                        backgroundColor: kAdminAccent,
                        child: Text((l['name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text(l['email'] ?? '', style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
                        Text(
                            'Bar Council: ${(l['bar_council_number'] ?? '').toString().isEmpty ? '—' : l['bar_council_number']} · Submitted ${fmtDate(l['created_at'])}',
                            style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
                      ]),
                    ),
                    AdminBadge(l['verification_status'] ?? '', AdminBadge.colorFor(l['verification_status'] ?? '')),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _viewDocument(l),
                      icon: const Icon(Icons.description_outlined, size: 15),
                      label: const Text('View Document'),
                    ),
                    if (_status == 'pending') ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check_circle_rounded, color: kAdminGreen),
                        onPressed: () => _verify(l['id'], 'verified'),
                      ),
                      IconButton(
                        tooltip: 'Reject',
                        icon: const Icon(Icons.cancel_rounded, color: kAdminRed),
                        onPressed: () => _showVerifyDialog(l, hasDoc: true, reject: true),
                      ),
                    ],
                  ]),
                )),
        ]),
      ),
    );
  }
}
