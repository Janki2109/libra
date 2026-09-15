import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Super Admin → Lawyer Management (enhanced in place — same route/screen
/// the sidebar's "Lawyers" item always pointed to).
///
/// Every tab in the detail view reuses an existing real data source: earnings
/// reuse lawyer_payouts (the same numbers the Payouts & Settlements module
/// shows), bookings/consultations reuse the consultations table, cases reuse
/// the cases table, documents reuse the documents table (migration 032 only
/// added a verification workflow to it), and activity reuses audit_logs.
/// There is no ratings/reviews table anywhere in this schema, so that tab is
/// a real, honest empty state rather than fabricated data.
class AdminLawyersScreen extends StatefulWidget {
  const AdminLawyersScreen({super.key});
  @override
  State<AdminLawyersScreen> createState() => _AdminLawyersScreenState();
}

class _AdminLawyersScreenState extends State<AdminLawyersScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  int _page = 1;
  bool _hasMore = false;

  bool _statsLoading = true;
  Map<String, dynamic> _stats = {};

  String _search = '';
  String _verification = '';
  String _activity = '';
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _load();
  }

  Future<void> _loadStats() async {
    try {
      final res = await _repo.lawyerStats();
      if (!mounted) return;
      setState(() {
        _stats = (res['data'] as Map<String, dynamic>?) ?? {};
        _statsLoading = false;
      });
    } on AdminException catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  num _n(String key) => (_stats[key] as num?) ?? 0;

  String? get _fromStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.start)
      : null;
  String? get _toStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.end)
      : null;

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _repo.lawyers(
        status: _verification,
        search: _search,
        activity: _activity,
        from: _fromStr,
        to: _toStr,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        _rows = (res['data'] as List?) ?? [];
        _hasMore = (res['meta']?['has_more'] as bool?) ?? false;
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

  void _applyFilters() {
    _page = 1;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/lawyers',
      title: 'Lawyer Management',
      actions: [
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _loadStats();
              _load();
            })
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Lawyer Management',
            style: TextStyle(
                color: kAdminTextPri,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
            'Manage lawyer verification, documents, activity, earnings, bookings, cases and consultations',
            style: TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
        const SizedBox(height: 20),
        _statsGrid(),
        const SizedBox(height: 20),
        _filtersCard(),
        const SizedBox(height: 16),
        _tableCard(),
      ]),
    );
  }

  Widget _statsGrid() {
    if (_statsLoading) return const AdminStatGridSkeleton(count: 5);
    final cards = [
      (
        'Total Lawyers',
        '${_n('total_lawyers')}',
        Icons.gavel_rounded,
        kAdminAccent,
        ''
      ),
      (
        'Pending Verification',
        '${_n('pending_verification')}',
        Icons.hourglass_bottom_rounded,
        kAdminAmber,
        'pending'
      ),
      (
        'Verified Lawyers',
        '${_n('verified')}',
        Icons.verified_rounded,
        kAdminGreen,
        'verified'
      ),
      (
        'Active Lawyers',
        '${_n('active')}',
        Icons.check_circle_rounded,
        kAdminGreen,
        ''
      ),
      (
        'Suspended Lawyers',
        '${_n('inactive')}',
        Icons.block_rounded,
        kAdminRed,
        ''
      ),
    ];
    return AdminStatGrid(
      cards: cards.map((c) {
        return AdminStatCard(
          label: c.$1,
          value: c.$2,
          icon: c.$3,
          color: c.$4,
          onTap: c.$5.isEmpty && c.$1 == 'Active Lawyers'
              ? () {
                  setState(() => _activity = 'active');
                  _applyFilters();
                }
              : c.$1 == 'Suspended Lawyers'
                  ? () {
                      setState(() => _activity = 'inactive');
                      _applyFilters();
                    }
                  : c.$5.isNotEmpty
                      ? () {
                          setState(() => _verification = c.$5);
                          _applyFilters();
                        }
                      : null,
        );
      }).toList(),
    );
  }

  Widget _filtersCard() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminSearchField(
                hint: 'Search name, lawyer ID, email, phone, designation…',
                onChanged: (v) {
                  _search = v;
                  _applyFilters();
                },
              ),
              for (final s in const [
                ('', 'All'),
                ('verified', 'Verified'),
                ('pending', 'Pending'),
                ('rejected', 'Rejected')
              ])
                AdminFilterChip(
                    label: s.$2,
                    selected: _verification == s.$1,
                    onTap: () {
                      setState(() => _verification = s.$1);
                      _applyFilters();
                    }),
              for (final s in const [
                ('', 'Any Activity'),
                ('active', 'Active'),
                ('inactive', 'Suspended')
              ])
                AdminFilterChip(
                    label: s.$2,
                    selected: _activity == s.$1,
                    onTap: () {
                      setState(() => _activity = s.$1);
                      _applyFilters();
                    }),
              GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 3),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: _dateRange);
                  if (picked != null) {
                    setState(() => _dateRange = picked);
                    _applyFilters();
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _dateRange != null
                        ? kAdminAccent.withValues(alpha: 0.1)
                        : kAdminBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color:
                            _dateRange != null ? kAdminAccent : kAdminBorder),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.date_range_rounded,
                        size: 15,
                        color: _dateRange != null
                            ? kAdminAccent
                            : kAdminTextMuted),
                    const SizedBox(width: 6),
                    Text(
                        _dateRange == null
                            ? 'Joined date'
                            : '${DateFormat('d MMM').format(_dateRange!.start)} – ${DateFormat('d MMM').format(_dateRange!.end)}',
                        style: TextStyle(
                            color: _dateRange != null
                                ? kAdminAccent
                                : kAdminTextPri,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    if (_dateRange != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() => _dateRange = null);
                          _applyFilters();
                        },
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: kAdminAccent),
                      ),
                    ],
                  ]),
                ),
              ),
            ]),
      ]),
    );
  }

  Widget _tableCard() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_loading)
          const AdminTableSkeleton(columns: 9)
        else if (_error != null)
          _errorState()
        else if (_rows.isEmpty)
          AdminEmptyState(
              message: _search.isNotEmpty ||
                      _verification.isNotEmpty ||
                      _activity.isNotEmpty
                  ? 'No matching lawyers found'
                  : 'No lawyers found')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 52,
              dataRowMaxHeight: 60,
              headingRowColor: WidgetStateProperty.all(kAdminBg),
              columns: const [
                DataColumn(label: Text('Lawyer')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Phone')),
                DataColumn(label: Text('Specialization')),
                DataColumn(label: Text('Verification')),
                DataColumn(label: Text('Activity')),
                DataColumn(label: Text('Cases')),
                DataColumn(label: Text('Consultations')),
                DataColumn(label: Text('Earnings')),
                DataColumn(label: Text('Joined')),
              ],
              rows: _rows.map((l) {
                final active = l['is_active'] == true;
                return DataRow(
                  onSelectChanged: (_) => _showDetail(l['id']),
                  cells: [
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      _Avatar(name: l['name'] ?? '?'),
                      const SizedBox(width: 8),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l['name'] ?? '-'),
                            Text('${l['id']}'.substring(0, 8),
                                style: const TextStyle(
                                    color: kAdminTextMuted, fontSize: 10)),
                          ]),
                    ])),
                    DataCell(Text(l['email'] ?? '',
                        style: const TextStyle(color: kAdminTextMuted))),
                    DataCell(Text((l['phone'] ?? '').toString().isEmpty
                        ? 'N/A'
                        : l['phone'])),
                    DataCell(Text((l['specialization'] ?? '').toString().isEmpty
                        ? 'N/A'
                        : l['specialization'])),
                    DataCell(AdminBadge(l['verification_status'] ?? '',
                        AdminBadge.colorFor(l['verification_status'] ?? ''))),
                    DataCell(AdminBadge(active ? 'Active' : 'Suspended',
                        AdminBadge.colorFor(active ? 'active' : 'suspended'))),
                    DataCell(Text('${l['total_cases'] ?? 0}')),
                    DataCell(Text('${l['total_consultations'] ?? 0}')),
                    DataCell(Text(
                        fmtRupees(((l['earnings_paid'] as num? ?? 0) +
                            (l['earnings_pending'] as num? ?? 0))),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text(fmtDate(l['created_at']))),
                  ],
                );
              }).toList(),
            ),
          ),
        AdminPager(
          page: _page,
          hasMore: _hasMore,
          loading: _loading,
          onPageChange: (p) {
            setState(() => _page = p);
            _load();
          },
        ),
      ]),
    );
  }

  Widget _errorState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(children: [
            const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 34),
            const SizedBox(height: 10),
            const Text('Unable to load lawyer information',
                style: TextStyle(
                    color: kAdminTextPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => _load(), child: const Text('Retry')),
          ]),
        ),
      );

  void _showDetail(String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => Theme(
        data: buildAdminTheme(dialogContext),
        child: Dialog(
          backgroundColor: kAdminCard,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
            child: _LawyerDetailView(
                lawyerId: id,
                repo: _repo,
                onChanged: () => _load(silent: true)),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  const _Avatar({required this.name, this.url});
  static const _palette = [
    kAdminAccent,
    Color(0xFF7C3AED),
    kAdminGreen,
    kAdminAmber,
    Color(0xFFDB2777)
  ];

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(radius: 16, backgroundImage: NetworkImage(url!));
    }
    final trimmed = name.trim();
    final initials = trimmed.isEmpty
        ? '?'
        : trimmed
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join();
    final color =
        _palette[trimmed.isEmpty ? 0 : trimmed.codeUnitAt(0) % _palette.length];
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(initials,
          style: TextStyle(
              color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Tabbed detail dialog body.
class _LawyerDetailView extends StatefulWidget {
  final String lawyerId;
  final AdminRepository repo;
  final VoidCallback onChanged;
  const _LawyerDetailView(
      {required this.lawyerId, required this.repo, required this.onChanged});

  @override
  State<_LawyerDetailView> createState() => _LawyerDetailViewState();
}

class _LawyerDetailViewState extends State<_LawyerDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  static const _tabs = [
    'Overview',
    'Verification',
    'Documents',
    'Bookings',
    'Earnings',
    'Ratings & Reviews',
    'Cases',
    'Consultations',
    'Activity'
  ];

  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.repo.lawyerProfile(widget.lawyerId);
      if (!mounted) return;
      setState(() {
        _profile = (res['data'] as Map<String, dynamic>?) ?? {};
        _loading = false;
      });
    } on AdminException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await _loadProfile();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    if (_error != null || _profile == null) {
      return SizedBox(
        height: 260,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 30),
          const SizedBox(height: 10),
          const Text('Unable to load lawyer information',
              style: TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ]),
      );
    }
    final p = _profile!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _Avatar(
                name: p['name'] ?? '?',
                url: p['avatar_url'],
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(p['name'] ?? '',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kAdminTextPri)),
                    Text(p['email'] ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: kAdminTextMuted)),
                  ])),
              AdminBadge(p['verification_status'] ?? '',
                  AdminBadge.colorFor(p['verification_status'] ?? '')),
              const SizedBox(width: 6),
              AdminBadge(
                  p['is_active'] == true ? 'Active' : 'Suspended',
                  AdminBadge.colorFor(
                      p['is_active'] == true ? 'active' : 'suspended')),
              const SizedBox(width: 8),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: kAdminTextPri)),
            ]),
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
              height: 560,
              child: TabBarView(controller: _tabCtrl, children: [
                _OverviewTab(profile: p),
                _VerificationTab(
                    profile: p, repo: widget.repo, onChanged: _refresh),
                _DocumentsTab(
                    lawyerId: widget.lawyerId,
                    repo: widget.repo,
                    onChanged: _refresh),
                _BookingsTab(
                    lawyerId: widget.lawyerId,
                    repo: widget.repo,
                    mode: 'bookings'),
                _EarningsTab(profile: p),
                _ReviewsTab(lawyerId: widget.lawyerId, repo: widget.repo),
                _CasesTab(lawyerId: widget.lawyerId, repo: widget.repo),
                _BookingsTab(
                    lawyerId: widget.lawyerId,
                    repo: widget.repo,
                    mode: 'consultations'),
                _ActivityTab(lawyerId: widget.lawyerId, repo: widget.repo),
              ]),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (p['is_active'] == true)
                OutlinedButton.icon(
                  onPressed: () => _suspendDialog(),
                  icon: const Icon(Icons.block_rounded,
                      size: 16, color: kAdminRed),
                  label: const Text('Suspend Lawyer',
                      style: TextStyle(color: kAdminRed)),
                )
              else
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await widget.repo.reactivateLawyer(widget.lawyerId);
                      await _refresh();
                    } on AdminException catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Reactivate Lawyer'),
                ),
            ]),
          ]),
    );
  }

  Future<void> _suspendDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Suspend Lawyer'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'This lawyer will be prevented from receiving new bookings per the app\'s existing suspension rules.',
                  style: TextStyle(fontSize: 12.5, color: kAdminTextMuted)),
              const SizedBox(height: 16),
              TextField(
                  controller: ctrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Suspension reason (required)')),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Suspend')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    try {
      await widget.repo.suspendLawyer(widget.lawyerId, ctrl.text.trim());
      await _refresh();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

Widget _dr(String label, dynamic value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(color: kAdminTextMuted, fontSize: 12))),
        Expanded(
            child: SelectableText('${value ?? '-'}',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: kAdminTextPri))),
      ]),
    );

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

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _OverviewTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Profile'),
        const SizedBox(height: 10),
        Wrap(spacing: 24, runSpacing: 8, children: [
          _dr('Lawyer ID', p['id']),
          _dr('Phone',
              (p['phone'] ?? '').toString().isEmpty ? 'N/A' : p['phone']),
          _dr(
              'Designation',
              (p['designation'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : p['designation']),
          _dr(
              'Bar Council No.',
              (p['bar_council_number'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : p['bar_council_number']),
          _dr(
              'Specialization',
              (p['specialization'] ?? '').toString().isEmpty
                  ? 'N/A'
                  : p['specialization']),
          _dr('Joined Date', fmtDate(p['created_at'])),
        ]),
        const Divider(height: 28),
        _sectionLabel('Summary'),
        const SizedBox(height: 12),
        Wrap(spacing: 24, runSpacing: 14, children: [
          _statTile(
              'Total Bookings', '${p['total_bookings'] ?? 0}', kAdminAccent),
          _statTile(
              'Completed', '${p['completed_consultations'] ?? 0}', kAdminGreen),
          _statTile(
              'Cases', '${p['total_cases'] ?? 0}', const Color(0xFF7C3AED)),
          _statTile('Gross Earnings', fmtRupees(p['gross_earnings'] as num?),
              kAdminTextPri),
          _statTile('Pending Payout', fmtRupees(p['pending_payout'] as num?),
              kAdminAmber),
          _statTile(
              'Paid Payout', fmtRupees(p['paid_payout'] as num?), kAdminGreen),
        ]),
      ]),
    );
  }

  Widget _statTile(String label, String value, Color color) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
        ]),
      );
}

