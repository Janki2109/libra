import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/auto_refresh_service.dart';
import '../repositories/admin_repository.dart';
import '../widgets/admin_shell.dart';
import '../widgets/admin_widgets.dart';

/// Super Admin → Content Management.
///
/// No content system existed anywhere in this app before migration 030.
/// Legal Articles / FAQs / Banners / Announcements / Promotional Content
/// all share one content_items table (a content_type discriminator) since
/// they have the same real shape; Terms & Conditions / Privacy Policy get
/// their own versioned legal_documents table, since those must never be
/// silently overwritten. The backend's ContentSweeper is what actually
/// moves scheduled → published and published → archived at the configured
/// times — this screen only ever triggers an explicit action.
class AdminContentScreen extends StatefulWidget {
  const AdminContentScreen({super.key});
  @override
  State<AdminContentScreen> createState() => _AdminContentScreenState();
}

class _AdminContentScreenState extends State<AdminContentScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AdminRepository();
  late TabController _tabCtrl;

  bool _statsLoading = true;
  Map<String, dynamic> _stats = {};

  static const _tabs = [
    'Articles',
    'FAQs',
    'Banners',
    'Announcements',
    'Promotions',
    'Terms',
    'Privacy Policy'
  ];
  static const _tabIcons = [
    Icons.article_rounded,
    Icons.quiz_rounded,
    Icons.view_carousel_rounded,
    Icons.campaign_rounded,
    Icons.local_offer_rounded,
    Icons.gavel_rounded,
    Icons.privacy_tip_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _loadStats();
    AutoRefreshService.instance.register('admin_content', () async {
      await _loadStats(silent: true);
    });
  }

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('admin_content');
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) setState(() => _statsLoading = true);
    try {
      final res = await _repo.contentStats();
      if (!mounted) return;
      setState(() {
        _stats = (res['data'] as Map<String, dynamic>?) ?? {};
        _statsLoading = false;
      });
    } on AdminException catch (_) {
      if (!silent && mounted) setState(() => _statsLoading = false);
    }
  }

  num _n(String key) => (_stats[key] as num?) ?? 0;
  num _byType(String key) =>
      ((_stats['by_type'] as Map?) ?? {})[key] as num? ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: '/admin/content',
      title: 'Content Management',
      actions: [
        IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => _loadStats()),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Content Management',
            style: TextStyle(
                color: kAdminTextPri,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
            'Manage legal content, FAQs, announcements, banners and app information',
            style: TextStyle(color: kAdminTextMuted, fontSize: 12.5)),
        const SizedBox(height: 20),
        _statsGrid(),
        const SizedBox(height: 20),
        AdminSectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: kAdminAccent,
            unselectedLabelColor: kAdminTextMuted,
            indicatorColor: kAdminAccent,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: List.generate(
                _tabs.length,
                (i) => Tab(
                    icon: Icon(_tabIcons[i], size: 16),
                    text: _tabs[i],
                    iconMargin: const EdgeInsets.only(bottom: 4))),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 680,
          child: TabBarView(controller: _tabCtrl, children: [
            _ContentTypeTab(
                contentType: 'article', repo: _repo, onChanged: _loadStats),
            _ContentTypeTab(
                contentType: 'faq', repo: _repo, onChanged: _loadStats),
            _ContentTypeTab(
                contentType: 'banner', repo: _repo, onChanged: _loadStats),
            _ContentTypeTab(
                contentType: 'announcement',
                repo: _repo,
                onChanged: _loadStats),
            _ContentTypeTab(
                contentType: 'promotion', repo: _repo, onChanged: _loadStats),
            _LegalDocTab(docType: 'terms', repo: _repo, onChanged: _loadStats),
            _LegalDocTab(
                docType: 'privacy', repo: _repo, onChanged: _loadStats),
          ]),
        ),
      ]),
    );
  }

  Widget _statsGrid() {
    if (_statsLoading) return const AdminStatGridSkeleton(count: 5);
    final cards = [
      (
        'Total Content',
        '${_n('total_content')}',
        Icons.dashboard_customize_rounded,
        kAdminAccent
      ),
      (
        'Published',
        '${_n('published')}',
        Icons.check_circle_rounded,
        kAdminGreen
      ),
      ('Drafts', '${_n('drafts')}', Icons.edit_note_rounded, kAdminTextMuted),
      (
        'Scheduled',
        '${_n('scheduled')}',
        Icons.schedule_rounded,
        const Color(0xFF7C3AED)
      ),
      ('Archived', '${_n('archived')}', Icons.archive_rounded, kAdminAmber),
    ];
    final typeCards = [
      (
        'Legal Articles',
        '${_byType('article')}',
        Icons.article_rounded,
        kAdminAccent
      ),
      (
        'FAQs',
        '${_byType('faq')}',
        Icons.quiz_rounded,
        const Color(0xFF7C3AED)
      ),
      (
        'Banners',
        '${_byType('banner')}',
        Icons.view_carousel_rounded,
        kAdminGreen
      ),
      (
        'Announcements',
        '${_byType('announcement')}',
        Icons.campaign_rounded,
        kAdminAmber
      ),
      (
        'Promotional Content',
        '${_byType('promotion')}',
        Icons.local_offer_rounded,
        kAdminGold
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AdminStatGrid(
        cards: cards
            .map((c) => AdminStatCard(
                label: c.$1, value: c.$2, icon: c.$3, color: c.$4))
            .toList(),
      ),
      const SizedBox(height: 12),
      AdminStatGrid(
        cards: typeCards
            .map((c) => AdminStatCard(
                label: c.$1, value: c.$2, icon: c.$3, color: c.$4))
            .toList(),
      ),
    ]);
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'published':
      return kAdminGreen;
    case 'draft':
      return kAdminTextMuted;
    case 'scheduled':
      return const Color(0xFF7C3AED);
    case 'unpublished':
      return kAdminAmber;
    case 'archived':
      return kAdminTextMuted;
    default:
      return kAdminTextMuted;
  }
}

