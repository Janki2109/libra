import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/auto_refresh_service.dart';
import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

String fmtFullDate(dynamic raw) {
  if (raw == null) return '-';
  try {
    final dt = DateTime.parse(raw.toString()).toLocal();
    return '${DateFormat('d MMM yyyy').format(dt)} · ${DateFormat('h:mm a').format(dt)}';
  } catch (_) {
    return raw.toString();
  }
}

/// Super Admin → Notifications Center.
///
/// Reuses the existing `notifications` table (every user's real in-app
/// inbox) and utils.SendPushToUserTracked — the same Firebase Admin SDK
/// client every other push in this app already uses (see
/// admin_notifications_controller.go's file header). notification_batches
/// is the one new record: one row per Super Admin send/schedule action.
/// This screen is distinct from the pre-existing simple "Notifications"
/// broadcast screen, which is left untouched.
class AdminNotificationsCenterScreen extends StatefulWidget {
  const AdminNotificationsCenterScreen({super.key});
  @override
  State<AdminNotificationsCenterScreen> createState() =>
      _AdminNotificationsCenterScreenState();
}

class _AdminNotificationsCenterScreenState
    extends State<AdminNotificationsCenterScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AdminRepository();
  late TabController _tabCtrl;

  bool _statsLoading = true;
  Map<String, dynamic> _stats = {};

  bool _loading = true;
  String? _error;
  List<dynamic> _rows = [];
  int _page = 1;
  int _limit = 20;
  bool _hasMore = false;
  String _search = '';
  String _audienceFilter = '';
  String _statusFilter = '';
  DateTimeRange? _dateRange;

  static const _tabs = ['Scheduled', 'History'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) _load();
    });
    _loadStats();
    _load();
    AutoRefreshService.instance.register('admin_notifications_center',
        () async {
      await Future.wait([_loadStats(silent: true), _load(silent: true)]);
    });
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('admin_notifications_center');
    _tabCtrl.dispose();
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
      final res = await _repo.notificationCenterStats();
      if (!mounted) return;
      setState(() {
        _stats = (res['data'] as Map<String, dynamic>?) ?? {};
        _statsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final isScheduledTab = _tabs[_tabCtrl.index] == 'Scheduled';
    try {
      final res = await _repo.notificationBatches(
        search: _search,
        audience: _audienceFilter,
        status: isScheduledTab ? 'scheduled' : _statusFilter,
        from: isScheduledTab ? null : _fromStr,
        to: isScheduledTab ? null : _toStr,
        page: _page,
        limit: _limit,
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

  Future<void> _refreshAll() async {
    await Future.wait([_loadStats(silent: true), _load(silent: true)]);
  }

  num _n(String key) => (_stats[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/notifications-center',
      title: 'Notifications Center',
      actions: [
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refreshAll),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Notifications Center',
            style: TextStyle(
                color: kAdminTextPri,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
            'Send, schedule and manage notifications across the Libra platform',
            style: TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
        const SizedBox(height: 20),
        _statsGrid(),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _openComposer(),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Send Notification', style: TextStyle(fontSize: 14))),
        ),
        const SizedBox(height: 20),
        AdminSectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: kAdminAccent,
            unselectedLabelColor: kAdminTextMuted,
            indicatorColor: kAdminAccent,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
            height: 600,
            child: TabBarView(
                controller: _tabCtrl,
                children: [_scheduledTab(), _historyTab()])),
      ]),
    );
  }

  Widget _statsGrid() {
    if (_statsLoading) return const AdminStatGridSkeleton(count: 5);
    final cards = [
      (
        'Total Notifications',
        '${_n('total_notifications')}',
        Icons.campaign_rounded,
        kAdminAccent
      ),
      ('Sent Today', '${_n('sent_today')}', Icons.today_rounded, kAdminGreen),
      (
        'Scheduled',
        '${_n('scheduled')}',
        Icons.schedule_rounded,
        const Color(0xFF7C3AED)
      ),
      (
        'Delivered',
        '${_n('delivered')}',
        Icons.mark_email_read_rounded,
        kAdminGreen
      ),
      ('Failed', '${_n('failed')}', Icons.error_outline_rounded, kAdminRed),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 1200
          ? 5
          : (constraints.maxWidth > 700 ? 3 : 2);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.3,
        children: cards
            .map((c) => AdminStatCard(
                label: c.$1, value: c.$2, icon: c.$3, color: c.$4))
            .toList(),
      );
    });
  }

  Widget _scheduledTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_loading)
          const AdminTableSkeleton(columns: 6)
        else if (_error != null)
          _errorState()
        else if (_rows.isEmpty)
          const AdminEmptyState(message: 'No scheduled notifications')
        else
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(kAdminBg),
                  columns: const [
                    DataColumn(label: Text('Title')),
                    DataColumn(label: Text('Audience')),
                    DataColumn(label: Text('Scheduled Date/Time')),
                    DataColumn(label: Text('Created By')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _rows.map((n) {
                    return DataRow(cells: [
                      DataCell(SizedBox(
                          width: 200,
                          child: Text(n['title'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis))),
                      DataCell(AdminBadge(
                          _audienceLabel(n['target_type'] ?? ''),
                          kAdminAccent)),
                      DataCell(Text(fmtFullDate(n['scheduled_at']))),
                      DataCell(Text(
                          (n['created_by_name'] ?? '').toString().isEmpty
                              ? 'N/A'
                              : n['created_by_name'])),
                      DataCell(AdminBadge(n['status'] ?? '',
                          _statusColorFor(n['status'] ?? ''))),
                      DataCell(Row(children: [
                        IconButton(
                            tooltip: 'View',
                            icon:
                                const Icon(Icons.visibility_rounded, size: 17),
                            onPressed: () => _showDetail(n['id']),
                            visualDensity: VisualDensity.compact),
                        IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_rounded, size: 17),
                            onPressed: () => _openComposer(existing: n),
                            visualDensity: VisualDensity.compact),
                        IconButton(
                            tooltip: 'Cancel',
                            icon: const Icon(Icons.cancel_rounded,
                                size: 17, color: kAdminRed),
                            onPressed: () => _cancelScheduled(n['id']),
                            visualDensity: VisualDensity.compact),
                      ])),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _historyTab() {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminSearchField(
                hint: 'Search notification ID, title, message, created by…',
                onChanged: (v) {
                  _search = v;
                  _applyFilters();
                },
              ),
              _dropdown('Audience', _audienceFilter, const [
                ('', 'All audiences'),
                ('everyone', 'Everyone'),
                ('client', 'Clients'),
                ('lawyer', 'Lawyers'),
                ('student', 'Students'),
                ('selected', 'Selected Users'),
              ], (v) {
                setState(() => _audienceFilter = v);
                _applyFilters();
              }),
              _dropdown('Status', _statusFilter, const [
                ('', 'All statuses'),
                ('sent', 'Sent'),
                ('partially_sent', 'Partially Sent'),
                ('scheduled', 'Scheduled'),
                ('failed', 'Failed'),
                ('cancelled', 'Cancelled'),
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
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const AdminTableSkeleton(columns: 8)
              : _error != null
                  ? _errorState()
                  : _rows.isEmpty
                      ? AdminEmptyState(
                          message:
                              _search.isNotEmpty || _statusFilter.isNotEmpty
                                  ? 'No matching notifications found'
                                  : 'No notification history found')
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor:
                                  WidgetStateProperty.all(kAdminBg),
                              columns: const [
                                DataColumn(label: Text('Title')),
                                DataColumn(label: Text('Audience')),
                                DataColumn(label: Text('Created By')),
                                DataColumn(label: Text('Created')),
                                DataColumn(label: Text('Sent')),
                                DataColumn(label: Text('Recipients')),
                                DataColumn(label: Text('Delivered / Failed')),
                                DataColumn(label: Text('Status')),
                              ],
                              rows: _rows.map((n) {
                                return DataRow(
                                  onSelectChanged: (_) => _showDetail(n['id']),
                                  cells: [
                                    DataCell(SizedBox(
                                        width: 200,
                                        child: Text(n['title'] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis))),
                                    DataCell(AdminBadge(
                                        _audienceLabel(n['target_type'] ?? ''),
                                        kAdminAccent)),
                                    DataCell(Text((n['created_by_name'] ?? '')
                                            .toString()
                                            .isEmpty
                                        ? 'N/A'
                                        : n['created_by_name'])),
                                    DataCell(Text(fmtDate(n['created_at']))),
                                    DataCell(Text(n['sent_at'] == null
                                        ? '-'
                                        : fmtDate(n['sent_at']))),
                                    DataCell(
                                        Text('${n['recipient_count'] ?? 0}')),
                                    DataCell(Text(
                                        '${n['sent_count'] ?? 0} / ${n['failed_count'] ?? 0}',
                                        style: TextStyle(
                                            color: (n['failed_count'] as int? ??
                                                        0) >
                                                    0
                                                ? kAdminRed
                                                : kAdminGreen))),
                                    DataCell(AdminBadge(n['status'] ?? '',
                                        _statusColorFor(n['status'] ?? ''))),
                                  ],
                                );
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

  Widget _errorState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Column(children: [
            const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 34),
            const SizedBox(height: 10),
            const Text('Unable to load notifications',
                style: TextStyle(
                    color: kAdminTextPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => _load(), child: const Text('Retry')),
          ]),
        ),
      );

  String _audienceLabel(String t) {
    switch (t) {
      case 'everyone':
        return 'EVERYONE';
      case 'client':
        return 'CLIENTS';
      case 'lawyer':
        return 'LAWYERS';
      case 'student':
        return 'STUDENTS';
      case 'selected':
        return 'SELECTED USERS';
      default:
        return t.toUpperCase();
    }
  }

  Color _statusColorFor(String status) {
    switch (status) {
      case 'sent':
        return kAdminGreen;
      case 'partially_sent':
        return kAdminAmber;
      case 'scheduled':
        return const Color(0xFF7C3AED);
      case 'processing':
        return kAdminAccent;
      case 'failed':
        return kAdminRed;
      case 'cancelled':
      case 'draft':
        return kAdminTextMuted;
      default:
        return kAdminTextMuted;
    }
  }

  Future<void> _cancelScheduled(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this scheduled notification?'),
        content: const Text('It will not be sent.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel Notification')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.cancelScheduledNotification(id);
      await _refreshAll();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _showDetail(String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => Theme(
        data: buildAdminTheme(dialogContext),
        child: Dialog(
          backgroundColor: kAdminCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
            child: FutureBuilder<Map<String, dynamic>>(
              future: _repo
                  .notificationBatchDetail(id)
                  .then((r) => (r['data'] as Map<String, dynamic>?) ?? {}),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                      height: 220,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.4)));
                }
                final d = snap.data!;
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(d['title'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: kAdminTextPri))),
                          AdminBadge(d['status'] ?? '',
                              _statusColorFor(d['status'] ?? '')),
                          const SizedBox(width: 8),
                          IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded,
                                  color: kAdminTextPri)),
                        ]),
                        const Divider(height: 24),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d['message'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 13, color: kAdminTextPri)),
                                  const Divider(height: 24),
                                  _dr('Notification ID', d['id']),
                                  _dr('Target Audience',
                                      _audienceLabel(d['target_type'] ?? '')),
                                  if ((d['target_user_count'] as int? ?? 0) > 0)
                                    _dr('Selected Users',
                                        '${d['target_user_count']}'),
                                  _dr(
                                      'Action / Deep Link',
                                      (d['deep_link'] ?? '').toString().isEmpty
                                          ? 'N/A'
                                          : d['deep_link']),
                                  _dr('Created By', d['created_by_name']),
                                  _dr('Created Date',
                                      fmtFullDate(d['created_at'])),
                                  if (d['scheduled_at'] != null)
                                    _dr('Scheduled Date',
                                        fmtFullDate(d['scheduled_at'])),
                                  if (d['sent_at'] != null)
                                    _dr('Sent Date', fmtFullDate(d['sent_at'])),
                                  const Divider(height: 24),
                                  const Text('Delivery Summary',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          color: kAdminTextPri)),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 24, runSpacing: 10, children: [
                                    _statTile(
                                        'Recipients',
                                        '${d['recipient_count'] ?? 0}',
                                        kAdminAccent),
                                    _statTile('Sent (push accepted)',
                                        '${d['sent_count'] ?? 0}', kAdminGreen),
                                    _statTile('Failed',
                                        '${d['failed_count'] ?? 0}', kAdminRed),
                                  ]),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'True on-device delivery confirmation is not available from Firebase — "Sent" means the push was accepted by FCM or the user has an in-app notification, per user with no registered device.',
                                      style: TextStyle(
                                          color: kAdminTextMuted,
                                          fontSize: 10.5,
                                          fontStyle: FontStyle.italic)),
                                ]),
                          ),
                        ),
                      ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, Color color) => SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 11)),
        ]),
      );

  Widget _dr(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 140,
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

  void _openComposer({dynamic existing}) {
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
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
            child: _NotificationComposer(
                repo: _repo, existing: existing, onDone: _refreshAll),
          ),
        ),
      ),
    );
  }
}

