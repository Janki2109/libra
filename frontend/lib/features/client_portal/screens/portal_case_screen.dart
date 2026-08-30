import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../providers/portal_provider.dart';

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _greenLight = Color(0xFF1A9E72);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);
const _gold = Color(0xFFD4A017);
const _blue = Color(0xFF4A90D9);
const _red = Color(0xFFD9534F);

class PortalCaseScreen extends StatefulWidget {
  const PortalCaseScreen({super.key});
  @override
  State<PortalCaseScreen> createState() => _PortalCaseScreenState();
}

class _PortalCaseScreenState extends State<PortalCaseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<PortalProvider>().refreshCases());
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return _green;
      case 'won':
        return _gold;
      case 'lost':
        return _red;
      case 'pending':
        return _gold;
      case 'closed':
        return _textMuted;
      default:
        return _greenLight;
    }
  }

  void _openCaseDetail(BuildContext context, Map<String, dynamic> c) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _CaseDetailScreen(caseData: c),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortalProvider>();
    final cases = provider.cases;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
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
                        child: Text('My Cases',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text('${cases.length} cases',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                  ]),
                )),
          ),

          Expanded(
            child: provider.loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : cases.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: Icon(Icons.gavel_rounded,
                                    color: _green.withValues(alpha: 0.5), size: 40)),
                            const SizedBox(height: 16),
                            const Text('No Cases Yet',
                                style: TextStyle(
                                    color: _textPri,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text(
                                'Your cases will appear here once your lawyer files them.',
                                style:
                                    TextStyle(color: _textMuted, fontSize: 13),
                                textAlign: TextAlign.center),
                          ]))
                    : RefreshIndicator(
                        color: _green,
                        backgroundColor: _bgCard,
                        onRefresh: () => provider.refreshCases(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: cases.length,
                          itemBuilder: (_, i) {
                            final c = cases[i];
                            final status = c['status'] ?? 'active';
                            final sc = _statusColor(status);
                            return GestureDetector(
                              onTap: () => _openCaseDetail(context, c),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                    color: _bgCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border:
                                        Border.all(color: sc.withValues(alpha: 0.25)),
                                    boxShadow: [
                                      BoxShadow(
                                          color: _green.withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ]),
                                child: Column(children: [
                                  Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                          color: sc,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(16)))),
                                  Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                    color: sc.withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10)),
                                                child: Icon(Icons.gavel_rounded,
                                                    color: sc, size: 22)),
                                            const SizedBox(width: 12),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(c['case_title'] ?? '',
                                                      style: const TextStyle(
                                                          color: _textPri,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 14)),
                                                  if ((c['case_number'] ?? '')
                                                      .isNotEmpty)
                                                    Text(
                                                        'Case No: ${c['case_number']}',
                                                        style: const TextStyle(
                                                            color: _textMuted,
                                                            fontSize: 11)),
                                                  if ((c['cnr_number'] ?? '')
                                                      .isNotEmpty)
                                                    Text(
                                                        'CNR: ${c['cnr_number']}',
                                                        style: const TextStyle(
                                                            color: _blue,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                ])),
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                        color:
                                                            sc.withValues(alpha: 0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                        border: Border.all(
                                                            color:
                                                                sc.withValues(
                                                                    alpha: 0.3))),
                                                    child: Text(
                                                        status.toUpperCase(),
                                                        style: TextStyle(
                                                            color: sc,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  const Icon(
                                                      Icons
                                                          .arrow_forward_ios_rounded,
                                                      color: _textMuted,
                                                      size: 12),
                                                ]),
                                          ]),
                                          if ((c['court_name'] ?? '')
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Divider(
                                                color: _border,
                                                height: 1,
                                                thickness: 0.6),
                                            const SizedBox(height: 10),
                                            Row(children: [
                                              const Icon(
                                                  Icons.account_balance_rounded,
                                                  color: _textMuted,
                                                  size: 14),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                  child: Text(
                                                      c['court_name'] ?? '',
                                                      style: const TextStyle(
                                                          color: _textMuted,
                                                          fontSize: 12))),
                                              if ((c['case_type'] ?? '')
                                                  .isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                      color: _green
                                                          .withValues(alpha: 0.08),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6)),
                                                  child: Text(c['case_type'],
                                                      style: const TextStyle(
                                                          color: _green,
                                                          fontSize: 11)),
                                                ),
                                            ]),
                                          ],
                                          // Tap to view details hint
                                          const SizedBox(height: 8),
                                          Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                Text(
                                                    'Tap to view details & hearings →',
                                                    style: TextStyle(
                                                        color: _green
                                                            .withValues(alpha: 0.6),
                                                        fontSize: 10,
                                                        fontStyle:
                                                            FontStyle.italic)),
                                              ]),
                                        ],
                                      )),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}