String fmtFullDate(dynamic raw) {
  if (raw == null) return '-';
  try {
    final dt = DateTime.parse(raw.toString()).toLocal();
    return '${DateFormat('d MMM yyyy').format(dt)} · ${DateFormat('h:mm a').format(dt)}';
  } catch (_) {
    return raw.toString();
  }
}

/// One tab body shared by article/faq/banner/announcement/promotion — same
/// list, filters, editor and workflow actions, parameterized by content
/// type so the five near-identical UIs aren't duplicated five times.
class _ContentTypeTab extends StatefulWidget {
  final String contentType;
  final AdminRepository repo;
  final VoidCallback onChanged;
  const _ContentTypeTab(
      {required this.contentType, required this.repo, required this.onChanged});

  @override
  State<_ContentTypeTab> createState() => _ContentTypeTabState();
}

class _ContentTypeTabState extends State<_ContentTypeTab> {
  bool _loading = true;
  String? _error;
  List<dynamic> _items = [];
  int _page = 1;
  bool _hasMore = false;
  String _search = '';
  String _statusFilter = '';

  static const _statuses = [
    'draft',
    'scheduled',
    'published',
    'unpublished',
    'archived'
  ];

  bool get _isFaq => widget.contentType == 'faq';
  bool get _hasSchedule =>
      ['banner', 'announcement', 'promotion'].contains(widget.contentType);