/// The compose/edit form — creates or edits a notification_batches row.
class _NotificationComposer extends StatefulWidget {
  final AdminRepository repo;
  final dynamic existing;
  final VoidCallback onDone;
  const _NotificationComposer(
      {required this.repo, this.existing, required this.onDone});

  @override
  State<_NotificationComposer> createState() => _NotificationComposerState();
}

class _NotificationComposerState extends State<_NotificationComposer> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _deepLinkCtrl = TextEditingController();
  final _userSearchCtrl = TextEditingController();
  String _audience = 'everyone';
  DateTime? _scheduleDate;
  TimeOfDay? _scheduleTime;
  bool _scheduling = false;
  bool _sending = false;
  int? _estimate;
  bool _estimating = false;
  List<dynamic> _userResults = [];
  final Map<String, String> _selectedUsers = {}; // id -> display name
  late final String _idempotencyKey;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'ntc-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
    if (widget.existing != null) {
      _titleCtrl.text = widget.existing['title'] ?? '';
      _messageCtrl.text = widget.existing['message'] ?? '';
      _audience = widget.existing['target_type'] ?? 'everyone';
      final scheduledAt = widget.existing['scheduled_at'];
      if (scheduledAt != null) {
        final dt = DateTime.tryParse(scheduledAt)?.toLocal();
        if (dt != null) {
          _scheduling = true;
          _scheduleDate = DateTime(dt.year, dt.month, dt.day);
          _scheduleTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
        }
      }
    }
    _updateEstimate();
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _messageCtrl,
      _imageCtrl,
      _deepLinkCtrl,
      _userSearchCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _updateEstimate() async {
    if (_audience == 'selected' && _selectedUsers.isEmpty) {
      setState(() => _estimate = 0);
      return;
    }
    setState(() => _estimating = true);
    try {
      final n = await widget.repo.estimateNotificationRecipients(
          targetType: _audience, userIds: _selectedUsers.keys.toList());
      if (mounted)
        setState(() {
          _estimate = n;
          _estimating = false;
        });
    } on AdminException catch (_) {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _searchUsers(String q) async {
    if (q.trim().length < 2) {
      setState(() => _userResults = []);
      return;
    }
    try {
      final res = await widget.repo.users(search: q.trim());
      if (mounted) setState(() => _userResults = (res['data'] as List?) ?? []);
    } on AdminException catch (_) {}
  }

  String? get _scheduledAtIso {
    if (!_scheduling || _scheduleDate == null || _scheduleTime == null)
      return null;
    return DateTime(_scheduleDate!.year, _scheduleDate!.month,
            _scheduleDate!.day, _scheduleTime!.hour, _scheduleTime!.minute)
        .toUtc()
        .toIso8601String();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _messageCtrl.text.trim().isEmpty)
      return;
    if (_audience == 'selected' && _selectedUsers.isEmpty) return;
    if (_scheduling && (_scheduleDate == null || _scheduleTime == null)) return;

    final audienceLabel = {
      'everyone': 'Everyone',
      'client': 'Clients',
      'lawyer': 'Lawyers',
      'student': 'Students',
      'selected': 'Selected Users (${_selectedUsers.length})',
    }[_audience]!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(_scheduling
            ? 'Schedule this notification?'
            : 'Send this notification now?'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audience: $audienceLabel'),
              const SizedBox(height: 6),
              Text('Estimated recipients: ${_estimate ?? '…'}'),
              if (_scheduling) ...[
                const SizedBox(height: 6),
                Text(
                    'Scheduled for: ${_scheduleDate != null && _scheduleTime != null ? '${DateFormat('d MMM yyyy').format(_scheduleDate!)} ${_scheduleTime!.format(context)}' : '-'}'),
              ],
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_scheduling ? 'Schedule' : 'Send Now')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      if (_isEditing) {
        await widget.repo.updateScheduledNotification(
          widget.existing['id'],
          title: _titleCtrl.text.trim(),
          message: _messageCtrl.text.trim(),
          imageUrl:
              _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
          deepLink: _deepLinkCtrl.text.trim().isEmpty
              ? null
              : _deepLinkCtrl.text.trim(),
          scheduledAt: _scheduledAtIso!,
        );
      } else {
        await widget.repo.createNotificationBatch(
          title: _titleCtrl.text.trim(),
          message: _messageCtrl.text.trim(),
          imageUrl:
              _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
          deepLink: _deepLinkCtrl.text.trim().isEmpty
              ? null
              : _deepLinkCtrl.text.trim(),
          targetType: _audience,
          targetUserIds:
              _audience == 'selected' ? _selectedUsers.keys.toList() : null,
          scheduledAt: _scheduledAtIso,
          idempotencyKey: _idempotencyKey,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(
                      _isEditing
                          ? 'Edit Scheduled Notification'
                          : 'Send Notification',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kAdminTextPri))),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: kAdminTextPri)),
            ]),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: LayoutBuilder(builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 620;
                  final form = _formColumn();
                  final preview = _previewColumn();
                  if (stacked)
                    return Column(
                        children: [form, const SizedBox(height: 20), preview]);
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: form),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: preview),
                      ]);
                }),
              ),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(
                        _scheduling
                            ? Icons.schedule_rounded
                            : Icons.send_rounded,
                        size: 16),
                label: Text(_scheduling ? 'Schedule' : 'Send Now'),
              ),
            ]),
          ]),
    );
  }

  Widget _formColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _field(_titleCtrl, 'Title', maxLength: 100),
      const SizedBox(height: 12),
      _field(_messageCtrl, 'Message', maxLines: 4, maxLength: 500),
      const SizedBox(height: 12),
      _field(_imageCtrl, 'Image URL (optional)'),
      const SizedBox(height: 12),
      _field(_deepLinkCtrl, 'Deep Link / Action (optional)'),
      const SizedBox(height: 16),
      const Text('Target Audience',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: kAdminTextPri)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in const [
          ('everyone', 'Everyone'),
          ('client', 'Clients Only'),
          ('lawyer', 'Lawyers Only'),
          ('student', 'Students Only'),
          ('selected', 'Selected Users'),
        ])
          AdminFilterChip(
              label: a.$2,
              selected: _audience == a.$1,
              onTap: () {
                setState(() => _audience = a.$1);
                _updateEstimate();
              }),
      ]),
      if (_audience == 'selected') ...[
        const SizedBox(height: 12),
        AdminSearchField(
            hint: 'Search by name, email, user ID, phone…',
            onChanged: _searchUsers),
        if (_userResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
                border: Border.all(color: kAdminBorder),
                borderRadius: BorderRadius.circular(10)),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  TextButton(
                      onPressed: () {
                        setState(() {
                          for (final u in _userResults) {
                            _selectedUsers[u['id']] = u['name'] ?? '';
                          }
                        });
                        _updateEstimate();
                      },
                      child: const Text('Select All Results')),
                  TextButton(
                      onPressed: () {
                        setState(() => _selectedUsers.clear());
                        _updateEstimate();
                      },
                      child: const Text('Clear Selection')),
                ]),
              ),
              for (final u in _userResults)
                CheckboxListTile(
                  dense: true,
                  value: _selectedUsers.containsKey(u['id']),
                  title: Text('${u['name']}',
                      style: const TextStyle(fontSize: 12.5)),
                  subtitle: Text('${u['email']}',
                      style: const TextStyle(fontSize: 10.5)),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedUsers[u['id']] = u['name'] ?? '';
                      } else {
                        _selectedUsers.remove(u['id']);
                      }
                    });
                    _updateEstimate();
                  },
                ),
            ]),
          ),
        if (_selectedUsers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedUsers.entries
                .map((e) => Chip(
                      label:
                          Text(e.value, style: const TextStyle(fontSize: 11.5)),
                      onDeleted: () {
                        setState(() => _selectedUsers.remove(e.key));
                        _updateEstimate();
                      },
                    ))
                .toList(),
          ),
        ],
      ],
      const SizedBox(height: 16),
      Row(children: [
        Checkbox(
            value: _scheduling,
            onChanged: (v) => setState(() => _scheduling = v ?? false)),
        const Text('Schedule for later', style: TextStyle(fontSize: 12.5)),
      ]),
      if (_scheduling)
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_rounded, size: 16),
            label: Text(_scheduleDate == null
                ? 'Pick date'
                : DateFormat('d MMM yyyy').format(_scheduleDate!)),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                  context: context,
                  firstDate: now,
                  lastDate: DateTime(now.year + 2));
              if (picked != null) setState(() => _scheduleDate = picked);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time_rounded, size: 16),
            label: Text(_scheduleTime == null
                ? 'Pick time'
                : _scheduleTime!.format(context)),
            onPressed: () async {
              final picked = await showTimePicker(
                  context: context, initialTime: TimeOfDay.now());
              if (picked != null) setState(() => _scheduleTime = picked);
            },
          ),
          const Text('(device local time)',
              style: TextStyle(color: kAdminTextMuted, fontSize: 11)),
        ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: kAdminAccent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.people_alt_rounded, size: 16, color: kAdminAccent),
          const SizedBox(width: 8),
          Text(
              _estimating
                  ? 'Estimating recipients…'
                  : 'Estimated recipients: ${_estimate ?? '-'}',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kAdminAccent)),
        ]),
      ),
    ]);
  }

  Widget _previewColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Preview',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: kAdminTextPri)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kAdminBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kAdminBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: kAdminAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.gavel_rounded,
                  size: 15, color: kAdminAccent),
            ),
            const SizedBox(width: 8),
            const Text('Libra Law Practice',
                style: TextStyle(
                    fontSize: 11,
                    color: kAdminTextMuted,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text(
              _titleCtrl.text.trim().isEmpty
                  ? 'Notification title'
                  : _titleCtrl.text.trim(),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _titleCtrl.text.trim().isEmpty
                      ? kAdminTextMuted
                      : kAdminTextPri)),
          const SizedBox(height: 4),
          Text(
              _messageCtrl.text.trim().isEmpty
                  ? 'Notification message will appear here.'
                  : _messageCtrl.text.trim(),
              style: TextStyle(
                  fontSize: 12,
                  color: _messageCtrl.text.trim().isEmpty
                      ? kAdminTextMuted
                      : kAdminTextPri)),
          if (_imageCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(_imageCtrl.text.trim(),
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ],
          if (_deepLinkCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Action: ${_deepLinkCtrl.text.trim()}',
                style: const TextStyle(
                    fontSize: 10.5,
                    color: kAdminAccent,
                    fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
      const SizedBox(height: 8),
      const Text('Preview only — nothing is sent until you confirm.',
          style: TextStyle(
              color: kAdminTextMuted,
              fontSize: 10.5,
              fontStyle: FontStyle.italic)),
    ]);
  }

  Widget _field(TextEditingController ctrl, String label,
          {int maxLines = 1, int? maxLength}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: kAdminBg,
          counterText: '',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      );
}
