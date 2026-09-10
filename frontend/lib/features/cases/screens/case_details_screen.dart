import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../../documents/widgets/document_upload_sheet.dart';
import '../../hearings/utils/hearing_status.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _brownLight = Color(0xFF3D2C8D);
const _gold = Color(0xFFB8860B);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class CaseDetailsScreen extends StatefulWidget {
  final String caseId;
  const CaseDetailsScreen({super.key, required this.caseId});
  @override
  State<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends State<CaseDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _case;
  List<dynamic> _hearings = [];
  List<dynamic> _documents = [];
  List<dynamic> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Notes tab has its own bottom action bar (note input + Send); the
    // floating Change Status button would sit on top of it and overflow, so
    // it's hidden there and offered inline in the Notes bar instead.
    _tabController.addListener(() => setState(() {}));
    _loadCase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCase() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/cases/${widget.caseId}');
      final hearingsRes =
          await DioClient.instance.get('/cases/${widget.caseId}/hearings');
      final notesRes =
          await DioClient.instance.get('/cases/${widget.caseId}/notes');
      // _documents was declared but never fetched from anywhere — the
      // Documents tab always rendered its permanently-empty initial value,
      // so an upload could succeed on the server and still look like nothing
      // happened.
      final documentsRes = await DioClient.instance
          .get('/documents', queryParameters: {'case_id': widget.caseId});
      setState(() {
        _case = res.data['data'];
        _hearings = hearingsRes.data['data'] ?? [];
        _notes = notesRes.data['data'] ?? [];
        _documents = documentsRes.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return const Color(0xFF2E8B57);
      case 'pending':
        return _gold;
      case 'won':
        return _brown;
      case 'lost':
        return const Color(0xFFD9534F);
      case 'closed':
        return _brownLight;
      default:
        return const Color(0xFF4A90D9);
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'active':
        return Icons.play_circle_rounded;
      case 'pending':
        return Icons.pending_rounded;
      case 'won':
        return Icons.emoji_events_rounded;
      case 'lost':
        return Icons.cancel_rounded;
      case 'closed':
        return Icons.lock_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  void _showStatusDialog() {
    final status = _case?['status'] ?? 'active';
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
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Change Case Status',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 18,
                    fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        if (status != 'active')
          _StatusOption(
              icon: Icons.play_circle_rounded,
              label: 'Mark as Active',
              subtitle: 'Case is being worked on',
              color: const Color(0xFF2E8B57),
              onTap: () {
                Navigator.pop(context);
                _updateStatus('active');
              }),
        if (status != 'won')
          _StatusOption(
              icon: Icons.emoji_events_rounded,
              label: 'Mark as Won 🏆',
              subtitle: 'Case won! Add feedback',
              color: _brown,
              onTap: () {
                Navigator.pop(context);
                _showWonDialog();
              }),
        if (status != 'lost')
          _StatusOption(
              icon: Icons.cancel_rounded,
              label: 'Mark as Lost',
              subtitle: 'Add reason for client',
              color: const Color(0xFFD9534F),
              onTap: () {
                Navigator.pop(context);
                _showLostDialog();
              }),
        if (status != 'pending')
          _StatusOption(
              icon: Icons.pending_rounded,
              label: 'Mark as Pending',
              subtitle: 'Case needs attention',
              color: _gold,
              onTap: () {
                Navigator.pop(context);
                _updateStatus('pending');
              }),
        if (status != 'closed')
          _StatusOption(
              icon: Icons.lock_rounded,
              label: 'Close Case',
              subtitle: 'Permanently close',
              color: _brownLight,
              onTap: () {
                Navigator.pop(context);
                _showCloseDialog();
              }),
        const SizedBox(height: 20),
      ]),
    );
  }

  void _showWonDialog() {
    final feedbackCtrl = TextEditingController();
    bool loading = false;
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
                  backgroundColor: _bgCard,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Row(children: [
                    Icon(Icons.emoji_events_rounded, color: _brown, size: 28),
                    const SizedBox(width: 10),
                    Text('Case Won! 🏆',
                        style: TextStyle(
                            color: _brown, fontWeight: FontWeight.w700))
                  ]),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Write feedback for your client.',
                        style: TextStyle(color: _textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: feedbackCtrl,
                        maxLines: 4,
                        style: const TextStyle(color: _textPri),
                        decoration: _inputDeco(
                            'Feedback / Message for client...',
                            Icons.message_rounded)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel',
                            style: TextStyle(color: _textMuted))),
                    ElevatedButton(
                      onPressed: loading
                          ? null
                          : () async {
                              setS(() => loading = true);
                              await _updateStatus('won',
                                  feedback: feedbackCtrl.text);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _brown,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Mark as Won',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ],
                )));
  }

  void _showLostDialog() {
    final reasonCtrl = TextEditingController();
    bool loading = false;
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
                  backgroundColor: _bgCard,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Row(children: [
                    Icon(Icons.cancel_rounded,
                        color: Color(0xFFD9534F), size: 28),
                    SizedBox(width: 10),
                    Text('Case Lost',
                        style: TextStyle(
                            color: Color(0xFFD9534F),
                            fontWeight: FontWeight.w700))
                  ]),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Please provide reason for the client.',
                        style: TextStyle(color: _textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: reasonCtrl,
                        maxLines: 4,
                        style: const TextStyle(color: _textPri),
                        decoration: _inputDeco('Reason why case was lost...',
                            Icons.notes_rounded)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel',
                            style: TextStyle(color: _textMuted))),
                    ElevatedButton(
                      onPressed: loading
                          ? null
                          : () async {
                              setS(() => loading = true);
                              await _updateStatus('lost',
                                  reason: reasonCtrl.text);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9534F),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Mark as Lost',
                              style: TextStyle(color: Colors.white)),
                    ),
                  ],
                )));
  }

  void _showCloseDialog() {
    final reasonCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Close Case',
                  style:
                      TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Are you sure you want to close this case?',
                    style: TextStyle(color: _textMuted)),
                const SizedBox(height: 12),
                TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: _textPri),
                    decoration:
                        _inputDeco('Reason for closing', Icons.notes_rounded)),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: _textMuted))),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _updateStatus('closed', reason: reasonCtrl.text);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _brownLight,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Close Case',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ));
  }

  void _showUploadDialog() {
    showDocumentUploadSheet(
      context,
      caseId: widget.caseId,
      description: 'Document for case: ${_case?['case_title']}',
      onUploaded: _loadCase,
    );
  }

  Future<void> _updateStatus(String status,
      {String? feedback, String? reason}) async {
    try {
      await DioClient.instance.put('/cases/${widget.caseId}', data: {
        'status': status,
        'won_feedback': feedback ?? '',
        'lost_reason': reason ?? '',
        'closed_reason': status == 'closed' ? (reason ?? '') : '',
      });
      HapticFeedback.heavyImpact();
      _loadCase();
      if (mounted) {
        String msg;
        Color color;
        switch (status) {
          case 'won':
            msg = 'Case marked as Won!';
            color = _brown;
            break;
          case 'lost':
            msg = 'Case marked as Lost';
            color = const Color(0xFFD9534F);
            break;
          case 'closed':
            msg = 'Case closed';
            color = _brownLight;
            break;
          case 'pending':
            msg = 'Case marked as Pending';
            color = _gold;
            break;
          default:
            msg = 'Status updated to $status';
            color = const Color(0xFF2E8B57);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      debugPrint('Status update error: $e');
    }
  }

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

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(
          backgroundColor: _bg,
          body: Center(child: CircularProgressIndicator(color: _brown)));

    final status = _case?['status'] ?? 'active';
    final statusColor = _statusColor(status);
    final statusIcon = _statusIcon(status);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _brown,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_case?['case_title'] ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(_case?['client_name'] ?? '',
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11)),
          ]),
          actions: [
            // A Won case is read-only — no edit, and no further status
            // change either (the backend rejects both regardless, but the
            // buttons are removed too so there's nothing to tap in the
            // first place).
            if (status != 'won')
              IconButton(
                  icon: const Icon(Icons.edit_rounded, color: Color(0xFFFFD700)),
                  onPressed: () => context
                      .push('/cases/${widget.caseId}/edit')
                      .then((_) => _loadCase())),
            IconButton(
                icon: const Icon(Icons.upload_file_rounded,
                    color: Color(0xFFFFD700)),
                onPressed: _showUploadDialog),
            if (status != 'won')
              IconButton(
                  icon: Icon(statusIcon, color: Colors.white),
                  onPressed: _showStatusDialog),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(90),
            child: Column(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: _brownDark,
                child: Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(statusIcon, color: statusColor, size: 12),
                      const SizedBox(width: 4),
                      Text(status.toUpperCase(),
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  if ((_case?['court_name'] ?? '').isNotEmpty)
                    Expanded(
                        child: Text(_case!['court_name'],
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                ]),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFFFD700),
                indicatorWeight: 2.5,
                labelColor: const Color(0xFFFFD700),
                unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Hearings'),
                  Tab(text: 'Documents'),
                  Tab(text: 'Notes')
                ],
              ),
            ]),
          ),
        ),
        body: Container(
          color: _bg,
          child: TabBarView(
            controller: _tabController,
            children: [
              _DetailsTab(caseData: _case!),
              _HearingsTab(
                  hearings: _hearings,
                  caseId: widget.caseId,
                  onRefresh: _loadCase),
              _DocumentsTab(documents: _documents, onUpload: _showUploadDialog),
              _NotesTab(
                  notes: _notes,
                  caseId: widget.caseId,
                  onRefresh: _loadCase,
                  showChangeStatus: status != 'won' &&
                      status != 'lost' &&
                      status != 'closed',
                  onChangeStatus: _showStatusDialog),
            ],
          ),
        ), // Container
        floatingActionButton: status != 'won' &&
                status != 'lost' &&
                status != 'closed' &&
                _tabController.index != 3
                ? FloatingActionButton.extended(
                    onPressed: _showStatusDialog,
                    backgroundColor: _brown,
                    icon: Icon(statusIcon, color: Colors.white),
                    label: const Text('Change Status',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  )
                : null,
      ),
    );
  }
}