  String get _typeLabel {
    switch (widget.contentType) {
      case 'article':
        return 'Article';
      case 'faq':
        return 'FAQ';
      case 'banner':
        return 'Banner';
      case 'announcement':
        return 'Announcement';
      default:
        return 'Promotion';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.repo.contentItems(
        type: widget.contentType,
        search: _search,
        status: _statusFilter,
        sort: _isFaq ? 'display_order' : 'updated_at',
        order: _isFaq ? 'asc' : 'desc',
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        _items = (res['data'] as List?) ?? [];
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
    await _load(silent: true);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AdminSearchField(
                    hint: 'Search title, content, category…',
                    onChanged: (v) {
                      _search = v;
                      _applyFilters();
                    },
                  ),
                  for (final s in const [''])
                    AdminFilterChip(
                        label: 'All',
                        selected: _statusFilter == s,
                        onTap: () {
                          setState(() => _statusFilter = '');
                          _applyFilters();
                        }),
                  for (final s in _statuses)
                    AdminFilterChip(
                        label: s.toUpperCase(),
                        selected: _statusFilter == s,
                        onTap: () {
                          setState(() => _statusFilter = s);
                          _applyFilters();
                        }),
                ]),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text('New $_typeLabel'),
          ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 460,
          child: _loading
              ? const AdminTableSkeleton(columns: 6)
              : _error != null
                  ? _errorState()
                  : _items.isEmpty
                      ? AdminEmptyState(
                          message:
                              _search.isNotEmpty || _statusFilter.isNotEmpty
                                  ? 'No matching content found'
                                  : 'No content found')
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 58,
                              headingRowColor:
                                  WidgetStateProperty.all(kAdminBg),
                              columns: [
                                const DataColumn(label: Text('Content')),
                                const DataColumn(label: Text('Category')),
                                const DataColumn(label: Text('Audience')),
                                const DataColumn(label: Text('Created By')),
                                const DataColumn(label: Text('Updated')),
                                const DataColumn(label: Text('Published')),
                                const DataColumn(label: Text('Status')),
                                const DataColumn(label: Text('Actions')),
                              ],
                              rows: _items.map((item) {
                                final status = item['status'] ?? '';
                                return DataRow(cells: [
                                  DataCell(SizedBox(
                                      width: 220,
                                      child: Text(item['title'] ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis))),
                                  DataCell(Text((item['category'] ?? '')
                                          .toString()
                                          .isEmpty
                                      ? '-'
                                      : item['category'])),
                                  DataCell(AdminBadge(
                                      (item['target_audience'] ?? '')
                                          .toString()
                                          .toUpperCase(),
                                      kAdminAccent)),
                                  DataCell(Text((item['created_by_name'] ?? '')
                                          .toString()
                                          .isEmpty
                                      ? 'N/A'
                                      : item['created_by_name'])),
                                  DataCell(Text(fmtDate(item['updated_at']))),
                                  DataCell(Text(item['published_at'] == null
                                      ? '-'
                                      : fmtDate(item['published_at']))),
                                  DataCell(
                                      AdminBadge(status, _statusColor(status))),
                                  DataCell(_actionsFor(item)),
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
      ]),
    );
  }

  Widget _errorState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Column(children: [
            const Icon(Icons.error_outline_rounded, color: kAdminRed, size: 34),
            const SizedBox(height: 10),
            const Text('Unable to load content',
                style: TextStyle(
                    color: kAdminTextPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => _load(), child: const Text('Retry')),
          ]),
        ),
      );

  Widget _actionsFor(dynamic item) {
    final status = item['status'] ?? '';
    final id = item['id'] as String;
    return Wrap(spacing: 4, children: [
      IconButton(
          tooltip: 'View / Edit',
          icon: const Icon(Icons.edit_rounded, size: 17),
          onPressed: () => _openEditor(existing: item),
          visualDensity: VisualDensity.compact),
      IconButton(
          tooltip: 'Preview',
          icon: const Icon(Icons.visibility_rounded, size: 17),
          onPressed: () => _preview(id),
          visualDensity: VisualDensity.compact),
      if (status == 'draft' || status == 'unpublished') ...[
        IconButton(
            tooltip: 'Publish',
            icon:
                const Icon(Icons.publish_rounded, size: 17, color: kAdminGreen),
            onPressed: () => _confirmPublish(id),
            visualDensity: VisualDensity.compact),
        if (_hasSchedule)
          IconButton(
              tooltip: 'Schedule',
              icon: const Icon(Icons.schedule_rounded,
                  size: 17, color: Color(0xFF7C3AED)),
              onPressed: () => _scheduleDialog(id),
              visualDensity: VisualDensity.compact),
      ],
      if (status == 'published')
        IconButton(
            tooltip: 'Unpublish',
            icon: const Icon(Icons.unpublished_rounded,
                size: 17, color: kAdminAmber),
            onPressed: () async {
              try {
                await widget.repo.unpublishContentItem(id);
                await _refreshAll();
              } on AdminException catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            visualDensity: VisualDensity.compact),
      if (status != 'archived')
        IconButton(
            tooltip: 'Archive',
            icon: const Icon(Icons.archive_rounded, size: 17),
            onPressed: () async {
              try {
                await widget.repo.archiveContentItem(id);
                await _refreshAll();
              } on AdminException catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            visualDensity: VisualDensity.compact),
      if (status == 'draft')
        IconButton(
            tooltip: 'Delete draft',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 17, color: kAdminRed),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete this draft?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await widget.repo.deleteContentItem(id);
                await _refreshAll();
              } on AdminException catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            visualDensity: VisualDensity.compact),
    ]);
  }