class _VerificationTab extends StatelessWidget {
  final Map<String, dynamic> profile;
  final AdminRepository repo;
  final VoidCallback onChanged;
  const _VerificationTab(
      {required this.profile, required this.repo, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final status = p['verification_status'] ?? '';
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel('Verification Status'),
          const SizedBox(width: 10),
          AdminBadge(status, AdminBadge.colorFor(status)),
        ]),
        const SizedBox(height: 12),
        _dr(
            'Bar Council No.',
            (p['bar_council_number'] ?? '').toString().isEmpty
                ? 'N/A'
                : p['bar_council_number']),
        if ((p['rejection_reason'] ?? '').toString().isNotEmpty)
          _dr('Rejection Reason', p['rejection_reason']),
        const SizedBox(height: 16),
        if (status == 'pending')
          Wrap(spacing: 10, children: [
            FilledButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Verify this lawyer?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Verify')),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  await repo.verifyLawyer(p['id'], 'verified');
                  onChanged();
                } on AdminException catch (e) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              icon: const Icon(Icons.verified_rounded, size: 16),
              label: const Text('Verify'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final ctrl = TextEditingController();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Reject Verification'),
                    content: TextField(
                        controller: ctrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            labelText: 'Rejection reason (required)')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reject')),
                    ],
                  ),
                );
                if (confirmed != true || ctrl.text.trim().isEmpty) return;
                try {
                  await repo.verifyLawyer(p['id'], 'rejected',
                      rejectionReason: ctrl.text.trim());
                  onChanged();
                } on AdminException catch (e) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              icon:
                  const Icon(Icons.cancel_rounded, size: 16, color: kAdminRed),
              label: const Text('Reject', style: TextStyle(color: kAdminRed)),
            ),
          ])
        else
          Text(
              'This lawyer\'s verification has already been decided ($status). See the Documents tab for individual document review.',
              style: const TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
      ]),
    );
  }
}