// ── Details Tab ────────────────────────────────────
class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> caseData;
  const _DetailsTab({required this.caseData});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        _InfoCard(title: 'Case Information', icon: Icons.gavel_rounded, items: [
          _InfoRow('Case Number', caseData['case_number'] ?? '-'),
          _InfoRow('Case Type', caseData['case_type'] ?? '-'),
          _InfoRow(
              'Priority', (caseData['priority'] ?? 'normal').toUpperCase()),
          _InfoRow('Status', (caseData['status'] ?? 'active').toUpperCase()),
        ]),
        const SizedBox(height: 12),
        _InfoCard(
            title: 'Court Details',
            icon: Icons.account_balance_rounded,
            items: [
              _InfoRow('Court Name', caseData['court_name'] ?? '-'),
              _InfoRow('Court Location', caseData['court_location'] ?? '-'),
              _InfoRow('Judge Name', caseData['judge_name'] ?? '-'),
            ]),
        const SizedBox(height: 12),
        _InfoCard(title: 'Opposite Party', icon: Icons.people_rounded, items: [
          _InfoRow('Party Name', caseData['opposite_party'] ?? '-'),
          _InfoRow('Lawyer', caseData['opposite_lawyer'] ?? '-'),
        ]),
        if ((caseData['description'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoCard(
              title: 'Description',
              icon: Icons.description_rounded,
              items: [
                _InfoRow('Details', caseData['description']),
              ]),
        ],
        if ((caseData['won_feedback'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _brown.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                      color: _brown.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.emoji_events_rounded, color: _brown, size: 18),
                const SizedBox(width: 8),
                Text('Won Feedback',
                    style:
                        TextStyle(color: _brown, fontWeight: FontWeight.w700))
              ]),
              const SizedBox(height: 8),
              Text(caseData['won_feedback'],
                  style: const TextStyle(color: _textMuted, height: 1.5)),
            ]),
          ),
        ],
        if ((caseData['lost_reason'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: const Color(0xFFD9534F).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                      color: _brown.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.cancel_rounded, color: Color(0xFFD9534F), size: 18),
                SizedBox(width: 8),
                Text('Reason for Loss',
                    style: TextStyle(
                        color: Color(0xFFD9534F), fontWeight: FontWeight.w700))
              ]),
              const SizedBox(height: 8),
              Text(caseData['lost_reason'],
                  style: const TextStyle(color: _textMuted, height: 1.5)),
            ]),
          ),
        ],
        const SizedBox(height: 80),
      ]);
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_InfoRow> items;
  const _InfoCard(
      {required this.title, required this.icon, required this.items});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: _brown, borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, color: Colors.white, size: 13)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: _brown, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          Divider(color: _border, height: 20, thickness: 0.6),
          ...items,
        ]),
      );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPri,
                      fontSize: 13,
                      fontWeight: FontWeight.w500))),
        ]),
      );
}