// ── Case Detail Screen ─────────────────────────────
class _CaseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> caseData;
  const _CaseDetailScreen({required this.caseData});
  @override
  State<_CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<_CaseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _hearings = [];
  List<dynamic> _documents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadDetails();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DioClient.instance.get('/portal/my-hearings'),
        DioClient.instance.get('/portal/my-documents'),
      ]);
      final allHearings = results[0].data['data'] as List? ?? [];
      final allDocs = results[1].data['data'] as List? ?? [];
      setState(() {
        // Filter by case_id OR case_title as fallback
        var filteredH = allHearings
            .where((h) => h['case_id'] == widget.caseData['id'])
            .toList();
        if (filteredH.isEmpty &&
            (widget.caseData['case_title'] ?? '').isNotEmpty) {
          filteredH = allHearings
              .where((h) =>
                  (h['case_title'] ?? '') ==
                  (widget.caseData['case_title'] ?? ''))
              .toList();
        }
        _hearings = filteredH;
        var filteredD = allDocs
            .where((d) => d['case_id'] == widget.caseData['id'])
            .toList();
        _documents = filteredD;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return _green;
      case 'won':
        return _gold;
      case 'lost':
        return _red;
      case 'pending':
        return _gold;
      default:
        return _textMuted;
    }
  }

  Color _hearingStatusColor(String s) {
    switch (s) {
      case 'completed':
        return _green;
      case 'cancelled':
        return _red;
      case 'adjourned':
        return _gold;
      default:
        return _blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.caseData;
    final sc = _statusColor(c['status'] ?? 'active');

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
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
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context)),
                    Expanded(
                        child: Text(c['case_title'] ?? 'Case Details',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: sc.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          (c['status'] ?? 'active').toString().toUpperCase(),
                          style: TextStyle(
                              color: sc,
                              fontWeight: FontWeight.w800,
                              fontSize: 11)),
                    ),
                  ]),
                ),
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: const Color(0xFFFFD700),
                  indicatorWeight: 3,
                  labelColor: const Color(0xFFFFD700),
                  unselectedLabelColor: Colors.white60,
                  tabs: const [
                    Tab(text: 'Details'),
                    Tab(text: 'Timeline'),
                    Tab(text: 'Hearings'),
                    Tab(text: 'Documents'),
                  ],
                ),
              ])),
        ),

        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : TabBarView(controller: _tabCtrl, children: [
                    _buildDetailsTab(c),
                    _buildTimelineTab(c),
                    _buildHearingsTab(),
                    _buildDocumentsTab(),
                  ])),
      ]),
    );
  }

  // ── Details Tab ──────────────────────────────────
  Widget _buildDetailsTab(Map<String, dynamic> c) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        // Case info
        _InfoCard(
            title: 'Case Information',
            icon: Icons.gavel_rounded,
            children: [
              _InfoRow(
                  'Case Title', c['case_title'] ?? '-', Icons.title_rounded),
              _InfoRow('Case Number', c['case_number'] ?? '-',
                  Icons.numbers_rounded),
              _InfoRow(
                  'CNR Number', c['cnr_number'] ?? '-', Icons.qr_code_rounded),
              _InfoRow(
                  'Case Type', c['case_type'] ?? '-', Icons.category_rounded),
              _InfoRow('Status', c['status'] ?? '-', Icons.info_rounded),
              _InfoRow('Priority', c['priority'] ?? '-',
                  Icons.priority_high_rounded),
            ]),
        const SizedBox(height: 12),

        // Court details
        _InfoCard(
            title: 'Court Details',
            icon: Icons.account_balance_rounded,
            children: [
              _InfoRow('Court Name', c['court_name'] ?? '-',
                  Icons.account_balance_rounded),
              _InfoRow('Court Location', c['court_location'] ?? '-',
                  Icons.location_on_rounded),
              _InfoRow(
                  'Judge Name', c['judge_name'] ?? '-', Icons.person_rounded),
            ]),
        const SizedBox(height: 12),

        // Next hearing (if available from hearings)
        if (_hearings.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withValues(alpha: 0.3))),
            child: Row(children: [
              const Icon(Icons.event_repeat_rounded, color: _gold, size: 22),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Next Hearing Date',
                    style: TextStyle(color: _textMuted, fontSize: 11)),
                Text(_getNextHearingDate(),
                    style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Opposite party
        if ((c['opposite_party'] ?? '').isNotEmpty)
          _InfoCard(
              title: 'Opposite Party',
              icon: Icons.people_rounded,
              children: [
                _InfoRow('Opposite Party', c['opposite_party'] ?? '-',
                    Icons.person_outline_rounded),
                _InfoRow('Opposite Lawyer', c['opposite_lawyer'] ?? '-',
                    Icons.gavel_rounded),
              ]),

        if ((c['description'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoCard(
              title: 'Description',
              icon: Icons.description_rounded,
              children: [
                Text(c['description'],
                    style: const TextStyle(
                        color: _textPri, fontSize: 13, height: 1.5)),
              ]),
        ],
        const SizedBox(height: 40),
      ]);

  // ── Timeline Tab ─────────────────────────────────
  Widget _buildTimelineTab(Map<String, dynamic> c) {
    final status = c['status'] ?? 'active';

    // Build timeline steps from case data + hearings
    final List<Map<String, dynamic>> steps = [];

    // Step 1: Case Filed
    steps.add({
      'title': 'Case Filed',
      'subtitle': 'Case registered with the court',
      'date': c['created_at']?.toString().length != null &&
              (c['created_at']?.toString().length ?? 0) >= 10
          ? c['created_at'].toString().substring(0, 10)
          : '',
      'status': 'done',
      'icon': Icons.gavel_rounded,
      'color': _green,
    });

    // Step 2: Each hearing as a step (oldest first, newest at top)
    final sortedHearings = List.from(_hearings)
      ..sort((a, b) =>
          (a['hearing_date'] ?? '').compareTo(b['hearing_date'] ?? ''));
    for (int i = 0; i < sortedHearings.length; i++) {
      final h = sortedHearings[i];
      final hStatus = h['status'] ?? 'scheduled';
      String stepStatus;
      if (hStatus == 'completed')
        stepStatus = 'done';
      else if (hStatus == 'cancelled')
        stepStatus = 'cancelled';
      else if (hStatus == 'adjourned')
        stepStatus = 'adjourned';
      else
        stepStatus = 'upcoming';

      steps.add({
        'title': 'Hearing ${i + 1}',
        'subtitle': h['court_name'] ?? 'Court Hearing',
        'date': (h['hearing_date'] ?? '').toString().length >= 10
            ? h['hearing_date'].toString().substring(0, 10)
            : '',
        'purpose': h['purpose'] ?? '',
        'order': h['order_summary'] ?? '',
        'remarks': h['remarks'] ?? '',
        'next_date': h['next_date'] ?? '',
        'status': stepStatus,
        'icon': Icons.event_rounded,
        'color': stepStatus == 'done'
            ? _green
            : stepStatus == 'cancelled'
                ? _red
                : stepStatus == 'adjourned'
                    ? _gold
                    : _blue,
      });
    }

    // Final step based on case status
    if (status == 'won') {
      steps.add({
        'title': 'Case Won! 🎉',
        'subtitle': 'Judgment in your favor',
        'date': '',
        'status': 'done',
        'icon': Icons.emoji_events_rounded,
        'color': _gold
      });
    } else if (status == 'lost') {
      steps.add({
        'title': 'Case Closed',
        'subtitle': 'Judgment delivered',
        'date': '',
        'status': 'done',
        'icon': Icons.do_not_disturb_rounded,
        'color': _red
      });
    } else if (status == 'closed') {
      steps.add({
        'title': 'Case Closed',
        'subtitle': 'Case has been closed',
        'date': '',
        'status': 'done',
        'icon': Icons.check_circle_rounded,
        'color': _textMuted
      });
    } else {
      steps.add({
        'title': 'Awaiting Judgment',
        'subtitle': 'Case is ongoing',
        'date': '',
        'status': 'pending',
        'icon': Icons.hourglass_empty_rounded,
        'color': _textMuted
      });
    }

    // ✅ Reverse so newest is at TOP, oldest at BOTTOM
    final reversedSteps = steps.reversed.toList();

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          // Case status banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.timeline_rounded,
                      color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Case Progress',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    Text(c['case_title'] ?? 'Case',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(status.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11)),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Progress bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border, width: 0.8)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Overall Progress',
                    style: TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                Text(
                    '${steps.where((s) => s['status'] == 'done').length}/${steps.length} steps',
                    style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: steps.isEmpty
                        ? 0
                        : steps.where((s) => s['status'] == 'done').length /
                            steps.length,
                    backgroundColor: _border,
                    valueColor: const AlwaysStoppedAnimation(_green),
                    minHeight: 10,
                  )),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    '${_hearings.length} hearing${_hearings.length == 1 ? '' : 's'} completed',
                    style: const TextStyle(color: _textMuted, fontSize: 10)),
                Text(
                    '${(steps.where((s) => s['status'] == 'done').length / (steps.isEmpty ? 1 : steps.length) * 100).toInt()}% complete',
                    style: const TextStyle(
                        color: _green,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          // Timeline
          ...reversedSteps.asMap().entries.map((entry) {
            final i = entry.key;
            final step = entry.value;
            final isLast = i == reversedSteps.length - 1;
            final isDone = step['status'] == 'done';
            final isUpcoming =
                step['status'] == 'upcoming' || step['status'] == 'pending';
            final isCancelled = step['status'] == 'cancelled';
            final isAdjourned = step['status'] == 'adjourned';
            final color = step['color'] as Color;

            return IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Left: dot + line
                  Column(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDone
                            ? color
                            : isUpcoming
                                ? _bgCard
                                : color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: isDone ? 0 : 2),
                        boxShadow: isDone
                            ? [
                                BoxShadow(
                                    color: color.withValues(alpha: 0.3),
                                    blurRadius: 8)
                              ]
                            : [],
                      ),
                      child: Icon(step['icon'] as IconData,
                          color: isDone ? Colors.white : color, size: 18),
                    ),
                    if (!isLast)
                      Expanded(
                          child: Container(
                              width: 2,
                              color:
                                  isDone ? _green.withValues(alpha: 0.4) : _border)),
                  ]),
                  const SizedBox(width: 14),

                  // Right: content
                  Expanded(
                      child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDone
                            ? _bgCard
                            : isUpcoming
                                ? _blue.withValues(alpha: 0.04)
                                : _bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDone
                              ? color.withValues(alpha: 0.2)
                              : isUpcoming
                                  ? _blue.withValues(alpha: 0.3)
                                  : _border,
                          width: isUpcoming ? 1.5 : 0.8,
                        ),
                        boxShadow: isDone
                            ? [
                                BoxShadow(
                                    color: color.withValues(alpha: 0.06),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ]
                            : [],
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(step['title'] as String,
                                      style: TextStyle(
                                          color: isDone
                                              ? _textPri
                                              : isUpcoming
                                                  ? _blue
                                                  : _textMuted,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14))),
                              if ((step['date'] as String).isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(step['date'] as String,
                                      style: TextStyle(
                                          color: color,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700)),
                                ),
                            ]),
                            const SizedBox(height: 3),
                            Text(step['subtitle'] as String,
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 12)),

                            if ((step['purpose'] as String? ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('📋 ${step['purpose']}',
                                  style: const TextStyle(
                                      color: _textMuted, fontSize: 11)),
                            ],

                            // Status badge
                            const SizedBox(height: 8),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          isDone
                                              ? Icons.check_circle_rounded
                                              : isCancelled
                                                  ? Icons.cancel_rounded
                                                  : isAdjourned
                                                      ? Icons.pending_rounded
                                                      : Icons.schedule_rounded,
                                          color: color,
                                          size: 10),
                                      const SizedBox(width: 4),
                                      Text(
                                          isDone
                                              ? 'Completed'
                                              : isCancelled
                                                  ? 'Cancelled'
                                                  : isAdjourned
                                                      ? 'Adjourned'
                                                      : 'Upcoming',
                                          style: TextStyle(
                                              color: color,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                              ),
                            ]),

                            // Order summary
                            if ((step['order'] as String? ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: _green.withValues(alpha: 0.2))),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(children: [
                                        Icon(Icons.gavel_rounded,
                                            color: _green, size: 12),
                                        SizedBox(width: 4),
                                        Text('Court Order',
                                            style: TextStyle(
                                                color: _green,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11)),
                                      ]),
                                      const SizedBox(height: 4),
                                      Text(step['order'] as String,
                                          style: const TextStyle(
                                              color: _textPri,
                                              fontSize: 11,
                                              height: 1.4)),
                                    ]),
                              ),
                            ],

                            // Remarks
                            if ((step['remarks'] as String? ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: _blue.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: _blue.withValues(alpha: 0.15))),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.notes_rounded,
                                          color: _blue, size: 12),
                                      const SizedBox(width: 4),
                                      Expanded(
                                          child: Text(step['remarks'] as String,
                                              style: const TextStyle(
                                                  color: _textPri,
                                                  fontSize: 11,
                                                  height: 1.4))),
                                    ]),
                              ),
                            ],

                            // Next date
                            if ((step['next_date'] as String? ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: _gold.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: _gold.withValues(alpha: 0.3))),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.event_repeat_rounded,
                                          color: _gold, size: 13),
                                      const SizedBox(width: 6),
                                      const Text('Next: ',
                                          style: TextStyle(
                                              color: _textMuted, fontSize: 11)),
                                      Text(
                                          (step['next_date'] as String)
                                                      .length >=
                                                  10
                                              ? (step['next_date'] as String)
                                                  .substring(0, 10)
                                              : step['next_date'] as String,
                                          style: const TextStyle(
                                              color: _gold,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11)),
                                    ]),
                              ),
                            ],
                          ]),
                    ),
                  )),
                ]));
          }).toList(),
        ]);
  }

  String _getNextHearingDate() {
    final now = DateTime.now();
    final upcoming = _hearings.where((h) {
      try {
        final d = DateTime.parse(
            (h['hearing_date'] ?? '').toString().substring(0, 10));
        return d.isAfter(now) && h['status'] == 'scheduled';
      } catch (_) {
        return false;
      }
    }).toList();
    if (upcoming.isEmpty) {
      // Check next_date from completed hearings
      for (final h in _hearings) {
        if ((h['next_date'] ?? '').isNotEmpty)
          return h['next_date'].toString().substring(0, 10);
      }
      return 'TBD';
    }
    return upcoming.first['hearing_date'].toString().substring(0, 10);
  }

  // ── Hearings Tab ─────────────────────────────────
  Widget _buildHearingsTab() {
    if (_hearings.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.event_rounded, color: _green.withValues(alpha: 0.3), size: 56),
        const SizedBox(height: 12),
        const Text('No hearings yet',
            style: TextStyle(color: _textMuted, fontSize: 15)),
        const SizedBox(height: 6),
        const Text('Your lawyer will schedule hearings here',
            style: TextStyle(color: _textMuted, fontSize: 12)),
      ]));
    }

    return RefreshIndicator(
      color: _green,
      backgroundColor: _bgCard,
      onRefresh: _loadDetails,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _hearings.length,
        itemBuilder: (_, i) {
          final h = _hearings[i];
          final status = h['status'] ?? 'scheduled';
          final color = _hearingStatusColor(status);
          final date = (h['hearing_date'] ?? '').toString();
          final day = date.length >= 10 ? date.substring(8, 10) : '--';
          final month = date.length >= 7
              ? _monthName(int.tryParse(date.substring(5, 7)) ?? 1)
              : '--';

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                      color: _green.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
            child: Column(children: [
              Container(
                  height: 4,
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)))),
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(children: [
                          Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(day,
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16)),
                                    Text(month,
                                        style: TextStyle(
                                            color: color.withValues(alpha: 0.7),
                                            fontSize: 10)),
                                  ])),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(h['court_name'] ?? 'Hearing',
                                    style: const TextStyle(
                                        color: _textPri,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                if ((h['purpose'] ?? '').isNotEmpty)
                                  Text(h['purpose'],
                                      style: const TextStyle(
                                          color: _textMuted, fontSize: 12)),
                                if ((h['hearing_time'] ?? '').isNotEmpty)
                                  Text('⏰ ${h['hearing_time']}',
                                      style: const TextStyle(
                                          color: _textMuted, fontSize: 11)),
                              ])),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: color.withValues(alpha: 0.3))),
                            child: Text(status.toUpperCase(),
                                style: TextStyle(
                                    color: color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ]),

                        // Order summary (after lawyer updates)
                        if ((h['order_summary'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Divider(color: _border, height: 1, thickness: 0.6),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _border)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(children: [
                                    Icon(Icons.gavel_rounded,
                                        color: _green, size: 14),
                                    SizedBox(width: 6),
                                    Text('Order Summary',
                                        style: TextStyle(
                                            color: _green,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(h['order_summary'],
                                      style: const TextStyle(
                                          color: _textPri,
                                          fontSize: 12,
                                          height: 1.4)),
                                ]),
                          ),
                        ],

                        // Remarks
                        if ((h['remarks'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: _blue.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: _blue.withValues(alpha: 0.2))),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.notes_rounded,
                                      color: _blue, size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(h['remarks'],
                                          style: const TextStyle(
                                              color: _textPri,
                                              fontSize: 12,
                                              height: 1.4))),
                                ]),
                          ),
                        ],

                        // Next date
                        if ((h['next_date'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: _gold.withValues(alpha: 0.3))),
                            child: Row(children: [
                              const Icon(Icons.event_repeat_rounded,
                                  color: _gold, size: 16),
                              const SizedBox(width: 8),
                              const Text('Next Date: ',
                                  style: TextStyle(
                                      color: _textMuted, fontSize: 12)),
                              Text(
                                  h['next_date'].toString().length >= 10
                                      ? h['next_date']
                                          .toString()
                                          .substring(0, 10)
                                      : h['next_date'].toString(),
                                  style: const TextStyle(
                                      color: _gold,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ]),
                          ),
                        ],
                      ])),
            ]),
          );
        },
      ),
    );
  }

  String _monthName(int m) => [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m - 1];

  // ── Documents Tab ────────────────────────────────
  Widget _buildDocumentsTab() {
    if (_documents.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.folder_open_rounded,
            color: _green.withValues(alpha: 0.3), size: 56),
        const SizedBox(height: 12),
        const Text('No documents yet',
            style: TextStyle(color: _textMuted, fontSize: 15)),
        const SizedBox(height: 6),
        const Text('Court orders & documents will appear here',
            style: TextStyle(color: _textMuted, fontSize: 12)),
      ]));
    }

    final courtDocs = _documents.where((d) {
      final cat = (d['category'] ?? '').toLowerCase();
      return cat.contains('court') ||
          cat.contains('order') ||
          cat.contains('petition') ||
          cat.contains('affidavit') ||
          cat.contains('notice');
    }).toList();

    final otherDocs = _documents.where((d) {
      final cat = (d['category'] ?? '').toLowerCase();
      return !cat.contains('court') &&
          !cat.contains('order') &&
          !cat.contains('petition') &&
          !cat.contains('affidavit') &&
          !cat.contains('notice');
    }).toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (courtDocs.isNotEmpty) ...[
        const Row(children: [
          Icon(Icons.balance_rounded, color: _green, size: 16),
          SizedBox(width: 6),
          Text('Court Documents',
              style: TextStyle(
                  color: _textPri, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        ...courtDocs.map((d) => _DocCard(doc: d)),
        const SizedBox(height: 16),
      ],
      if (otherDocs.isNotEmpty) ...[
        const Row(children: [
          Icon(Icons.folder_rounded, color: _textMuted, size: 16),
          SizedBox(width: 6),
          Text('Other Documents',
              style: TextStyle(
                  color: _textPri, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        ...otherDocs.map((d) => _DocCard(doc: d)),
      ],
      const SizedBox(height: 40),
    ]);
  }
}

// ── Document Card ─────────────────────────────────
class _DocCard extends StatelessWidget {
  final dynamic doc;
  const _DocCard({required this.doc});

  IconData _icon(String? t, String? n) {
    final type = (t ?? '').toLowerCase();
    final name = (n ?? '').toLowerCase();
    if (type.contains('pdf') || name.endsWith('.pdf'))
      return Icons.picture_as_pdf_rounded;
    if (type.contains('image')) return Icons.image_rounded;
    if (type.contains('video')) return Icons.videocam_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _color(String? t, String? n) {
    final type = (t ?? '').toLowerCase();
    final name = (n ?? '').toLowerCase();
    if (type.contains('pdf') || name.endsWith('.pdf')) return _red;
    if (type.contains('image')) return _blue;
    if (type.contains('video')) return const Color(0xFF7C3AED);
    return _green;
  }

  @override
  Widget build(BuildContext context) {
    final name = doc['file_name'] ?? 'Document';
    final category = doc['category'] ?? '';
    final url = doc['file_url'] ?? '';
    final createdAt = doc['created_at']?.toString() ?? '';
    final date = createdAt.length >= 10 ? createdAt.substring(0, 10) : '';
    final color = _color(doc['file_type'], doc['file_name']);
    final icon = _icon(doc['file_type'], doc['file_name']);

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
                blurRadius: 6,
                offset: const Offset(0, 2))
          ]),
      child: Row(children: [
        Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Row(children: [
            if (category.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(category,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 6),
            Text(date, style: const TextStyle(color: _textMuted, fontSize: 10)),
          ]),
        ])),
        GestureDetector(
          onTap: () async {
            if (url.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Link copied! Open in browser to download.'),
                  backgroundColor: _green,
                  behavior: SnackBarBehavior.floating));
          },
          child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: url.isNotEmpty
                      ? color.withValues(alpha: 0.1)
                      : _border.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.download_rounded,
                  color: url.isNotEmpty ? color : _textMuted, size: 18)),
        ),
      ]),
    );
  }
}

// ── Info Card ─────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard(
      {required this.title, required this.icon, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _green.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: _green, borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, color: Colors.white, size: 14)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: _textPri,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
          Divider(color: _border, height: 16, thickness: 0.6),
          ...children,
        ]),
      );
}

// ── Info Row ──────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _InfoRow(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == '-' || value == 'null')
      return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _green, size: 15),
            const SizedBox(width: 10),
            SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(color: _textMuted, fontSize: 12))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w600,
                        fontSize: 13))),
          ],
        ));
  }
}
