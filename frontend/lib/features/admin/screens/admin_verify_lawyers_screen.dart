import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF5ECD7);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF5C3317);
const _brownDark = Color(0xFF3D2008);
const _border = Color(0xFFD4B896);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF8B5E3C);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);

class AdminVerifyLawyersScreen extends StatefulWidget {
  const AdminVerifyLawyersScreen({super.key});
  @override
  State<AdminVerifyLawyersScreen> createState() =>
      _AdminVerifyLawyersScreenState();
}

class _AdminVerifyLawyersScreenState extends State<AdminVerifyLawyersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _pending = [];
  List<dynamic> _verified = [];
  List<dynamic> _rejected = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/admin/lawyers');
      final all = res.data['data'] as List? ?? [];
      setState(() {
        _pending =
            all.where((l) => l['verification_status'] == 'pending').toList();
        _verified =
            all.where((l) => l['verification_status'] == 'verified').toList();
        _rejected =
            all.where((l) => l['verification_status'] == 'rejected').toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String userId, String status,
      {String? reason}) async {
    try {
      await DioClient.instance.put('/admin/lawyers/$userId/verify', data: {
        'verification_status': status,
        'rejection_reason': reason ?? '',
      });
      HapticFeedback.heavyImpact();
      _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Lawyer ${status == 'verified' ? 'approved' : 'rejected'}!'),
            backgroundColor: status == 'verified' ? _green : _red,
            behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red));
    }
  }

  Future<void> _viewDocument(String userId) async {
    try {
      final res = await DioClient.instance.get('/admin/lawyers/$userId/document');
      final d = res.data['data'];
      final content = (d['file_content'] ?? '').toString();
      final mime = (d['mime_type'] ?? '').toString();
      if (!mounted) return;
      if (content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Document could not be loaded'),
            backgroundColor: _red));
        return;
      }
      final raw = content.contains(',') ? content.split(',').last : content;
      showDialog(
          context: context,
          builder: (_) => Dialog(
              backgroundColor: _bgCard,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (mime.startsWith('image/'))
                      Image.memory(base64Decode(raw), fit: BoxFit.contain)
                    else
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Preview not available for this file type',
                              style: TextStyle(color: _textMuted))),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close',
                            style: TextStyle(color: _brown))),
                  ]))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red));
      }
    }
  }

  void _showVerifyDialog(dynamic lawyer) {
    final reasonCtrl = TextEditingController();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: _bgCard,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
              padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24),
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
                    Text(lawyer['name'] ?? 'Lawyer',
                        style: const TextStyle(
                            color: _textPri,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text(lawyer['email'] ?? '',
                        style:
                            const TextStyle(color: _textMuted, fontSize: 12)),
                    const SizedBox(height: 16),
                    // Verification details
                    _VerifyRow('Bar Council No',
                        lawyer['bar_council_number'] ?? 'Not provided'),
                    _VerifyRow('State', lawyer['state'] ?? '-'),
                    _VerifyRow('Experience',
                        '${lawyer['experience_years'] ?? 0} years'),
                    _VerifyRow('Practice Areas', lawyer['speciality'] ?? '-'),
                    const SizedBox(height: 12),
                    if ((lawyer['document_id'] ?? '').toString().isNotEmpty)
                      OutlinedButton.icon(
                          onPressed: () => _viewDocument(lawyer['id']),
                          icon: const Icon(Icons.description_outlined,
                              color: _brown, size: 18),
                          label: const Text('View Verification Document',
                              style: TextStyle(
                                  color: _brown, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _border),
                              minimumSize: const Size(double.infinity, 44),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))))
                    else
                      const Text('No verification document uploaded',
                          style: TextStyle(color: _textMuted, fontSize: 12)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: reasonCtrl,
                        style: const TextStyle(color: _textPri, fontSize: 13),
                        decoration: InputDecoration(
                            labelText: 'Rejection reason (if rejecting)',
                            labelStyle: const TextStyle(
                                color: _textMuted, fontSize: 12),
                            filled: true,
                            fillColor: _bg,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: _border)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: _border, width: 0.8)))),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _updateStatus(lawyer['id'], 'verified');
                        },
                        icon: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16),
                        label: const Text('Approve',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _updateStatus(lawyer['id'], 'rejected',
                              reason: reasonCtrl.text);
                        },
                        icon: const Icon(Icons.close_rounded,
                            color: _red, size: 16),
                        label: const Text('Reject',
                            style: TextStyle(
                                color: _red, fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                      )),
                    ]),
                  ]),
            ));
  }

  Widget _VerifyRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPri,
                      fontWeight: FontWeight.w600,
                      fontSize: 13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_brown, _brownDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                    child: Row(children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                          onPressed: () => context.pop()),
                      const Expanded(
                          child: Text('Lawyer Verification',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          icon: const Icon(Icons.refresh_rounded,
                              color: Colors.white),
                          onPressed: _load),
                    ])),
                TabBar(
                    controller: _tabCtrl,
                    indicatorColor: const Color(0xFFFFD700),
                    indicatorWeight: 3,
                    labelColor: const Color(0xFFFFD700),
                    unselectedLabelColor: Colors.white60,
                    tabs: [
                      Tab(text: 'Pending (${_pending.length})'),
                      Tab(text: 'Verified (${_verified.length})'),
                      Tab(text: 'Rejected (${_rejected.length})')
                    ]),
              ])),
        ),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : TabBarView(controller: _tabCtrl, children: [
                    _buildList(_pending, showActions: true),
                    _buildList(_verified, color: _green),
                    _buildList(_rejected, color: _red),
                  ])),
      ]),
    );
  }

  Widget _buildList(List<dynamic> list,
      {bool showActions = false, Color color = _brown}) {
    if (list.isEmpty)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.people_rounded, color: _brown.withValues(alpha: 0.3), size: 56),
        const SizedBox(height: 12),
        const Text('No lawyers here',
            style: TextStyle(color: _textMuted, fontSize: 15)),
      ]));
    return RefreshIndicator(
        color: _brown,
        backgroundColor: _bgCard,
        onRefresh: _load,
        child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final l = list[i];
              final initials = (l['name'] ?? 'L')[0].toUpperCase();
              return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                            color: _brown.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ]),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [_brown, _brownDark]),
                                  shape: BoxShape.circle),
                              child: Center(
                                  child: Text(initials,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 20)))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(l['name'] ?? '',
                                    style: const TextStyle(
                                        color: _textPri,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                Text(l['email'] ?? '',
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 12)),
                                Text(
                                    l['bar_council_number'] ??
                                        'No bar council number',
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ])),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                  (l['verification_status'] ?? 'pending')
                                      .toUpperCase(),
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800))),
                        ]),
                        if (showActions) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: GestureDetector(
                                    onTap: () =>
                                        _updateStatus(l['id'], 'verified'),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                            color: _green,
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_rounded,
                                                  color: Colors.white,
                                                  size: 14),
                                              SizedBox(width: 4),
                                              Text('Approve',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12)),
                                            ])))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: GestureDetector(
                                    onTap: () => _showVerifyDialog(l),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                            color: _bgCard,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(color: _border)),
                                        child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.info_rounded,
                                                  color: _brown, size: 14),
                                              SizedBox(width: 4),
                                              Text('Review',
                                                  style: TextStyle(
                                                      color: _brown,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12)),
                                            ])))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: GestureDetector(
                                    onTap: () =>
                                        _updateStatus(l['id'], 'rejected'),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                            color: _red.withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: _red.withValues(alpha: 0.3))),
                                        child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.close_rounded,
                                                  color: _red, size: 14),
                                              SizedBox(width: 4),
                                              Text('Reject',
                                                  style: TextStyle(
                                                      color: _red,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12)),
                                            ])))),
                          ]),
                        ],
                      ]));
            }));
  }
}