  Future<void> _confirmPublish(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Publish this content?'),
        content: const Text(
            'It will become visible to the selected audience immediately.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.publishContentItem(id);
      await _refreshAll();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _scheduleDialog(String id) async {
    DateTime? date;
    TimeOfDay? time;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          StatefulBuilder(builder: (dialogContext, setSt) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Schedule Publish'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: Text(date == null
                      ? 'Pick publish date'
                      : DateFormat('d MMM yyyy').format(date!)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                        context: dialogContext,
                        firstDate: now,
                        lastDate: DateTime(now.year + 2));
                    if (picked != null) setSt(() => date = picked);
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(time == null
                      ? 'Pick publish time'
                      : time!.format(dialogContext)),
                  onPressed: () async {
                    final picked = await showTimePicker(
                        context: dialogContext, initialTime: TimeOfDay.now());
                    if (picked != null) setSt(() => time = picked);
                  },
                ),
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: date == null || time == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Schedule')),
          ],
        );
      }),
    );
    if (result != true || date == null || time == null) return;
    final publishAt =
        DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute)
            .toUtc()
            .toIso8601String();
    try {
      await widget.repo.scheduleContentItem(id, publishAt);
      await _refreshAll();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _preview(String id) async {
    try {
      final res = await widget.repo.contentItemDetail(id);
      final d = (res['data'] as Map<String, dynamic>?) ?? {};
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => Theme(
          data: buildAdminTheme(dialogContext),
          child: Dialog(
            backgroundColor: kAdminCard,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Preview',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded)),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 500,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: kAdminBg,
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: kAdminBorder, width: 2)),
                          child: SingleChildScrollView(
                            child: _isFaq
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                        Text('${d['title']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: kAdminTextPri)),
                                        const Divider(height: 20),
                                        Text('${d['body'] ?? ''}',
                                            style: const TextStyle(
                                                fontSize: 12.5,
                                                color: kAdminTextPri)),
                                      ])
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                        if ((d['image_url'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Image.network(d['image_url'],
                                                height: 120,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const SizedBox.shrink()),
                                          ),
                                        const SizedBox(height: 10),
                                        Text('${d['title']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                                color: kAdminTextPri)),
                                        if ((d['subtitle'] ?? '')
                                            .toString()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text('${d['subtitle']}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: kAdminTextMuted)),
                                        ],
                                        const SizedBox(height: 10),
                                        Text('${d['body'] ?? ''}',
                                            style: const TextStyle(
                                                fontSize: 12.5,
                                                color: kAdminTextPri)),
                                        if ((d['cta_text'] ?? '')
                                            .toString()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 14),
                                          FilledButton(
                                              onPressed: null,
                                              child: Text('${d['cta_text']}')),
                                        ],
                                      ]),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      );
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openEditor({dynamic existing}) {
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
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
            child: _ContentEditor(
              contentType: widget.contentType,
              existingId: existing?['id'],
              repo: widget.repo,
              onSaved: _refreshAll,
            ),
          ),
        ),
      ),
    );
  }
}

/// The create/edit form for one content_items row — fields shown vary by
/// content_type (FAQ needs question/answer/order; banner/announcement/
/// promotion need image/CTA/audience; article needs subtitle/tags).
class _ContentEditor extends StatefulWidget {
  final String contentType;
  final String? existingId;
  final AdminRepository repo;
  final VoidCallback onSaved;
  const _ContentEditor(
      {required this.contentType,
      this.existingId,
      required this.repo,
      required this.onSaved});