// ── Hearings Tab ───────────────────────────────────
class _HearingsTab extends StatelessWidget {
  final List<dynamic> hearings;
  final String caseId;
  final VoidCallback onRefresh;
  const _HearingsTab(
      {required this.hearings, required this.caseId, required this.onRefresh});

  void _addNextHearing(BuildContext context) {
    context
        .push('/hearings/add', extra: {'caseId': caseId})
        .then((_) => onRefresh());
  }

  // The hearing date can be postponed and re-added multiple times, so the
  // soonest still-scheduled hearing is flagged "NEXT" to distinguish it from
  // the rest of the history rather than replacing/removing older entries.
  Map<String, dynamic>? get _nextHearing {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final upcoming = hearings.where((h) {
      if (h['status'] != 'scheduled') return false;
      final d = DateTime.tryParse(h['hearing_date'] ?? '');
      return d != null && !d.isBefore(todayDate);
    }).toList()
      ..sort((a, b) => DateTime.parse(a['hearing_date'])
          .compareTo(DateTime.parse(b['hearing_date'])));
    return upcoming.isEmpty ? null : upcoming.first as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextHearing;
    if (hearings.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.event_rounded,
            color: _brownLight.withValues(alpha: 0.4), size: 52),
        const SizedBox(height: 12),
        const Text('No hearings yet', style: TextStyle(color: _textMuted)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _addNextHearing(context),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Schedule Hearing',
              style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _addNextHearing(context),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Add Next Hearing',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _brown,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ),
      Expanded(
        child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: hearings.length,
              itemBuilder: (_, i) {
                final h = hearings[i];
                final isNext = next != null && h['id'] == next['id'];
                final statusInfo = hearingStatusInfo(h);
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => context
                      .push('/hearings/${h['id']}')
                      .then((_) => onRefresh()),
                  child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: isNext ? _brown : _border,
                          width: isNext ? 1.4 : 0.8),
                      boxShadow: [
                        BoxShadow(
                            color: _brown.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2))
                      ]),
                  child: Row(children: [
                    Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.event_rounded,
                            color: Color(0xFF4A90D9), size: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Text(h['hearing_date'] ?? '',
                                style: const TextStyle(
                                    color: _brown,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            if (isNext) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF2E8B57),
                                    borderRadius: BorderRadius.circular(6)),
                                child: const Text('NEXT',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ]),
                          if ((h['court_name'] ?? '').isNotEmpty)
                            Text(h['court_name'],
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 12)),
                          if ((h['purpose'] ?? '').isNotEmpty)
                            Text(h['purpose'],
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 12)),
                        ])),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: statusInfo.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(statusInfo.label,
                          style: TextStyle(
                              color: statusInfo.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  ),
                );
              },
        ),
      ),
    ]);
  }
}

