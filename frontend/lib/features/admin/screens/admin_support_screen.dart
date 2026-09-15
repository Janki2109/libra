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

/// Super Admin → Support / Complaints.
///
/// No support/ticket system existed anywhere in this app before migration
/// 029 (support_tickets/support_messages/support_ticket_history). Every
/// ticket, message and history row shown here is a real write from the
/// user-facing /support/tickets endpoints or this screen's own admin
/// actions — nothing is synthesized. Every management action here (assign,
/// priority, status, reply, resolve, close, reopen) also calls
/// utils.LogAudit on the backend, so it shows up in Audit Logs too.
class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({super.key});
  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

enum _QuickRange { today, last7, last30, thisMonth, custom }

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  final _repo = AdminRepository();

  bool _statsLoading = true;
  Map<String, dynamic> _stats = {};

  bool _ticketsLoading = true;
  String? _error;
  List<dynamic> _tickets = [];
  int _page = 1;
  int _limit = 20;
  bool _hasMore = false;

  List<dynamic> _superAdmins = [];

  String _search = '';
  String _roleFilter = '';
  String _statusFilter = '';
  String _priorityFilter = '';
  String _categoryFilter = '';
  String _assignedFilter = '';
  _QuickRange? _quickRange;
  DateTimeRange? _dateRange;
  String _sort = 'updated_at';
  String _order = 'desc';

  static const _categories = [
    'booking',
    'payment',
    'refund',
    'payout',
    'subscription',
    'account',
    'lawyer',
    'client',
    'student',
    'documents',
    'technical',
    'other',
  ];
  static const _statuses = [
    'open',
    'in_progress',
    'waiting_for_user',
    'resolved',
    'closed'
  ];
  static const _priorities = ['low', 'medium', 'high', 'urgent'];
  static const _roles = [
    ('client', 'CLIENT'),
    ('lawyer', 'LAWYER'),
    ('law_student', 'STUDENT'),
  ];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadTickets();
    _loadSuperAdmins();
    AutoRefreshService.instance.register('admin_support', () async {
      await Future.wait([_loadStats(silent: true), _loadTickets(silent: true)]);
    });
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('admin_support');
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
      final res = await _repo.supportStats();
      if (!mounted) return;
      setState(() {
        _stats = (res['data'] as Map<String, dynamic>?) ?? {};
        _statsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadSuperAdmins() async {
    try {
      final res = await _repo.users(role: 'super_admin');
      if (!mounted) return;
      setState(() => _superAdmins = (res['data'] as List?) ?? []);
    } on AdminException catch (_) {}
  }

  Future<void> _loadTickets({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _ticketsLoading = true;
        _error = null;
      });
    }
    try {
      final res = await _repo.supportTickets(
        search: _search,
        role: _roleFilter,
        status: _statusFilter,
        priority: _priorityFilter,
        category: _categoryFilter,
        assigned: _assignedFilter,
        from: _fromStr,
        to: _toStr,
        sort: _sort,
        order: _order,
        page: _page,
        limit: _limit,
      );
      if (!mounted) return;
      setState(() {
        _tickets = (res['data'] as List?) ?? [];
        _hasMore = (res['meta']?['has_more'] as bool?) ?? false;
        _ticketsLoading = false;
      });
    } on AdminException catch (e) {
      if (!silent && mounted) {
        setState(() {
          _ticketsLoading = false;
          _error = e.message;
        });
      }
    }
  }

  void _applyFilters() {
    _page = 1;
    _loadTickets();
  }

  void _filterByStatus(String status) {
    setState(() {
      _statusFilter = status;
      _priorityFilter = '';
    });
    _applyFilters();
  }

  void _filterHighPriority() {
    setState(() {
      _statusFilter = '';
      _priorityFilter = 'high';
    });
    _applyFilters();
  }

  void _clearCardFilter() {
    setState(() {
      _statusFilter = '';
      _priorityFilter = '';
    });
    _applyFilters();
  }

  void _setQuickRange(_QuickRange r) {
    final now = DateTime.now();
    DateTimeRange range;
    switch (r) {
      case _QuickRange.today:
        range = DateTimeRange(
            start: DateTime(now.year, now.month, now.day), end: now);
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
    _loadTickets();
  }

  num _n(String key) => (_stats[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/support',
      title: 'Support & Complaints',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () {
            _loadStats();
            _loadTickets();
          },
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Support & Complaints',
            style: TextStyle(
                color: kAdminTextPri,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Manage user complaints, support requests and resolutions',
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
    if (_statsLoading) return const AdminStatGridSkeleton(count: 6);
    final cards = [
      (
        'Total Tickets',
        '${_n('total_tickets')}',
        Icons.confirmation_number_rounded,
        kAdminAccent,
        _clearCardFilter
      ),
      (
        'Open',
        '${_n('open_tickets')}',
        Icons.markunread_mailbox_rounded,
        kAdminAccent,
        () => _filterByStatus('open')
      ),
      (
        'In Progress',
        '${_n('in_progress')}',
        Icons.autorenew_rounded,
        const Color(0xFF7C3AED),
        () => _filterByStatus('in_progress')
      ),
      (
        'Resolved',
        '${_n('resolved')}',
        Icons.check_circle_rounded,
        kAdminGreen,
        () => _filterByStatus('resolved')
      ),
      (
        'Closed',
        '${_n('closed')}',
        Icons.lock_rounded,
        kAdminTextMuted,
        () => _filterByStatus('closed')
      ),
      (
        'High Priority',
        '${_n('high_priority')}',
        Icons.priority_high_rounded,
        kAdminRed,
        _filterHighPriority
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 1200
          ? 6
          : (constraints.maxWidth > 800 ? 3 : 2);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.7,
        children: cards
            .map((c) => AdminStatCard(
                label: c.$1, value: c.$2, icon: c.$3, color: c.$4, onTap: c.$5))
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
                hint: 'Search ticket ID, user, email, subject, description…',
                onChanged: (v) {
                  _search = v;
                  _applyFilters();
                },
              ),
              _dropdown('Role', _roleFilter, [('', 'All roles'), ..._roles],
                  (v) {
                setState(() => _roleFilter = v);
                _applyFilters();
              }),
              _dropdown('Status', _statusFilter, [
                ('', 'All statuses'),
                ..._statuses
                    .map((s) => (s, s.replaceAll('_', ' ').toUpperCase()))
              ], (v) {
                setState(() {
                  _statusFilter = v;
                  _priorityFilter = '';
                });
                _applyFilters();
              }),
              _dropdown('Priority', _priorityFilter, [
                ('', 'All priorities'),
                ..._priorities.map((p) => (p, p.toUpperCase()))
              ], (v) {
                setState(() {
                  _priorityFilter = v;
                  _statusFilter = '';
                });
                _applyFilters();
              }),
              _dropdown('Category', _categoryFilter, [
                ('', 'All categories'),
                ..._categories
                    .map((c) => (c, c[0].toUpperCase() + c.substring(1)))
              ], (v) {
                setState(() => _categoryFilter = v);
                _applyFilters();
              }),
              _dropdown('Assigned', _assignedFilter, [
                ('', 'All'),
                ('unassigned', 'Unassigned'),
                ..._superAdmins.map((a) => ('${a['id']}', '${a['name']}')),
              ], (v) {
                setState(() => _assignedFilter = v);
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
              onPressed: () => _exportCsv(_tickets),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('CSV')),
          OutlinedButton.icon(
              onPressed: () => _exportPdf(_tickets),
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
              .map((o) => DropdownMenuItem(
                  value: o.$1,
                  child: Text(o.$2, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => onChanged(v ?? ''),
        ),
      );

  Widget _tableCard() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_ticketsLoading)
          const AdminTableSkeleton(columns: 9)
        else if (_error != null)
          _errorState()
        else if (_tickets.isEmpty)
          AdminEmptyState(
              message: (_search.isNotEmpty ||
                      _roleFilter.isNotEmpty ||
                      _statusFilter.isNotEmpty ||
                      _dateRange != null)
                  ? 'No matching tickets found'
                  : 'No support tickets found')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 50,
              dataRowMaxHeight: 60,
              headingRowColor: WidgetStateProperty.all(kAdminBg),
              columns: [
                const DataColumn(label: Text('Ticket')),
                const DataColumn(label: Text('User')),
                const DataColumn(label: Text('Role')),
                const DataColumn(label: Text('Subject')),
                const DataColumn(label: Text('Category')),
                _sortableColumn('Priority', 'priority'),
                const DataColumn(label: Text('Assigned To')),
                _sortableColumn('Updated', 'updated_at'),
                _sortableColumn('Status', 'status'),
              ],
              rows: _tickets.map((t) {
                final unread = t['has_unread_reply'] == true;
                return DataRow(
                  onSelectChanged: (_) => _showDetail(t['id']),
                  color: unread
                      ? WidgetStateProperty.all(
                          kAdminAccent.withValues(alpha: 0.03))
                      : null,
                  cells: [
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      if (unread)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                              color: kAdminAccent, shape: BoxShape.circle),
                        ),
                      Text('${t['ticket_number']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12)),
                    ])),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      _Avatar(name: t['user_name'] ?? '?'),
                      const SizedBox(width: 8),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t['user_name'] ?? '-'),
                            Text(t['user_email'] ?? '',
                                style: const TextStyle(
                                    color: kAdminTextMuted, fontSize: 10.5)),
                          ]),
                    ])),
                    DataCell(AdminBadge(
                        t['role'] ?? '', _roleColor(t['role'] ?? ''))),
                    DataCell(SizedBox(
                        width: 180,
                        child: Text(t['subject'] ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis))),
                    DataCell(Text((t['category'] ?? '').toString())),
                    DataCell(_priorityBadge(t['priority'] ?? '')),
                    DataCell(Text(
                        (t['assigned_name'] ?? '').toString().isEmpty
                            ? 'Unassigned'
                            : t['assigned_name'],
                        style: TextStyle(
                            color: (t['assigned_name'] ?? '').toString().isEmpty
                                ? kAdminTextMuted
                                : kAdminTextPri))),
                    DataCell(Text(fmtDate(t['updated_at']))),
                    DataCell(AdminBadge(
                        (t['status'] ?? '').toString().replaceAll('_', ' '),
                        _statusColor(t['status'] ?? ''))),
                  ],
                );
              }).toList(),
            ),
          ),
        AdminPager(
          page: _page,
          hasMore: _hasMore,
          loading: _ticketsLoading,
          onPageChange: (p) {
            setState(() => _page = p);
            _loadTickets();
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
            const Text('Unable to load support tickets',
                style: TextStyle(
                    color: kAdminTextPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_error ?? '',
                style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5)),
            const SizedBox(height: 12),
            TextButton(
                onPressed: () => _loadTickets(), child: const Text('Retry')),
          ]),
        ),
      );

  Color _roleColor(String role) {
    switch (role) {
      case 'LAWYER':
        return kAdminAccent;
      case 'CLIENT':
        return kAdminGreen;
      case 'STUDENT':
        return kAdminGold;
      default:
        return kAdminTextMuted;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return kAdminAccent;
      case 'in_progress':
        return const Color(0xFF7C3AED);
      case 'waiting_for_user':
        return kAdminAmber;
      case 'resolved':
        return kAdminGreen;
      case 'closed':
        return kAdminTextMuted;
      default:
        return kAdminTextMuted;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return kAdminRed;
      case 'high':
        return kAdminAmber;
      case 'medium':
        return kAdminAccent;
      default:
        return kAdminTextMuted;
    }
  }

  Widget _priorityBadge(String priority) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (priority == 'urgent' || priority == 'high')
          Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.arrow_upward_rounded,
                  size: 13, color: _priorityColor(priority))),
        AdminBadge(priority, _priorityColor(priority)),
      ]);

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
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
            child: _TicketDetailView(
              ticketId: id,
              repo: _repo,
              superAdmins: _superAdmins,
              onChanged: () {
                _loadStats();
                _loadTickets(silent: true);
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Export (current filtered page) ──
  void _exportCsv(List<dynamic> rows) {
    final table = [
      [
        'Ticket ID',
        'User',
        'Role',
        'Subject',
        'Category',
        'Priority',
        'Assigned To',
        'Status',
        'Created Date',
        'Updated Date'
      ],
      ...rows.map((t) => [
            '${t['ticket_number'] ?? ''}',
            '${t['user_name'] ?? ''}',
            '${t['role'] ?? ''}',
            '${t['subject'] ?? ''}',
            '${t['category'] ?? ''}',
            '${t['priority'] ?? ''}',
            (t['assigned_name'] ?? '').toString().isEmpty
                ? 'Unassigned'
                : '${t['assigned_name']}',
            '${t['status'] ?? ''}',
            fmtDate(t['created_at']),
            fmtDate(t['updated_at']),
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
        triggerBrowserDownload(bytes, 'libra_support_tickets.csv', 'text/csv');
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
                      pw.Text('Super Admin — Support & Complaints Report',
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
              'Ticket ID',
              'User',
              'Role',
              'Subject',
              'Category',
              'Priority',
              'Assigned To',
              'Status',
              'Updated'
            ],
            data: rows
                .map((t) => [
                      '${t['ticket_number'] ?? ''}',
                      '${t['user_name'] ?? ''}',
                      '${t['role'] ?? ''}',
                      '${t['subject'] ?? ''}',
                      '${t['category'] ?? ''}',
                      '${t['priority'] ?? ''}',
                      (t['assigned_name'] ?? '').toString().isEmpty
                          ? 'Unassigned'
                          : '${t['assigned_name']}',
                      '${t['status'] ?? ''}',
                      fmtDate(t['updated_at']),
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
        bytes, 'libra_support_tickets.pdf', 'application/pdf');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('PDF export is only available in the Chrome admin panel.')));
    }
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});
  static const _palette = [
    kAdminAccent,
    Color(0xFF7C3AED),
    kAdminGreen,
    kAdminAmber,
    Color(0xFFDB2777)
  ];

  @override
  Widget build(BuildContext context) {
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
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(initials,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

/// The ticket detail dialog body — its own StatefulWidget so it can reload
/// itself after an action (assign/priority/status/reply/resolve/close/
/// reopen) without the parent list screen needing to know about any of
/// that beyond "something changed, refresh the list".
class _TicketDetailView extends StatefulWidget {
  final String ticketId;
  final AdminRepository repo;
  final List<dynamic> superAdmins;
  final VoidCallback onChanged;
  const _TicketDetailView(
      {required this.ticketId,
      required this.repo,
      required this.superAdmins,
      required this.onChanged});

  @override
  State<_TicketDetailView> createState() => _TicketDetailViewState();
}

class _TicketDetailViewState extends State<_TicketDetailView> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.repo.supportTicketDetail(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _data = (res['data'] as Map<String, dynamic>?) ?? {};
        _loading = false;
        _error = null;
      });
    } on AdminException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _refreshAfterAction() async {
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    if (_error != null) {
      return SizedBox(
        height: 260,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 30),
          const SizedBox(height: 10),
          const Text('Unable to load ticket',
              style: TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ]),
      );
    }
    final t = (_data!['ticket'] as Map<String, dynamic>?) ?? {};
    final messages = (_data!['messages'] as List?) ?? [];
    final history = (_data!['history'] as List?) ?? [];
    final status = t['status'] ?? '';
    final closed = status == 'closed';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${t['ticket_number']}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kAdminTextPri)),
                    Text('${t['subject']}',
                        style: const TextStyle(
                            fontSize: 12.5, color: kAdminTextMuted)),
                  ])),
              AdminBadge((status).toString().replaceAll('_', ' '),
                  _statusColorStatic(status)),
              const SizedBox(width: 8),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: kAdminTextPri)),
            ]),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Ticket Information'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 24, runSpacing: 8, children: [
                        _dr('Category', t['category']),
                        _dr('Priority',
                            (t['priority'] ?? '').toString().toUpperCase()),
                        _dr('Created', fmtFull(t['created_at'])),
                        _dr('Last Updated', fmtFull(t['updated_at'])),
                      ]),
                      const Divider(height: 24),
                      _label('User Information'),
                      const SizedBox(height: 8),
                      _dr('Name', t['user_name']),
                      _dr('Email', t['user_email']),
                      _dr('User ID', t['user_id']),
                      _dr('Role', t['role']),
                      if ((t['user_phone'] ?? '').toString().isNotEmpty)
                        _dr('Phone', t['user_phone']),
                      const Divider(height: 24),
                      _label('Complaint / Description'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: kAdminBg,
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${t['description'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 12.5, color: kAdminTextPri)),
                      ),
                      const Divider(height: 24),
                      _label('Assignment'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: t['assigned_id'] ?? '',
                            isExpanded: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: kAdminBg,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none),
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: '', child: Text('Unassigned')),
                              ...widget.superAdmins.map((a) => DropdownMenuItem(
                                  value: '${a['id']}',
                                  child: Text('${a['name']}'))),
                            ],
                            onChanged: closed
                                ? null
                                : (v) async {
                                    try {
                                      await widget.repo.assignSupportTicket(
                                          widget.ticketId, v ?? '');
                                      await _refreshAfterAction();
                                    } on AdminException catch (e) {
                                      if (mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(e.message)));
                                    }
                                  },
                          ),
                        ),
                      ]),
                      if ((t['assigned_at']) != null)
                        _dr('Assigned Date', fmtFull(t['assigned_at'])),
                      const Divider(height: 24),
                      _label('Priority & Status'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 12, runSpacing: 10, children: [
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            initialValue: t['priority'],
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Priority',
                              filled: true,
                              fillColor: kAdminBg,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none),
                            ),
                            items: _supportPriorityOptions
                                .map((p) => DropdownMenuItem(
                                    value: p, child: Text(p.toUpperCase())))
                                .toList(),
                            onChanged: closed
                                ? null
                                : (v) async {
                                    if (v == null) return;
                                    try {
                                      await widget.repo.updateSupportPriority(
                                          widget.ticketId, v);
                                      await _refreshAfterAction();
                                    } on AdminException catch (e) {
                                      if (mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(e.message)));
                                    }
                                  },
                          ),
                        ),
                        if (!closed && status != 'resolved')
                          SizedBox(
                            width: 190,
                            child: DropdownButtonFormField<String>(
                              initialValue: [
                                'open',
                                'in_progress',
                                'waiting_for_user'
                              ].contains(status)
                                  ? status
                                  : 'open',
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Status',
                                filled: true,
                                fillColor: kAdminBg,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'open', child: Text('OPEN')),
                                DropdownMenuItem(
                                    value: 'in_progress',
                                    child: Text('IN PROGRESS')),
                                DropdownMenuItem(
                                    value: 'waiting_for_user',
                                    child: Text('WAITING FOR USER')),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                try {
                                  await widget.repo
                                      .updateSupportStatus(widget.ticketId, v);
                                  await _refreshAfterAction();
                                } on AdminException catch (e) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.message)));
                                }
                              },
                            ),
                          ),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        if (status != 'resolved' && status != 'closed')
                          FilledButton.icon(
                            onPressed: () => _resolveDialog(),
                            icon: const Icon(Icons.task_alt_rounded, size: 16),
                            label: const Text('Resolve'),
                          ),
                        if (status == 'resolved')
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await widget.repo
                                    .closeSupportTicket(widget.ticketId);
                                await _refreshAfterAction();
                              } on AdminException catch (e) {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.message)));
                              }
                            },
                            icon: const Icon(Icons.lock_rounded, size: 16),
                            label: const Text('Close Ticket'),
                          ),
                        if (status == 'resolved' || status == 'closed')
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await widget.repo
                                    .reopenSupportTicket(widget.ticketId);
                                await _refreshAfterAction();
                              } on AdminException catch (e) {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.message)));
                              }
                            },
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: const Text('Reopen Ticket'),
                          ),
                      ]),
                      if ((t['resolution_note'] ?? '')
                          .toString()
                          .isNotEmpty) ...[
                        const Divider(height: 24),
                        _label('Resolution'),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: kAdminGreen.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kAdminGreen.withValues(alpha: 0.2))),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t['resolution_note']}',
                                    style: const TextStyle(
                                        fontSize: 12.5, color: kAdminTextPri)),
                                const SizedBox(height: 8),
                                _dr(
                                    'Resolved By',
                                    (t['resolved_by_name'] ?? '')
                                            .toString()
                                            .isEmpty
                                        ? 'N/A'
                                        : t['resolved_by_name']),
                                _dr(
                                    'Resolved Date',
                                    t['resolved_at'] == null
                                        ? 'N/A'
                                        : fmtFull(t['resolved_at'])),
                                if ((t['closed_by_name'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  _dr('Closed By', t['closed_by_name']),
                                if (t['closed_at'] != null)
                                  _dr('Closed Date', fmtFull(t['closed_at'])),
                              ]),
                        ),
                      ],
                      const Divider(height: 24),
                      _label('Conversation'),
                      const SizedBox(height: 10),
                      if (messages.isEmpty)
                        const Text('No messages yet.',
                            style: TextStyle(
                                color: kAdminTextMuted, fontSize: 12.5))
                      else
                        ...messages.map((m) => _messageBubble(m)),
                      const SizedBox(height: 10),
                      if (!closed)
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _replyCtrl,
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    hintText: 'Reply to this user…',
                                    filled: true,
                                    fillColor: kAdminBg,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: _sending ? null : _sendReply,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.send_rounded, size: 18),
                              ),
                            ])
                      else
                        const Text(
                            'This ticket is closed. Reopen it to continue the conversation.',
                            style: TextStyle(
                                color: kAdminTextMuted,
                                fontSize: 12,
                                fontStyle: FontStyle.italic)),
                      const Divider(height: 24),
                      _label('History'),
                      const SizedBox(height: 10),
                      if (history.isEmpty)
                        const Text('No activity recorded yet.',
                            style: TextStyle(
                                color: kAdminTextMuted, fontSize: 12.5))
                      else
                        _timeline(history),
                    ]),
              ),
            ),
          ]),
    );
  }

  Widget _messageBubble(dynamic m) {
    final isAdmin = m['sender_role'] == 'SUPER ADMIN';
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: isAdmin ? kAdminAccent.withValues(alpha: 0.08) : kAdminBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isAdmin
                  ? kAdminAccent.withValues(alpha: 0.25)
                  : kAdminBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${m['sender_name']}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: kAdminTextPri)),
            const SizedBox(width: 6),
            AdminBadge(
                m['sender_role'] ?? '', isAdmin ? kAdminAccent : kAdminGreen),
            const SizedBox(width: 8),
            Text(fmtFull(m['created_at']),
                style: const TextStyle(color: kAdminTextMuted, fontSize: 10)),
          ]),
          const SizedBox(height: 6),
          Text('${m['message']}',
              style: const TextStyle(fontSize: 12.5, color: kAdminTextPri)),
        ]),
      ),
    );
  }

  Widget _timeline(List<dynamic> history) {
    return Column(
      children: history.reversed.map((h) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 4, right: 10),
              decoration:
                  BoxDecoration(color: kAdminAccent, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtFull(h['created_at']),
                        style: const TextStyle(
                            color: kAdminTextMuted, fontSize: 10.5)),
                    const SizedBox(height: 2),
                    Text(_historyLabel(h),
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kAdminTextPri)),
                    Text(
                        'by ${h['actor_name'] ?? 'System'} (${h['actor_role']})',
                        style: const TextStyle(
                            color: kAdminTextMuted, fontSize: 11)),
                  ]),
            ),
          ]),
        );
      }).toList(),
    );
  }

  String _historyLabel(dynamic h) {
    final action = (h['action'] ?? '').toString();
    final before = (h['before'] ?? '').toString();
    final after = (h['after'] ?? '').toString();
    switch (action) {
      case 'TICKET_CREATED':
        return 'Ticket created';
      case 'SUPPORT_TICKET_ASSIGNED':
        return 'Ticket assigned';
      case 'SUPPORT_TICKET_REASSIGNED':
        return 'Ticket reassigned';
      case 'SUPPORT_TICKET_UNASSIGNED':
        return 'Ticket unassigned';
      case 'SUPPORT_PRIORITY_CHANGED':
        return 'Priority changed from ${before.toUpperCase()} → ${after.toUpperCase()}';
      case 'SUPPORT_STATUS_CHANGED':
        return 'Status changed from ${before.replaceAll('_', ' ').toUpperCase()} → ${after.replaceAll('_', ' ').toUpperCase()}';
      case 'SUPPORT_REPLY_SENT':
        return 'Super Admin replied';
      case 'USER_REPLIED':
        return 'User replied';
      case 'SUPPORT_TICKET_RESOLVED':
        return 'Ticket resolved';
      case 'SUPPORT_TICKET_CLOSED':
        return 'Ticket closed';
      case 'SUPPORT_TICKET_REOPENED':
        return 'Ticket reopened';
      default:
        return action;
    }
  }

  Future<void> _sendReply() async {
    final msg = _replyCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.repo.replySupportTicket(widget.ticketId, msg);
      _replyCtrl.clear();
      await _refreshAfterAction();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resolveDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Resolve Ticket'),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Resolution note',
              hintText:
                  'e.g. Payment proof verified and payment status updated.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resolve')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    try {
      await widget.repo.resolveSupportTicket(widget.ticketId, ctrl.text.trim());
      await _refreshAfterAction();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
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

  Widget _dr(String label, dynamic value) => SizedBox(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 110,
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
        ),
      );

  Color _statusColorStatic(String status) {
    switch (status) {
      case 'open':
        return kAdminAccent;
      case 'in_progress':
        return const Color(0xFF7C3AED);
      case 'waiting_for_user':
        return kAdminAmber;
      case 'resolved':
        return kAdminGreen;
      case 'closed':
        return kAdminTextMuted;
      default:
        return kAdminTextMuted;
    }
  }
}

const _supportPriorityOptions = ['low', 'medium', 'high', 'urgent'];

String fmtFull(dynamic raw) {
  if (raw == null) return '-';
  try {
    final dt = DateTime.parse(raw.toString()).toLocal();
    return '${DateFormat('d MMM yyyy').format(dt)} · ${DateFormat('h:mm a').format(dt)}';
  } catch (_) {
    return raw.toString();
  }
}