  @override
  State<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<_ContentEditor> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _ctaTextCtrl = TextEditingController();
  final _ctaActionCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '0');
  String _audience = 'all';
  bool _loading = false;
  bool _saving = false;
  Map<String, dynamic>? _existing;

  bool get _isFaq => widget.contentType == 'faq';
  bool get _isArticle => widget.contentType == 'article';
  bool get _hasCta =>
      ['banner', 'announcement', 'promotion'].contains(widget.contentType);

  @override
  void initState() {
    super.initState();
    if (widget.existingId != null) _load();
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _subtitleCtrl,
      _bodyCtrl,
      _categoryCtrl,
      _imageCtrl,
      _ctaTextCtrl,
      _ctaActionCtrl,
      _tagsCtrl,
      _orderCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.repo.contentItemDetail(widget.existingId!);
      final d = (res['data'] as Map<String, dynamic>?) ?? {};
      _existing = d;
      _titleCtrl.text = d['title'] ?? '';
      _subtitleCtrl.text = d['subtitle'] ?? '';
      _bodyCtrl.text = d['body'] ?? '';
      _categoryCtrl.text = d['category'] ?? '';
      _imageCtrl.text = d['image_url'] ?? '';
      _ctaTextCtrl.text = d['cta_text'] ?? '';
      _ctaActionCtrl.text = d['cta_action'] ?? '';
      _tagsCtrl.text = ((d['tags'] as List?) ?? []).join(', ');
      _orderCtrl.text = '${d['display_order'] ?? 0}';
      _audience = d['target_audience'] ?? 'all';
    } on AdminException catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final data = {
      'content_type': widget.contentType,
      'title': _titleCtrl.text.trim(),
      'subtitle': _subtitleCtrl.text.trim(),
      'body': _bodyCtrl.text.trim(),
      'category': _categoryCtrl.text.trim(),
      'image_url': _imageCtrl.text.trim(),
      'cta_text': _ctaTextCtrl.text.trim(),
      'cta_action': _ctaActionCtrl.text.trim(),
      'tags': _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      'target_audience': _audience,
      'display_order': int.tryParse(_orderCtrl.text) ?? 0,
    };
    try {
      if (widget.existingId != null) {
        await widget.repo.updateContentItem(widget.existingId!, data);
      } else {
        await widget.repo.createContentItem(data);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(
                      widget.existingId == null
                          ? 'New Content'
                          : 'Edit Content',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kAdminTextPri))),
              if (_existing != null)
                AdminBadge(_existing!['status'] ?? '',
                    _statusColor(_existing!['status'] ?? '')),
              const SizedBox(width: 8),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: kAdminTextPri)),
            ]),
            const Divider(height: 24),
            SizedBox(
              height: 560,
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(_titleCtrl, _isFaq ? 'Question' : 'Title',
                          maxLines: 1),
                      const SizedBox(height: 12),
                      if (_isArticle) ...[
                        _field(_subtitleCtrl, 'Short description', maxLines: 2),
                        const SizedBox(height: 12),
                      ],
                      if (_hasCta) ...[
                        _field(_subtitleCtrl, 'Message', maxLines: 2),
                        const SizedBox(height: 12),
                      ],
                      _field(_bodyCtrl, _isFaq ? 'Answer' : 'Content / Body',
                          maxLines: 8),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        SizedBox(
                            width: 220,
                            child:
                                _field(_categoryCtrl, 'Category', maxLines: 1)),
                        if (_isFaq)
                          SizedBox(
                              width: 140,
                              child: _field(_orderCtrl, 'Display order',
                                  maxLines: 1,
                                  keyboardType: TextInputType.number)),
                        if (!_isFaq)
                          SizedBox(
                            width: 200,
                            child: DropdownButtonFormField<String>(
                              initialValue: _audience,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Target Audience',
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
                                    value: 'all', child: Text('All Users')),
                                DropdownMenuItem(
                                    value: 'lawyer', child: Text('Lawyers')),
                                DropdownMenuItem(
                                    value: 'client', child: Text('Clients')),
                                DropdownMenuItem(
                                    value: 'student', child: Text('Students')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _audience = v ?? 'all'),
                            ),
                          ),
                      ]),
                      if (_isArticle) ...[
                        const SizedBox(height: 12),
                        _field(_tagsCtrl, 'Tags (comma separated)',
                            maxLines: 1),
                      ],
                      if (_hasCta) ...[
                        const SizedBox(height: 12),
                        _field(_imageCtrl, 'Image URL', maxLines: 1),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _field(_ctaTextCtrl, 'CTA text',
                                  maxLines: 1)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _field(
                                  _ctaActionCtrl, 'CTA destination / action',
                                  maxLines: 1)),
                        ]),
                      ],
                    ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Draft'),
              ),
            ]),
          ]),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
          {int maxLines = 1, TextInputType? keyboardType}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: kAdminBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      );
}

/// Terms & Conditions / Privacy Policy tab — version history plus a new
/// draft editor. Publishing a new version never overwrites or deletes the
/// row for the previous one.
class _LegalDocTab extends StatefulWidget {
  final String docType;
  final AdminRepository repo;
  final VoidCallback onChanged;
  const _LegalDocTab(
      {required this.docType, required this.repo, required this.onChanged});

  @override
  State<_LegalDocTab> createState() => _LegalDocTabState();
}