class _DocumentsTab extends StatefulWidget {
  final String lawyerId;
  final AdminRepository repo;
  final VoidCallback onChanged;
  const _DocumentsTab(
      {required this.lawyerId, required this.repo, required this.onChanged});

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  bool _loading = true;
  List<dynamic> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.repo.lawyerDocumentsList(widget.lawyerId);
      if (mounted) {
        setState(() {
          _docs = (res['data'] as List?) ?? [];
          _loading = false;
        });
      }
    } on AdminException catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminTableSkeleton(columns: 5);
    if (_docs.isEmpty)
      return const AdminEmptyState(message: 'No documents available');
    return ListView.builder(
      itemCount: _docs.length,
      itemBuilder: (context, i) {
        final d = _docs[i];
        final status = d['verification_status'] ?? 'pending';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: kAdminBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kAdminBorder)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.description_rounded,
                  size: 18, color: kAdminAccent),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(d['file_name'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: kAdminTextPri))),
              AdminBadge(status, AdminBadge.colorFor(status)),
            ]),
            const SizedBox(height: 6),
            _dr('Uploaded', fmtDate(d['uploaded_at'])),
            if ((d['verified_by_name'] ?? '').toString().isNotEmpty)
              _dr('Reviewed By', d['verified_by_name']),
            if ((d['rejection_reason'] ?? '').toString().isNotEmpty)
              _dr('Rejection Reason', d['rejection_reason']),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => showAdminLawyerDocumentPreview(
                    context, widget.repo, widget.lawyerId),
                icon: const Icon(Icons.visibility_rounded, size: 15),
                label: const Text('Preview'),
              ),
              if (status != 'approved')
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await widget.repo.approveLawyerDocument(d['id']);
                      await _load();
                      widget.onChanged();
                    } on AdminException catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 15),
                  label: const Text('Approve'),
                ),
              if (status != 'rejected')
                OutlinedButton.icon(
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Reject Document'),
                        content: TextField(
                            controller: ctrl,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                labelText: 'Rejection reason (required)')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Reject')),
                        ],
                      ),
                    );
                    if (confirmed != true || ctrl.text.trim().isEmpty) return;
                    try {
                      await widget.repo
                          .rejectLawyerDocument(d['id'], ctrl.text.trim());
                      await _load();
                      widget.onChanged();
                    } on AdminException catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  icon: const Icon(Icons.close_rounded,
                      size: 15, color: kAdminRed),
                  label:
                      const Text('Reject', style: TextStyle(color: kAdminRed)),
                ),
            ]),
          ]),
        );
      },
    );
  }
}