// ── Documents Tab ──────────────────────────────────
class _DocumentsTab extends StatelessWidget {
  final List<dynamic> documents;
  final VoidCallback onUpload;
  const _DocumentsTab({required this.documents, required this.onUpload});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        floatingActionButton: FloatingActionButton(
          onPressed: onUpload,
          backgroundColor: _brown,
          child: const Icon(Icons.upload_file_rounded, color: Colors.white),
        ),
        body: documents.isEmpty
            ? Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Icon(Icons.folder_open_rounded,
                        color: _brownLight.withValues(alpha: 0.4), size: 52),
                    const SizedBox(height: 12),
                    const Text('No documents yet',
                        style: TextStyle(color: _textMuted)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: onUpload,
                      icon:
                          const Icon(Icons.upload_rounded, color: Colors.white),
                      label: const Text('Upload Document',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _brown,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                  ]))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: documents.length,
                itemBuilder: (_, i) {
                  final d = documents[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => context.push('/documents/${d['id']}'),
                    child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: _bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border, width: 0.8),
                        boxShadow: [
                          BoxShadow(
                              color: _brown.withValues(alpha: 0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]),
                    child: Row(children: [
                      Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                              color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.description_rounded,
                              color: Color(0xFFD9534F), size: 24)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(d['file_name'] ?? '',
                                style: const TextStyle(
                                    color: _textPri,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(d['category'] ?? '',
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 12)),
                          ])),
                    ]),
                    ),
                  );
                },
              ),
      );
}

