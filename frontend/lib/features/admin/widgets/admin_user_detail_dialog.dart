import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';
import 'admin_shell.dart';
import 'admin_widgets.dart';

/// The shared "click a row → see the full profile" dialog for
/// Users/Lawyers/Students/Clients — all four are the same `users` table
/// underneath, so GET /admin/users/:id serves all four instead of needing
/// four different detail screens (see AdminGetUserDetail's doc comment).
///
/// Enhanced into a full tabbed view (Personal, Registration, Bookings,
/// Payments, Refunds, Consultations, Documents, Cases, Subscription,
/// Activity) — every section reuses data AdminGetUserDetail already
/// assembles from real tables (consultations, documents, cases,
/// subscriptions, audit_logs); nothing here is a second data source.
Future<void> showAdminUserDetail(BuildContext context, String userId) async {
  showDialog(
    context: context,
    builder: (dialogContext) => Theme(
      data: buildAdminTheme(dialogContext),
      child: Dialog(
        backgroundColor: kAdminCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 800),
          child: _UserDetailDialog(userId: userId),
        ),
      ),
    ),
  );
}

class _UserDetailDialog extends StatefulWidget {
  final String userId;
  const _UserDetailDialog({required this.userId});
  @override
  State<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<_UserDetailDialog>
    with SingleTickerProviderStateMixin {
  final _repo = AdminRepository();
  late TabController _tabCtrl;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = {};
  List<dynamic> _asClient = [];
  List<dynamic> _asLawyer = [];
  List<dynamic> _documents = [];
  List<dynamic> _refunds = [];
  List<dynamic> _cases = [];
  List<dynamic> _activity = [];
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _studentProgress;

  static const _tabs = [
    'Personal',
    'Registration',
    'Bookings',
    'Payments',
    'Refunds',
    'Consultations',
    'Documents',
    'Cases',
    'Subscription',
    'Activity',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _repo.userDetail(widget.userId);
      final data = res['data'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        _profile = (data['profile'] as Map<String, dynamic>?) ?? {};
        _asClient = (data['consultations_client'] as List?) ?? [];
        _asLawyer = (data['consultations_lawyer'] as List?) ?? [];
        _documents = (data['documents'] as List?) ?? [];
        _refunds = (data['refunds'] as List?) ?? [];
        _cases = (data['cases'] as List?) ?? [];
        _activity = (data['activity'] as List?) ?? [];
        _subscription = data['subscription'] as Map<String, dynamic>?;
        _studentProgress = data['student_progress'] as Map<String, dynamic>?;
        _loading = false;
      });
    } on AdminException catch (e) {
      if (!silent && mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  String get _roleLabel => (_profile['role_name'] ?? '')
      .toString()
      .replaceAll('_', ' ')
      .toUpperCase();
  bool get _isLawyer => _profile['role_name'] == 'lawyer';
  bool get _isSuperAdmin => _profile['role_name'] == 'super_admin';

  List<dynamic> get _allBookings => [..._asClient, ..._asLawyer];

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 320,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    if (_error != null) {
      return SizedBox(
        height: 260,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 30),
          const SizedBox(height: 10),
          const Text('Unable to load user information',
              style: TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ]),
      );
    }
    final active = _profile['is_active'] == true;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryHeader(active),
            const Divider(height: 24),
            TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              labelColor: kAdminAccent,
              unselectedLabelColor: kAdminTextMuted,
              indicatorColor: kAdminAccent,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 520,
              child: TabBarView(controller: _tabCtrl, children: [
                _personalTab(),
                _registrationTab(),
                _bookingsTab(),
                _paymentsTab(),
                _refundsTab(),
                _consultationsTab(),
                _documentsTab(),
                _casesTab(),
                _subscriptionTab(),
                _activityTab(),
              ]),
            ),
          ]),
    );
  }

  Widget _summaryHeader(bool active) {
    return Row(children: [
      CircleAvatar(
        radius: 26,
        backgroundColor: kAdminAccent,
        backgroundImage: (_profile['avatar_url'] ?? '').toString().isNotEmpty
            ? NetworkImage(_profile['avatar_url'])
            : null,
        child: (_profile['avatar_url'] ?? '').toString().isEmpty
            ? Text(
                (_profile['name'] ?? '?').toString().isNotEmpty
                    ? (_profile['name'] as String).substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800))
            : null,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_profile['name'] ?? '',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: kAdminTextPri)),
          Text(_profile['email'] ?? '',
              style: const TextStyle(color: kAdminTextMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _miniStat('Bookings', '${_allBookings.length}'),
            _miniStat('Payments',
                '${_allBookings.where((b) => b['payment_status'] == 'paid').length}'),
            _miniStat('Refunds', '${_refunds.length}'),
            _miniStat(
                'Subscription',
                _subscription == null
                    ? 'N/A'
                    : (_subscription!['status'] ?? '')
                        .toString()
                        .toUpperCase()),
          ]),
        ]),
      ),
      AdminBadge(_roleLabel, kAdminAccent),
      const SizedBox(width: 8),
      AdminBadge(active ? 'Active' : 'Suspended',
          AdminBadge.colorFor(active ? 'active' : 'suspended')),
      const SizedBox(width: 8),
      if (!_isSuperAdmin)
        IconButton(
          icon: Icon(active ? Icons.block_rounded : Icons.check_circle_rounded,
              size: 20, color: active ? kAdminRed : kAdminGreen),
          tooltip: active ? 'Suspend' : 'Activate',
          onPressed: () => _confirmStatusChange(active),
        ),
      IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: kAdminTextPri)),
    ]);
  }

  Widget _miniStat(String label, String value) => Text.rich(TextSpan(children: [
        TextSpan(
            text: '$value ',
            style: const TextStyle(
                color: kAdminTextPri,
                fontWeight: FontWeight.w800,
                fontSize: 12)),
        TextSpan(
            text: label,
            style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
      ]));

  Future<void> _confirmStatusChange(bool currentlyActive) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(currentlyActive
            ? 'Suspend this account?'
            : 'Activate this account?'),
        content: Text(currentlyActive
            ? 'The user will be prevented from signing in and using the platform.'
            : 'The user will regain full access to the platform.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(currentlyActive ? 'Suspend' : 'Activate')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.setUserActive(widget.userId, !currentlyActive);
      await _load();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ── Personal ──
  Widget _personalTab() {
    final p = _profile;
    return SingleChildScrollView(
      child: Wrap(spacing: 24, runSpacing: 10, children: [
        _field('User ID', p['id']),
        _field('Full Name', p['name']),
        _field('Email', p['email']),
        _field('Phone',
            (p['phone'] ?? '').toString().isEmpty ? 'N/A' : p['phone']),
        _field('Role', _roleLabel),
        if (_isLawyer) ...[
          _field(
              'Designation',
              (p['designation'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : p['designation']),
          _field(
              'Bar Council No.',
              (p['bar_council_number'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : p['bar_council_number']),
          _field(
              'Verification',
              (p['verification_status'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : p['verification_status']),
        ],
        _field(
            'Account Status', p['is_active'] == true ? 'ACTIVE' : 'SUSPENDED'),
        _field('Registered', fmtDate(p['created_at'])),
        _field(
            'Last Login',
            (p['last_login_at'] ?? '').toString().isEmpty
                ? 'N/A'
                : fmtDate(p['last_login_at'])),
        if (_studentProgress != null) ...[
          _field('Total Score', '${_studentProgress!['total_score']}'),
          _field('Challenges',
              '${_studentProgress!['completed_challenges']}/${_studentProgress!['total_challenges']}'),
          _field('Streak Days', '${_studentProgress!['streak_days']}'),
        ],
        if (_isLawyer) ...[
          _moneyTile('Earnings (Paid)', p['earnings_paid'], kAdminGreen),
          _moneyTile('Earnings (Pending)', p['earnings_pending'], kAdminAmber),
        ],
        if ((p['spent_total'] ?? 0) > 0)
          _moneyTile('Total Spent', p['spent_total'], kAdminAccent),
      ]),
    );
  }

  // ── Registration ──
  Widget _registrationTab() {
    final p = _profile;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Registration Information'),
        const SizedBox(height: 10),
        Wrap(spacing: 24, runSpacing: 10, children: [
          _field('Registered On', fmtDate(p['created_at'])),
          _field('Role at Registration', _roleLabel),
          if (_isLawyer)
            _field(
                'Verification Status',
                (p['verification_status'] ?? '').toString().isEmpty
                    ? 'N/A'
                    : p['verification_status']),
          _field(
              'Last Login',
              (p['last_login_at'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : fmtDate(p['last_login_at'])),
        ]),
        const SizedBox(height: 8),
        const Text(
            'Registration method is not tracked by this application — omitted rather than guessed.',
            style: TextStyle(
                color: kAdminTextMuted,
                fontSize: 10.5,
                fontStyle: FontStyle.italic)),
      ]),
    );
  }

  // ── Bookings ──
  Widget _bookingsTab() {
    if (_allBookings.isEmpty)
      return const AdminEmptyState(message: 'No booking history available');
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(kAdminBg),
          columns: const [
            DataColumn(label: Text('Booking')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Amount')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Payment')),
            DataColumn(label: Text('Created')),
          ],
          rows: _allBookings.map((b) {
            return DataRow(
              onSelectChanged: (_) => _showBookingDetail(b),
              cells: [
                DataCell(Text('${b['id']}'.substring(0, 8))),
                DataCell(Text(b['consultation_type'] ?? '')),
                DataCell(Text(b['consultation_date'] ?? '')),
                DataCell(Text(b['consultation_time'] ?? '')),
                DataCell(Text(fmtRupees(b['amount_rupees'] as num?))),
                DataCell(AdminBadge(
                    b['status'] ?? '', AdminBadge.colorFor(b['status'] ?? ''))),
                DataCell(AdminBadge(b['payment_status'] ?? '',
                    AdminBadge.colorFor(b['payment_status'] ?? ''))),
                DataCell(Text(fmtDate(b['created_at']))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showBookingDetail(dynamic b) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Booking Detail'),
        content: SizedBox(
          width: 380,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('Booking ID', b['id']),
                _field('Type', b['consultation_type']),
                _field('With', b['lawyer_name'] ?? b['client_name']),
                _field('Date', b['consultation_date']),
                _field('Time', b['consultation_time']),
                _field(
                    'Duration',
                    (b['duration_seconds'] as int? ?? 0) > 0
                        ? '${((b['duration_seconds'] as int) / 60).round()} min'
                        : 'N/A'),
                _field('Amount', fmtRupees(b['amount_rupees'] as num?)),
                _field('Status', b['status']),
                _field('Payment Status', b['payment_status']),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  // ── Payments ──
  Widget _paymentsTab() {
    final paid =
        _allBookings.where((b) => (b['payment_status'] ?? '') != '').toList();
    if (paid.isEmpty)
      return const AdminEmptyState(message: 'No payments available');
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(kAdminBg),
          columns: const [
            DataColumn(label: Text('Booking Ref')),
            DataColumn(label: Text('Amount')),
            DataColumn(label: Text('GST')),
            DataColumn(label: Text('Platform Fee')),
            DataColumn(label: Text('Method')),
            DataColumn(label: Text('Reference')),
            DataColumn(label: Text('Status')),
          ],
          rows: paid.map((b) {
            return DataRow(cells: [
              DataCell(Text('${b['id']}'.substring(0, 8))),
              DataCell(Text(fmtRupees(b['amount_rupees'] as num?),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              const DataCell(Text('N/A')),
              const DataCell(Text('N/A')),
              DataCell(Text((b['payment_method'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : b['payment_method'])),
              DataCell(Text((b['payment_reference'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : b['payment_reference'])),
              DataCell(AdminBadge(b['payment_status'] ?? '',
                  AdminBadge.colorFor(b['payment_status'] ?? ''))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ── Refunds ──
  Widget _refundsTab() {
    if (_refunds.isEmpty)
      return const AdminEmptyState(message: 'No refunds available');
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(kAdminBg),
          columns: const [
            DataColumn(label: Text('Booking Ref')),
            DataColumn(label: Text('Refund Amount')),
            DataColumn(label: Text('Reference')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Date')),
          ],
          rows: _refunds.map((r) {
            return DataRow(cells: [
              DataCell(Text('${r['id']}'.substring(0, 8))),
              DataCell(Text(fmtRupees(r['amount_rupees'] as num?),
                  style: const TextStyle(
                      color: kAdminRed, fontWeight: FontWeight.w700))),
              DataCell(Text((r['payment_reference'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : r['payment_reference'])),
              const DataCell(AdminBadge('refunded', kAdminAccent)),
              DataCell(Text(fmtDate(r['created_at']))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ── Consultations / Communication ──
  Widget _consultationsTab() {
    if (_allBookings.isEmpty)
      return const AdminEmptyState(
          message: 'No consultation history available');
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Consultation & Communication History'),
        const SizedBox(height: 10),
        ..._allBookings.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: kAdminBg, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(_iconFor(c['consultation_type'] ?? ''),
                    size: 16, color: kAdminAccent),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '${c['consultation_type']} · ${c['client_name'] ?? c['lawyer_name'] ?? ''}',
                        style: const TextStyle(fontSize: 12.5))),
                Text(
                    '${(c['duration_seconds'] as int? ?? 0) > 0 ? '${((c['duration_seconds'] as int) / 60).round()} min' : 'N/A'}',
                    style:
                        const TextStyle(fontSize: 11, color: kAdminTextMuted)),
                const SizedBox(width: 8),
                Text(fmtDate(c['consultation_date']),
                    style:
                        const TextStyle(fontSize: 11, color: kAdminTextMuted)),
                const SizedBox(width: 8),
                AdminBadge(
                    c['status'] ?? '', AdminBadge.colorFor(c['status'] ?? '')),
              ]),
            )),
      ]),
    );
  }

  IconData _iconFor(String type) {
    final t = type.toLowerCase();
    if (t.contains('video')) return Icons.videocam_rounded;
    if (t.contains('audio')) return Icons.call_rounded;
    if (t.contains('visit')) return Icons.location_on_rounded;
    return Icons.chat_bubble_rounded;
  }

  // ── Documents ──
  Widget _documentsTab() {
    if (_documents.isEmpty)
      return const AdminEmptyState(message: 'No documents available');
    return ListView.builder(
      itemCount: _documents.length,
      itemBuilder: (context, i) {
        final d = _documents[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.description_outlined,
                size: 16, color: kAdminTextMuted),
            const SizedBox(width: 8),
            Expanded(
                child: Text(d['file_name'] ?? '',
                    style: const TextStyle(fontSize: 12.5))),
            if ((d['category'] ?? '').toString().isNotEmpty) ...[
              AdminBadge(d['category'], kAdminAccent),
              const SizedBox(width: 8),
            ],
            Text(fmtDate(d['created_at']),
                style: const TextStyle(fontSize: 11, color: kAdminTextMuted)),
          ]),
        );
      },
    );
  }

  // ── Cases ──
  Widget _casesTab() {
    if (_cases.isEmpty)
      return const AdminEmptyState(message: 'No cases available');
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(kAdminBg),
          columns: const [
            DataColumn(label: Text('Case')),
            DataColumn(label: Text('With')),
            DataColumn(label: Text('Court')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Filing Date')),
            DataColumn(label: Text('Status')),
          ],
          rows: _cases.map((cs) {
            final withName = cs['as_role'] == 'client'
                ? cs['lawyer_name']
                : cs['client_name'];
            return DataRow(cells: [
              DataCell(Text(cs['case_title'] ?? '')),
              DataCell(
                  Text((withName ?? '').toString().isEmpty ? 'N/A' : withName)),
              DataCell(Text((cs['court_name'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : cs['court_name'])),
              DataCell(Text((cs['case_type'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : cs['case_type'])),
              DataCell(Text((cs['filing_date'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : fmtDate(cs['filing_date']))),
              DataCell(AdminBadge(
                  cs['status'] ?? '', AdminBadge.colorFor(cs['status'] ?? ''))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ── Subscription ──
  Widget _subscriptionTab() {
    if (_subscription == null) {
      return const AdminEmptyState(
          message: 'No subscription associated with this account');
    }
    final s = _subscription!;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel('Subscription'),
          const SizedBox(width: 10),
          AdminBadge(s['status'] ?? '', AdminBadge.colorFor(s['status'] ?? '')),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 24, runSpacing: 10, children: [
          _field(
              'Plan',
              (s['plan_name'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : s['plan_name']),
          _field(
              'Billing Cycle',
              (s['billing_cycle'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : s['billing_cycle']),
          _field(
              'Started',
              (s['started_at'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : fmtDate(s['started_at'])),
          _field(
              'Current Period End',
              (s['current_period_end'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : fmtDate(s['current_period_end'])),
          if ((s['trial_ends_at'] ?? '').toString().isNotEmpty)
            _field('Trial Ends', fmtDate(s['trial_ends_at'])),
          if ((s['cancelled_at'] ?? '').toString().isNotEmpty)
            _field('Cancelled At', fmtDate(s['cancelled_at'])),
          if ((s['last_payment_amount'] as num? ?? 0) > 0)
            _moneyTile('Last Payment', s['last_payment_amount'], kAdminGreen),
        ]),
      ]),
    );
  }

  // ── Activity ──
  Widget _activityTab() {
    if (_activity.isEmpty)
      return const AdminEmptyState(message: 'No activity recorded yet');
    return ListView.builder(
      itemCount: _activity.length,
      itemBuilder: (context, i) {
        final e = _activity[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, right: 10),
                decoration: const BoxDecoration(
                    color: kAdminAccent, shape: BoxShape.circle)),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtDate(e['created_at']),
                        style: const TextStyle(
                            color: kAdminTextMuted, fontSize: 10.5)),
                    const SizedBox(height: 2),
                    Text(e['description'] ?? e['action'] ?? '',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kAdminTextPri)),
                    Text(
                        'by ${(e['actor_name'] ?? '').toString().isEmpty ? 'System' : e['actor_name']} (${e['actor_role']})',
                        style: const TextStyle(
                            color: kAdminTextMuted, fontSize: 11)),
                  ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _sectionLabel(String s) => Row(children: [
        Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
                color: kAdminAccent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(s,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: kAdminTextPri)),
      ]);

  Widget _field(String label, dynamic value) => SizedBox(
        width: 200,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 10.5)),
          Text((value ?? '—').toString().isEmpty ? '—' : value.toString(),
              style: const TextStyle(
                  color: kAdminTextPri,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _moneyTile(String label, dynamic value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtRupees(value as num?),
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
        ]),
      );
}