/// Opens the existing lawyer-verification document preview (reuses the
/// pre-existing /admin/lawyers/:id/document endpoint — no second document
/// viewer built for this module).
void showAdminLawyerDocumentPreview(
    BuildContext context, AdminRepository repo, String lawyerId) {
  showDialog(
    context: context,
    builder: (dialogContext) => Theme(
      data: buildAdminTheme(dialogContext),
      child: Dialog(
        backgroundColor: kAdminCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FutureBuilder<Map<String, dynamic>>(
              future: repo
                  .lawyerDocument(lawyerId)
                  .then((r) => (r['data'] as Map<String, dynamic>?) ?? {}),
              builder: (context, snap) {
                if (!snap.hasData)
                  return const SizedBox(
                      height: 200,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.4)));
                final d = snap.data!;
                final content = d['file_content'] as String? ?? '';
                return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(d['file_name'] ?? 'Document',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded)),
                      ]),
                      const Divider(height: 20),
                      if (content.isNotEmpty &&
                          (d['mime_type'] ?? '')
                              .toString()
                              .startsWith('image/'))
                        Expanded(
                            child: Image.memory(
                                Uri.parse(content).data!.contentAsBytes(),
                                fit: BoxFit.contain))
                      else
                        const Expanded(
                            child: Center(
                                child: Text(
                                    'Preview not available for this file type.',
                                    style: TextStyle(color: kAdminTextMuted)))),
                    ]);
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _EarningsTab extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _EarningsTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Earnings Summary'),
        const SizedBox(height: 4),
        const Text(
            'Figures reuse the same lawyer_payouts source of truth as Payouts & Settlements — no separate calculation.',
            style: TextStyle(
                color: kAdminTextMuted,
                fontSize: 10.5,
                fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        Wrap(spacing: 24, runSpacing: 14, children: [
          _tile('Gross Earnings', fmtRupees(p['gross_earnings'] as num?),
              kAdminAccent),
          _tile('Platform Commission', fmtRupees(0), const Color(0xFF7C3AED)),
          _tile('GST', fmtRupees(0), kAdminAmber),
          _tile('Net Earnings', fmtRupees(p['gross_earnings'] as num?),
              kAdminGreen),
          _tile('Pending Payout', fmtRupees(p['pending_payout'] as num?),
              kAdminAmber),
          _tile(
              'Paid Payout', fmtRupees(p['paid_payout'] as num?), kAdminGreen),
        ]),
        const SizedBox(height: 8),
        const Text(
            'No platform commission or GST is deducted from consultation earnings in this application — see Payouts & Settlements for detail.',
            style: TextStyle(
                color: kAdminTextMuted,
                fontSize: 10.5,
                fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _tile(String label, String value, Color color) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
        ]),
      );
}