class _LegalDocTabState extends State<_LegalDocTab> {
  bool _loading = true;
  String? _error;
  List<dynamic> _versions = [];

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
      final res = await widget.repo.legalDocumentVersions(widget.docType);
      if (!mounted) return;
      setState(() {
        _versions = (res['data'] as List?) ?? [];
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

  Future<void> _refreshAll() async {
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.docType == 'terms' ? 'Terms & Conditions' : 'Privacy Policy';
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('$label — Version History',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: kAdminTextPri))),
          FilledButton.icon(
            onPressed: () => _newVersionDialog(),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New Version'),
          ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 460,
          child: _loading
              ? const AdminTableSkeleton(columns: 5)
              : _error != null
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: kAdminRed, size: 30),
                            const SizedBox(height: 10),
                            const Text('Unable to load content',
                                style: TextStyle(
                                    color: kAdminTextMuted, fontSize: 12.5)),
                            const SizedBox(height: 10),
                            TextButton(
                                onPressed: _load, child: const Text('Retry')),
                          ]),
                    )
                  : _versions.isEmpty
                      ? const AdminEmptyState(message: 'No content found')
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor:
                                  WidgetStateProperty.all(kAdminBg),
                              columns: const [
                                DataColumn(label: Text('Version')),
                                DataColumn(label: Text('Created By')),
                                DataColumn(label: Text('Created Date')),
                                DataColumn(label: Text('Published Date')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: _versions.map((v) {
                                final status = v['status'] ?? '';
                                return DataRow(cells: [
                                  DataCell(Text('v${v['version']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700))),
                                  DataCell(Text((v['created_by_name'] ?? '')
                                          .toString()
                                          .isEmpty
                                      ? 'N/A'
                                      : v['created_by_name'])),
                                  DataCell(Text(fmtDate(v['created_at']))),
                                  DataCell(Text(v['published_at'] == null
                                      ? '-'
                                      : fmtDate(v['published_at']))),
                                  DataCell(AdminBadge(
                                      status,
                                      status == 'published'
                                          ? kAdminGreen
                                          : kAdminTextMuted)),
                                  DataCell(Row(children: [
                                    IconButton(
                                        tooltip: 'View / Preview',
                                        icon: const Icon(
                                            Icons.visibility_rounded,
                                            size: 17),
                                        onPressed: () => _viewVersion(v['id']),
                                        visualDensity: VisualDensity.compact),
                                    if (status != 'published')
                                      IconButton(
                                          tooltip: 'Publish this version',
                                          icon: const Icon(
                                              Icons.publish_rounded,
                                              size: 17,
                                              color: kAdminGreen),
                                          onPressed: () =>
                                              _confirmPublish(v['id']),
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

  Future<void> _confirmPublish(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish this version?'),
        content: const Text(
            'This becomes the current version shown to all users. The previous version is kept in history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.publishLegalDocument(id);
      await _refreshAll();
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _viewVersion(String id) async {
    try {
      final res = await widget.repo.legalDocumentVersion(id);
      final d = (res['data'] as Map<String, dynamic>?) ?? {};
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => Theme(
          data: buildAdminTheme(dialogContext),
          child: Dialog(
            backgroundColor: kAdminCard,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('Version ${d['version']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded)),
                      ]),
                      const Divider(height: 20),
                      SizedBox(
                        height: 480,
                        child: SingleChildScrollView(
                          child: Text('${d['content'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 12.5, color: kAdminTextPri)),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      );
    } on AdminException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _newVersionDialog() async {
    final versionCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: buildAdminTheme(dialogContext),
        child: Dialog(
          backgroundColor: kAdminCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New Version (Draft)',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: versionCtrl,
                      decoration: InputDecoration(
                        labelText: 'Version (e.g. 2.0)',
                        filled: true,
                        fillColor: kAdminBg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 380,
                      child: TextField(
                        controller: contentCtrl,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          labelText: 'Content',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: kAdminBg,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (versionCtrl.text.trim().isEmpty ||
                              contentCtrl.text.trim().isEmpty) return;
                          try {
                            await widget.repo.createLegalDocumentDraft(
                                widget.docType,
                                versionCtrl.text.trim(),
                                contentCtrl.text.trim());
                            if (dialogContext.mounted)
                              Navigator.pop(dialogContext, true);
                          } on AdminException catch (e) {
                            if (dialogContext.mounted)
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text(e.message)));
                          }
                        },
                        child: const Text('Save Draft'),
                      ),
                    ]),
                  ]),
            ),
          ),
        ),
      ),
    );
    if (saved == true) _refreshAll();
  }
}
