import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/auto_refresh_service.dart';
import '../../lawyer/utils/browser_download.dart';
import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Super Admin → Audit Logs.
///
/// audit_logs already existed (migration 007) for a couple of write sites;
/// migration 028 extended it (actor_role, target_type, device_type,
/// request_id, status, description) and made it append-only at the database
/// level, and utils.LogAudit/LogSystemAudit is now called from the real
/// action points this module claims to track (lawyer verification,
/// user suspension, refunds, payouts, subscription cancellation, case
/// status changes). Every row shown here is a real write from one of those
/// call sites — nothing is synthesized for this screen.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});
  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

enum _QuickRange { today, yesterday, last7, last30, thisMonth, custom }

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  final _repo = AdminRepository();

  bool _statsLoading = true;
  Map<String, dynamic> _stats = {};

  bool _logsLoading = true;
  String? _error;
  List<dynamic> _logs = [];
  int _page = 1;
  int _limit = 20;
  bool _hasMore = false;

  String _search = '';
  String _roleFilter = '';
  String _actionFilter = '';
  String _moduleFilter = '';
  String _statusFilter = '';
  _QuickRange? _quickRange;
  DateTimeRange? _dateRange;
  String _sort = 'created_at';
  String _order = 'desc';

  // Only action types this codebase actually writes — see admin_audit_controller.go.
  static const _knownActions = [
    'LAWYER_VERIFIED',
    'LAWYER_REJECTED',
    'USER_SUSPENDED',
    'USER_ACTIVATED',
    'PAYOUT_MARKED_PAID',
    'REFUND_PROCESSED',
    'SUBSCRIPTION_UPDATED',
    'CASE_STATUS_CHANGED',
    'password_changed',
    'bank_details_updated',
  ];
  static const _knownModules = [
    'lawyers',
    'users',
    'payouts',
    'payments',
    'subscriptions',
    'cases',
    'auth',
    'firm',
  ];
  static const _roleOptions = [
    ('super_admin', 'SUPER ADMIN'),
    ('lawyer', 'LAWYER'),
    ('client', 'CLIENT'),
    ('law_student', 'STUDENT'),
    ('system', 'SYSTEM'),
  ];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadLogs();
    AutoRefreshService.instance.register('admin_audit', () async {
      await Future.wait([_loadStats(silent: true), _loadLogs(silent: true)]);
    });
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('admin_audit');
    super.dispose();
  }

  String? get _fromStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.start)
      : null;
  String? get _toStr => _dateRange != null
      ? DateFormat('yyyy-MM-dd').format(_dateRange!.end)
      : null;

  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) setState(() => _statsLoading = true);
    try {
      final res = await _repo.auditLogStats();
      if (!mounted) return;
      setState(() {
        _stats = (res['data'] as Map<String, dynamic>?) ?? {};
        _statsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadLogs({bool silent = false}) async {
    if (!silent)
      setState(() {
        _logsLoading = true;
        _error = null;
      });
    try {
      final res = await _repo.auditLogs(
        search: _search,
        role: _roleFilter,
        action: _actionFilter,
        module: _moduleFilter,
        status: _statusFilter,
        from: _fromStr,
        to: _toStr,
        sort: _sort,
        order: _order,
        page: _page,
        limit: _limit,
      );
      if (!mounted) return;
      setState(() {
        _logs = (res['data'] as List?) ?? [];
        _hasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _logsLoading = false;
      });
    } on AdminException catch (e) {
      if (!silent && mounted)
        setState(() {
          _logsLoading = false;
          _error = e.message;
        });
    }
  }

  void _applyFilters() {
    _page = 1;
    _loadLogs();
  }

  void _setQuickRange(_QuickRange r) {
    final now = DateTime.now();
    DateTimeRange range;
    switch (r) {
      case _QuickRange.today:
        range = DateTimeRange(
            start: DateTime(now.year, now.month, now.day), end: now);
        break;
      case _QuickRange.yesterday:
        final y = now.subtract(const Duration(days: 1));
        range = DateTimeRange(
            start: DateTime(y.year, y.month, y.day),
            end: DateTime(y.year, y.month, y.day, 23, 59, 59));
        break;
      case _QuickRange.last7:
        range = DateTimeRange(
            start: now.subtract(const Duration(days: 6)), end: now);
        break;
      case _QuickRange.last30:
        range = DateTimeRange(
            start: now.subtract(const Duration(days: 29)), end: now);
        break;
      case _QuickRange.thisMonth:
        range =
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
        break;
      case _QuickRange.custom:
        _pickCustomRange();
        return;
    }
    setState(() {
      _quickRange = r;
      _dateRange = range;
    });
    _applyFilters();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _dateRange);
    if (picked != null) {
      setState(() {
        _quickRange = _QuickRange.custom;
        _dateRange = picked;
      });
      _applyFilters();
    }
  }

  void _clearDateRange() {
    setState(() {
      _quickRange = null;
      _dateRange = null;
    });
    _applyFilters();
  }

  void _toggleSort(String col) {
    setState(() {
      if (_sort == col) {
        _order = _order == 'desc' ? 'asc' : 'desc';
      } else {
        _sort = col;
        _order = 'desc';
      }
    });
    _loadLogs();
  }

  num _n(String key) => (_stats[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/audit',
      title: 'Audit Logs',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () {
            _loadStats();
            _loadLogs();
          },
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Audit Logs',
            style: TextStyle(
                color: kAdminTextPri,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
            'Track important administrative actions and changes across the platform',
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
    if (_statsLoading) return const AdminStatGridSkeleton(count: 4);
    final cards = [
      (
        'Total Events',
        '${_n('total_events')}',
        Icons.history_rounded,
        kAdminAccent
      ),
      (
        'Today\'s Events',
        '${_n('today_events')}',
        Icons.today_rounded,
        kAdminGreen
      ),
      (
        'High-Risk Actions',
        '${_n('high_risk_actions')}',
        Icons.warning_amber_rounded,
        kAdminRed
      ),
      (
        'Super Admin Actions',
        '${_n('super_admin_actions')}',
        Icons.shield_rounded,
        const Color(0xFF7C3AED)
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 1000
          ? 4
          : (constraints.maxWidth > 620 ? 2 : 1);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.6,
        children: cards
            .map((c) => AdminStatCard(
                label: c.$1, value: c.$2, icon: c.$3, color: c.$4))
            .toList(),
      );
    });
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
                hint:
                    'Search actor, email, user ID, action, target, description…',
                onChanged: (v) {
                  _search = v;
                  _applyFilters();
                },
              ),
              _dropdown(
                  'Role', _roleFilter, [('', 'All roles'), ..._roleOptions],
                  (v) {
                setState(() => _roleFilter = v);
                _applyFilters();
              }),
              _dropdown('Action', _actionFilter, [
                ('', 'All actions'),
                ..._knownActions.map((a) => (a, a))
              ], (v) {
                setState(() => _actionFilter = v);
                _applyFilters();
              }),
              _dropdown('Module', _moduleFilter, [
                ('', 'All modules'),
                ..._knownModules.map((m) => (m, m))
              ], (v) {
                setState(() => _moduleFilter = v);
                _applyFilters();
              }),
              _dropdown('Status', _statusFilter, const [
                ('', 'All statuses'),
                ('success', 'Success'),
                ('failed', 'Failed')
              ], (v) {
                setState(() => _statusFilter = v);
                _applyFilters();
              }),
              _dropdown('Page size', '$_limit', const [
                ('20', '20 / page'),
                ('50', '50 / page'),
                ('100', '100 / page')
              ], (v) {
                setState(() => _limit = int.parse(v));
                _applyFilters();
              }),
            ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in const [
            (_QuickRange.today, 'Today'),
            (_QuickRange.yesterday, 'Yesterday'),
            (_QuickRange.last7, 'Last 7 Days'),
            (_QuickRange.last30, 'Last 30 Days'),
            (_QuickRange.thisMonth, 'This Month'),
          ])
            AdminFilterChip(
                label: r.$2,
                selected: _quickRange == r.$1,
                onTap: () => _setQuickRange(r.$1)),
          GestureDetector(
            onTap: _pickCustomRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _quickRange == _QuickRange.custom
                    ? kAdminAccent.withValues(alpha: 0.1)
                    : kAdminBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _quickRange == _QuickRange.custom
                        ? kAdminAccent
                        : kAdminBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.date_range_rounded,
                    size: 15,
                    color: _quickRange == _QuickRange.custom
                        ? kAdminAccent
                        : kAdminTextMuted),
                const SizedBox(width: 6),
                Text(
                    _dateRange == null
                        ? 'Custom range'
                        : '${DateFormat('d MMM').format(_dateRange!.start)} – ${DateFormat('d MMM').format(_dateRange!.end)}',
                    style: TextStyle(
                        color: _quickRange == _QuickRange.custom
                            ? kAdminAccent
                            : kAdminTextPri,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                if (_dateRange != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                      onTap: _clearDateRange,
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: kAdminAccent)),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
              onPressed: () => _exportCsv(_logs),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('CSV')),
          OutlinedButton.icon(
              onPressed: () => _exportPdf(_logs),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text('PDF')),
        ]),
      ]),
    );
  }

  Widget _dropdown(String hint, String value, List<(String, String)> options,
          ValueChanged<String> onChanged) =>
      SizedBox(
        width: 168,
        child: DropdownButtonFormField<String>(
          initialValue: options.any((o) => o.$1 == value) ? value : '',
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: kAdminBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
          style: const TextStyle(fontSize: 12.5, color: kAdminTextPri),
          items: options
              .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
              .toList(),
          onChanged: (v) => onChanged(v ?? ''),
        ),
      );

  Widget _tableCard() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_logsLoading)
          const AdminTableSkeleton(columns: 8)
        else if (_error != null)
          _errorState()
        else if (_logs.isEmpty)
          AdminEmptyState(
              message: (_search.isNotEmpty ||
                      _roleFilter.isNotEmpty ||
                      _actionFilter.isNotEmpty ||
                      _dateRange != null)
                  ? 'No matching audit events found'
                  : 'No audit activity found')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 48,
              dataRowMaxHeight: 56,
              headingRowColor: WidgetStateProperty.all(kAdminBg),
              columns: [
                _sortableColumn('Date & Time', 'created_at'),
                _sortableColumn('Actor', 'actor'),
                const DataColumn(label: Text('Role')),
                _sortableColumn('Action', 'action'),
                _sortableColumn('Module', 'module'),
                const DataColumn(label: Text('Target')),
                const DataColumn(label: Text('IP Address')),
                const DataColumn(label: Text('Device')),
                const DataColumn(label: Text('Status')),
              ],
              rows: _logs.map((l) {
                final highRisk = l['high_risk'] == true;
                return DataRow(
                  onSelectChanged: (_) => _showDetail(l['id']),
                  color: highRisk
                      ? WidgetStateProperty.all(
                          kAdminRed.withValues(alpha: 0.03))
                      : null,
                  cells: [
                    DataCell(Text(_fmtDateTime(l['created_at']),
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l['actor_name'] ?? 'System',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          if ((l['actor_email'] ?? '').toString().isNotEmpty)
                            Text(l['actor_email'],
                                style: const TextStyle(
                                    color: kAdminTextMuted, fontSize: 10.5)),
                        ])),
                    DataCell(AdminBadge(
                        l['role'] ?? '', _roleColor(l['role'] ?? ''))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      if (highRisk)
                        const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.warning_amber_rounded,
                                size: 14, color: kAdminRed)),
                      Text(l['action'] ?? '',
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ])),
                    DataCell(Text(l['module'] ?? '-')),
                    DataCell(Text(
                        l['target_id'] == null
                            ? '-'
                            : '${l['target_id']}'.substring(0, 8),
                        style: const TextStyle(
                            fontSize: 11, color: kAdminTextMuted))),
                    DataCell(Text(l['ip_address'] ?? 'Unavailable',
                        style: const TextStyle(fontSize: 11.5))),
                    DataCell(Text((l['device'] ?? '').toString().isEmpty
                        ? 'Unavailable'
                        : l['device'])),
                    DataCell(AdminBadge(l['status'] ?? '',
                        AdminBadge.colorFor(l['status'] ?? ''))),
                  ],
                );
              }).toList(),
            ),
          ),
        AdminPager(
          page: _page,
          hasMore: _hasMore,
          loading: _logsLoading,
          onPageChange: (p) {
            setState(() => _page = p);
            _loadLogs();
          },
        ),
      ]),
    );
  }

  DataColumn _sortableColumn(String label, String key) => DataColumn(
        label: GestureDetector(
          onTap: () => _toggleSort(key),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label),
            if (_sort == key) ...[
              const SizedBox(width: 3),
              Icon(
                  _order == 'desc'
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 12,
                  color: kAdminAccent),
            ],
          ]),
        ),
      );

  Widget _errorState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Column(children: [
            const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 34),
            const SizedBox(height: 10),
            const Text('Unable to load audit logs',
                style: TextStyle(
                    color: kAdminTextPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_error ?? '',
                style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
            const SizedBox(height: 12),
            TextButton(
                onPressed: () => _loadLogs(), child: const Text('Retry')),
          ]),
        ),
      );

  Color _roleColor(String role) {
    switch (role) {
      case 'SUPER ADMIN':
        return const Color(0xFF7C3AED);
      case 'LAWYER':
        return kAdminAccent;
      case 'CLIENT':
        return kAdminGreen;
      case 'STUDENT':
        return kAdminGold;
      case 'SYSTEM':
        return kAdminTextMuted;
      default:
        return kAdminTextMuted;
    }
  }

  String _fmtDateTime(dynamic raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${DateFormat('d MMM yyyy').format(dt)}\n${DateFormat('h:mm:ss a').format(dt)}';
    } catch (_) {
      return raw.toString();
    }
  }

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
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FutureBuilder<Map<String, dynamic>>(
                future: _repo
                    .auditLogDetail(id)
                    .then((r) => (r['data'] as Map<String, dynamic>?) ?? {}),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return SizedBox(
                      height: 220,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: kAdminRed, size: 30),
                            const SizedBox(height: 10),
                            const Text('Unable to load audit event',
                                style: TextStyle(
                                    color: kAdminTextMuted, fontSize: 12.5)),
                            const SizedBox(height: 12),
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close')),
                          ]),
                    );
                  }
                  if (!snap.hasData) {
                    return const SizedBox(
                        height: 220,
                        child: Center(
                            child:
                                CircularProgressIndicator(strokeWidth: 2.4)));
                  }
                  final d = snap.data!;
                  final before = d['before'] as Map<String, dynamic>?;
                  final after = d['after'] as Map<String, dynamic>?;
                  final changedFields = <String>{
                    ...(before?.keys ?? []),
                    ...(after?.keys ?? [])
                  };

                  return SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Expanded(
                                child: Text('Audit Event',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: kAdminTextPri))),
                            AdminBadge(d['status'] ?? '',
                                AdminBadge.colorFor(d['status'] ?? '')),
                            const SizedBox(width: 6),
                            IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded,
                                    color: kAdminTextPri)),
                          ]),
                          const Divider(height: 28),
                          _label('Actor'),
                          const SizedBox(height: 8),
                          _dr('Name', d['actor_name'] ?? 'System'),
                          _dr(
                              'Email',
                              (d['actor_email'] ?? '').toString().isEmpty
                                  ? 'N/A'
                                  : d['actor_email']),
                          _dr('Role', d['role']),
                          const Divider(height: 24),
                          _label('Action'),
                          const SizedBox(height: 8),
                          Row(children: [
                            if (auditIsHighRisk(d['action'] ?? ''))
                              const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.warning_amber_rounded,
                                      size: 16, color: kAdminRed)),
                            Text(d['action'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: kAdminTextPri)),
                          ]),
                          const Divider(height: 24),
                          _label('Module'),
                          const SizedBox(height: 8),
                          _dr('Module', d['module']),
                          _dr(
                              'Target Type',
                              (d['target_type'] ?? '').toString().isEmpty
                                  ? 'N/A'
                                  : d['target_type']),
                          _dr('Target ID', d['target_id'] ?? 'N/A'),
                          const Divider(height: 24),
                          _label('Date & Time'),
                          const SizedBox(height: 8),
                          _dr('Timestamp', _fmtFull(d['created_at'])),
                          const Divider(height: 24),
                          _label('Network'),
                          const SizedBox(height: 8),
                          _dr('IP Address', d['ip_address'] ?? 'Unavailable'),
                          _dr(
                              'Device',
                              (d['device'] ?? '').toString().isEmpty
                                  ? 'Unavailable'
                                  : d['device']),
                          if ((d['description'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            const Divider(height: 24),
                            _label('Description'),
                            const SizedBox(height: 8),
                            Text(d['description'],
                                style: const TextStyle(
                                    fontSize: 12.5, color: kAdminTextPri)),
                          ],
                          if (changedFields.isNotEmpty) ...[
                            const Divider(height: 24),
                            _label('Changes'),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                  border: Border.all(color: kAdminBorder),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Column(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration:
                                      const BoxDecoration(color: kAdminBg),
                                  child: const Row(children: [
                                    Expanded(
                                        flex: 2,
                                        child: Text('Field',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11.5,
                                                color: kAdminTextMuted))),
                                    Expanded(
                                        flex: 3,
                                        child: Text('Before',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11.5,
                                                color: kAdminTextMuted))),
                                    Expanded(
                                        flex: 3,
                                        child: Text('After',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11.5,
                                                color: kAdminTextMuted))),
                                  ]),
                                ),
                                for (final f in changedFields)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    decoration: const BoxDecoration(
                                        border: Border(
                                            top: BorderSide(
                                                color: kAdminBorder))),
                                    child: Row(children: [
                                      Expanded(
                                          flex: 2,
                                          child: Text(f,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: kAdminTextPri))),
                                      Expanded(
                                          flex: 3,
                                          child: Text('${before?[f] ?? '-'}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: kAdminRed))),
                                      Expanded(
                                          flex: 3,
                                          child: Text('${after?[f] ?? '-'}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: kAdminGreen))),
                                    ]),
                                  ),
                              ]),
                            ),
                          ],
                          const Divider(height: 24),
                          _label('Metadata'),
                          const SizedBox(height: 8),
                          _dr(
                              'Request ID',
                              (d['request_id'] ?? '').toString().isEmpty
                                  ? 'N/A'
                                  : d['request_id']),
                          _dr('Event ID', d['id']),
                        ]),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Row(children: [
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

  Widget _dr(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style:
                      const TextStyle(color: kAdminTextMuted, fontSize: 12))),
          Expanded(
              child: SelectableText('${value ?? '-'}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: kAdminTextPri))),
        ]),
      );

  String _fmtFull(dynamic raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${DateFormat('d MMM yyyy').format(dt)} · ${DateFormat('h:mm:ss a').format(dt)}';
    } catch (_) {
      return raw.toString();
    }
  }

  // ── Export (current filtered page) ──
  void _exportCsv(List<dynamic> rows) {
    final table = [
      [
        'Date & Time',
        'Actor',
        'Role',
        'Action',
        'Module',
        'Target',
        'Description',
        'IP',
        'Device',
        'Status'
      ],
      ...rows.map((l) => [
            _fmtFull(l['created_at']),
            '${l['actor_name'] ?? 'System'}',
            '${l['role'] ?? ''}',
            '${l['action'] ?? ''}',
            '${l['module'] ?? ''}',
            '${l['target_id'] ?? ''}',
            '${l['description'] ?? ''}',
            '${l['ip_address'] ?? 'Unavailable'}',
            '${l['device'] ?? 'Unavailable'}',
            '${l['status'] ?? ''}',
          ]),
    ];
    final csv = table
        .map((row) => row.map((cell) {
              final escaped = cell.replaceAll('"', '""');
              return escaped.contains(',') ||
                      escaped.contains('"') ||
                      escaped.contains('\n')
                  ? '"$escaped"'
                  : escaped;
            }).join(','))
        .join('\r\n');
    final bytes = Uint8List.fromList(csv.codeUnits);
    final ok =
        triggerBrowserDownload(bytes, 'libra_audit_logs.csv', 'text/csv');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('CSV export is only available in the Chrome admin panel.')));
    }
  }

  Future<void> _exportPdf(List<dynamic> rows) async {
    final doc = pw.Document();
    final now = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('LIBRA LAW',
                          style: pw.TextStyle(
                              fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Super Admin — Audit Logs Report',
                          style: const pw.TextStyle(fontSize: 12)),
                    ]),
                pw.Text('Generated: $now',
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
          pw.SizedBox(height: 10),
          pw.Text('Records: ${rows.length}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'Date & Time',
              'Actor',
              'Role',
              'Action',
              'Module',
              'Target',
              'IP',
              'Device',
              'Status'
            ],
            data: rows
                .map((l) => [
                      _fmtFull(l['created_at']),
                      '${l['actor_name'] ?? 'System'}',
                      '${l['role'] ?? ''}',
                      '${l['action'] ?? ''}',
                      '${l['module'] ?? ''}',
                      '${l['target_id'] ?? ''}',
                      '${l['ip_address'] ?? 'Unavailable'}',
                      '${l['device'] ?? 'Unavailable'}',
                      '${l['status'] ?? ''}',
                    ])
                .toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    final ok = triggerBrowserDownload(
        bytes, 'libra_audit_logs.pdf', 'application/pdf');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('PDF export is only available in the Chrome admin panel.')));
    }
  }
}

/// Mirrors admin_audit_controller.go's auditHighRisk — kept in sync manually
/// since this is purely a UI emphasis (icon/badge), not a security boundary.
bool auditIsHighRisk(String action) {
  const highRisk = {
    'REFUND_APPROVED',
    'REFUND_REJECTED',
    'REFUND_PROCESSED',
    'PAYOUT_APPROVED',
    'PAYOUT_MARKED_PAID',
    'LAWYER_VERIFIED',
    'LAWYER_REJECTED',
    'USER_ROLE_CHANGED',
    'USER_SUSPENDED',
    'SETTINGS_CHANGED',
  };
  return highRisk.contains(action);
}