class _BookingsTab extends StatefulWidget {
  final String lawyerId;
  final AdminRepository repo;
  final String
      mode; // 'bookings' | 'consultations' — same data, different framing
  const _BookingsTab(
      {required this.lawyerId, required this.repo, required this.mode});

  @override
  State<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<_BookingsTab> {
  bool _loading = true;
  List<dynamic> _rows = [];
  int _page = 1;
  bool _hasMore = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.repo
          .lawyerBookings(widget.lawyerId, status: _status, page: _page);
      if (mounted) {
        setState(() {
          _rows = (res['data'] as List?) ?? [];
          _hasMore = (res['meta']?['has_more'] as bool?) ?? false;
          _loading = false;
        });
      }
    } on AdminException catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBookingsMode = widget.mode == 'bookings';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isBookingsMode)
        Wrap(spacing: 8, children: [
          for (final s in const [
            ('', 'All'),
            ('upcoming', 'Upcoming'),
            ('completed', 'Completed'),
            ('cancelled', 'Cancelled'),
            ('rejected', 'Rejected'),
            ('expired', 'Expired')
          ])
            AdminFilterChip(
                label: s.$2,
                selected: _status == s.$1,
                onTap: () {
                  setState(() {
                    _status = s.$1;
                    _page = 1;
                  });
                  _load();
                }),
        ]),
      const SizedBox(height: 12),
      Expanded(
        child: _loading
            ? const AdminTableSkeleton(columns: 6)
            : _rows.isEmpty
                ? AdminEmptyState(
                    message: isBookingsMode
                        ? 'No booking history available'
                        : 'No consultation history available')
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(kAdminBg),
                        columns: const [
                          DataColumn(label: Text('Client')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Time')),
                          DataColumn(label: Text('Duration')),
                          DataColumn(label: Text('Amount')),
                          DataColumn(label: Text('Status')),
                        ],
                        rows: _rows.map((b) {
                          final durSec = (b['duration_seconds'] as int?) ?? 0;
                          return DataRow(cells: [
                            DataCell(Text(b['client_name'] ?? '-')),
                            DataCell(Text(b['consultation_type'] ?? '')),
                            DataCell(Text(b['date'] ?? '')),
                            DataCell(Text(b['time'] ?? '')),
                            DataCell(Text(durSec > 0
                                ? '${(durSec / 60).round()} min'
                                : 'N/A')),
                            DataCell(Text(fmtRupees(
                                (b['amount_paise'] as int? ?? 0) / 100))),
                            DataCell(AdminBadge(b['status'] ?? '',
                                AdminBadge.colorFor(b['status'] ?? ''))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
      ),
      AdminPager(
        page: _page,
        hasMore: _hasMore,
        loading: _loading,
        onPageChange: (p) {
          setState(() => _page = p);
          _load();
        },
      ),
    ]);
  }
}

class _ReviewsTab extends StatefulWidget {
  final String lawyerId;
  final AdminRepository repo;
  const _ReviewsTab({required this.lawyerId, required this.repo});

  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  bool _loading = true;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.repo.lawyerReviews(widget.lawyerId);
      if (mounted) {
        setState(() {
          _data = (res['data'] as Map<String, dynamic>?) ?? {};
          _loading = false;
        });
      }
    } on AdminException catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminLoader(topPadding: 60);
    final reviews = (_data['reviews'] as List?) ?? [];
    if (reviews.isEmpty) {
      return const AdminEmptyState(message: 'No reviews available');
    }
    return ListView.builder(
        itemCount: reviews.length, itemBuilder: (_, i) => const SizedBox());
  }
}