// ── Notes Tab ──────────────────────────────────────
class _NotesTab extends StatefulWidget {
  final List<dynamic> notes;
  final String caseId;
  final VoidCallback onRefresh;
  final bool showChangeStatus;
  final VoidCallback onChangeStatus;
  const _NotesTab(
      {required this.notes,
      required this.caseId,
      required this.onRefresh,
      required this.showChangeStatus,
      required this.onChangeStatus});
  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> {
  final _noteCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    if (_noteCtrl.text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await DioClient.instance.post('/cases/${widget.caseId}/notes', data: {
        'note': _noteCtrl.text.trim(),
        'is_private': false,
      });
      _noteCtrl.clear();
      widget.onRefresh();
    } catch (e) {
      debugPrint('Note error: $e');
    }
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: widget.notes.isEmpty
              ? const Center(
                  child:
                      Text('No notes yet', style: TextStyle(color: _textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.notes.length,
                  itemBuilder: (_, i) {
                    final n = widget.notes[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: _bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border, width: 0.8),
                          boxShadow: [
                            BoxShadow(
                                color: _brown.withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n['note'] ?? '',
                                style: const TextStyle(
                                    color: _textPri,
                                    fontSize: 14,
                                    height: 1.5)),
                            const SizedBox(height: 6),
                            Text(n['created_by'] ?? '',
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11)),
                          ]),
                    );
                  }),
        ),
        SafeArea(
          top: false,
          child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _bgCard,
              border: Border(top: BorderSide(color: _border, width: 0.8)),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (widget.showChangeStatus) ...[
              GestureDetector(
                onTap: widget.onChangeStatus,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _brown.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: _brown.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.sync_alt_rounded,
                      color: _brown, size: 20),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
                child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border, width: 0.8)),
              child: TextField(
                controller: _noteCtrl,
                style: const TextStyle(color: _textPri, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Add a note...',
                  hintStyle: TextStyle(color: _textMuted),
                  border: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _addNote,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF150E3D), Color(0xFF3D2C8D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ]),
          ),
        ),
      ]);
}

// ── Helper Widgets ─────────────────────────────────
class _StatusOption extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _StatusOption(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22)),
        title: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: _textMuted, fontSize: 12)),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
      );
}