class _CasesTab extends StatefulWidget {
  final String lawyerId;
  final AdminRepository repo;
  const _CasesTab({required this.lawyerId, required this.repo});

  @override
  State<_CasesTab> createState() => _CasesTabState();
}

class _CasesTabState extends State<_CasesTab> {
  bool _loading = true;
  List<dynamic> _rows = [];
  int _page = 1;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.repo.lawyerCases(widget.lawyerId, page: _page);
      if (mounted) {
        setState(() {
          _rows = (res['data'] as List?) ?? [];
          _hasMore = (res['meta']?['has_more'] as bool?) ?? false;
          _loading = false;
        });
      }
    } on AdminException catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminTableSkeleton(columns: 6);
    if (_rows.isEmpty)
      return const AdminEmptyState(message: 'No cases available');
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(kAdminBg),
              columns: const [
                DataColumn(label: Text('Case')),
                DataColumn(label: Text('Client')),
                DataColumn(label: Text('Court')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Filing Date')),
                DataColumn(label: Text('Status')),
              ],
              rows: _rows.map((cs) {
                return DataRow(cells: [
                  DataCell(Text(cs['case_title'] ?? '')),
                  DataCell(Text((cs['client_name'] ?? '').toString().isEmpty
                      ? 'N/A'
                      : cs['client_name'])),
                  DataCell(Text((cs['court_name'] ?? '').toString().isEmpty
                      ? 'N/A'
                      : cs['court_name'])),
                  DataCell(Text((cs['case_type'] ?? '').toString().isEmpty
                      ? 'N/A'
                      : cs['case_type'])),
                  DataCell(Text(cs['filing_date'] == null
                      ? 'N/A'
                      : fmtDate(cs['filing_date']))),
                  DataCell(AdminBadge(cs['status'] ?? '',
                      AdminBadge.colorFor(cs['status'] ?? ''))),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
      AdminPager(
        page: _page,
        hasMore: _hasMore,
        loading: _loading,
        onPageChange: (p) {
          setState(() => _page = p);
          _load();
        },
      ),
    ]);
  }
}

class _ActivityTab extends StatefulWidget {
  final String lawyerId;
  final AdminRepository repo;
  const _ActivityTab({required this.lawyerId, required this.repo});

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  bool _loading = true;
  List<dynamic> _events = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.repo.lawyerActivity(widget.lawyerId);
      if (mounted) {
        setState(() {
          _events = (res['data'] as List?) ?? [];
          _loading = false;
        });
      }
    } on AdminException catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminLoader(topPadding: 60);
    if (_events.isEmpty)
      return const AdminEmptyState(message: 'No activity recorded yet');
    return ListView.builder(
      itemCount: _events.length,
      itemBuilder: (context, i) {
        final e = _events[i];
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
}
