import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';
import '../utils/android_download.dart';

const _bg = AppColors.bg;
const _bgCard = AppColors.bgCard;
const _gold = AppColors.gold;
const _goldLight = AppColors.goldLight;
const _border = AppColors.border;
const _textPri = AppColors.textPrimary;
const _textMuted = AppColors.textSecondary;
const _error = AppColors.error;
const _success = Color(0xFF2E8B57);

/// Every entry here is a real, persisted row the authenticated Lawyer's own
/// Smart Draft activity actually wrote via /ai/history -- there is no
/// local/frontend-only history list; everything shown is loaded fresh from
/// the backend, scoped server-side to the caller's own user_id.
class SmartDraftHistoryScreen extends StatefulWidget {
  const SmartDraftHistoryScreen({super.key});
  @override
  State<SmartDraftHistoryScreen> createState() =>
      _SmartDraftHistoryScreenState();
}

class _SmartDraftHistoryScreenState extends State<SmartDraftHistoryScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error_;
  String _typeFilter = ''; // '' = All
  final _searchCtrl = TextEditingController();
  DateTime? _from;
  DateTime? _to;

  static const _typeFilters = [
    {'key': '', 'label': 'All'},
    {'key': 'draft', 'label': 'Drafts'},
    {'key': 'tool', 'label': 'Tools'},
    {'key': 'file_analysis', 'label': 'File Analysis'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error_ = null;
    });
    try {
      final res = await DioClient.instance.get('/ai/history', queryParameters: {
        if (_typeFilter.isNotEmpty) 'type': _typeFilter,
        if (_searchCtrl.text.trim().isNotEmpty) 'q': _searchCtrl.text.trim(),
        if (_from != null) 'from': _fmtDate(_from!),
        if (_to != null) 'to': _fmtDate(_to!),
      });
      setState(() {
        _items = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error_ = DioClient.describeError(e);
      });
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      _load();
    }
  }

  void _clearDateRange() {
    setState(() {
      _from = null;
      _to = null;
    });
    _load();
  }

  Future<void> _openItem(dynamic item) async {
    final result = await context
        .push('/smart-draft/history/${item['id']}') as bool?;
    if (result == true) _load();
  }

  Future<void> _rename(dynamic item) async {
    final ctrl = TextEditingController(text: (item['title'] ?? '').toString());
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename',
            style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: _textPri),
          decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    try {
      await DioClient.instance
          .patch('/ai/history/${item['id']}/rename', data: {'title': newTitle});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: _error,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _delete(dynamic item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this history item?',
            style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: Text(
            'This removes "${item['title']}" and all its saved versions. This cannot be undone.',
            style: const TextStyle(color: _textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DioClient.instance.delete('/ai/history/${item['id']}');
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: _error,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _download(dynamic item, String format) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _gold)),
    );
    try {
      // Full content isn't in the list response (truncated for the list
      // view) -- fetch the full item first so the exported file isn't
      // silently cut off.
      final detail = await DioClient.instance.get('/ai/history/${item['id']}');
      final full = detail.data['data'];
      final title = (full['title'] ?? 'Document').toString();
      final content = (full['output_text'] ?? '').toString();

      final endpoint = format == 'docx' ? '/ai/export-docx' : '/ai/export-pdf';
      final mimeType = format == 'docx'
          ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          : 'application/pdf';
      final res = await DioClient.instance
          .post(endpoint, data: {'title': title, 'content': content});
      final data = res.data['data'];
      final b64 = (data?['file_base64'] ?? '').toString();
      final fileName = (data?['file_name'] ?? 'document').toString();
      if (mounted) Navigator.pop(context);
      if (b64.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nothing to download yet'),
              backgroundColor: _error,
              behavior: SnackBarBehavior.floating));
        }
        return;
      }
      final bytes = base64Decode(b64);
      if (await saveToAndroidDownloads(bytes, fileName, mimeType)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('$fileName saved to Downloads'),
              backgroundColor: _success,
              behavior: SnackBarBehavior.floating));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Download failed: ${DioClient.describeError(e)}'),
            backgroundColor: _error,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'draft':
        return 'Draft';
      case 'tool':
        return 'AI Tool';
      case 'file_analysis':
        return 'File Analysis';
      case 'research':
        return 'Research';
      default:
        return t;
    }
  }

  IconData _typeIcon(String t) {
    switch (t) {
      case 'draft':
        return Icons.edit_document;
      case 'tool':
        return Icons.auto_awesome_rounded;
      case 'file_analysis':
        return Icons.image_search_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Smart Draft History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        actions: [
          IconButton(
            tooltip: _from != null ? 'Clear date range' : 'Filter by date',
            icon: Icon(
                _from != null
                    ? Icons.event_busy_rounded
                    : Icons.date_range_rounded,
                color: Colors.white),
            onPressed: _from != null ? _clearDateRange : _pickDateRange,
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: _textPri),
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search by title or content...',
              prefixIcon: const Icon(Icons.search_rounded, color: _textMuted),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, color: _gold),
                  onPressed: _load),
              filled: true,
              fillColor: _bgCard,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border)),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _typeFilters.map((f) {
              final selected = _typeFilter == f['key'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f['label']!,
                      style: TextStyle(
                          color: selected ? Colors.white : _textPri,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  selected: selected,
                  selectedColor: _gold,
                  backgroundColor: _bgCard,
                  onSelected: (_) {
                    setState(() => _typeFilter = f['key']!);
                    _load();
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _gold))
              : _error_ != null
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          const Icon(Icons.wifi_off_rounded,
                              color: _textMuted, size: 40),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(_error_!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _textMuted)),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry')),
                        ]))
                  : _items.isEmpty
                      ? const Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                              Icon(Icons.history_rounded,
                                  color: _textMuted, size: 48),
                              SizedBox(height: 12),
                              Text('No history yet',
                                  style: TextStyle(color: _textMuted)),
                              SizedBox(height: 4),
                              Text(
                                  'Every research, file analysis and draft you\ngenerate will be saved here automatically.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: _textMuted, fontSize: 12)),
                            ]))
                      : RefreshIndicator(
                          color: _gold,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final item = _items[i];
                              final type =
                                  (item['activity_type'] ?? '').toString();
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                    color: _bgCard,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: _border)),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _openItem(item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                    color: _gold.withValues(
                                                        alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10)),
                                                child: Icon(_typeIcon(type),
                                                    color: _goldLight, size: 18)),
                                            const SizedBox(width: 10),
                                            Expanded(
                                                child: Text(
                                                    (item['title'] ?? '')
                                                        .toString(),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: _textPri,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 14))),
                                            PopupMenuButton<String>(
                                              icon: const Icon(
                                                  Icons.more_vert_rounded,
                                                  color: _textMuted, size: 18),
                                              onSelected: (v) {
                                                HapticFeedback.lightImpact();
                                                switch (v) {
                                                  case 'open':
                                                    _openItem(item);
                                                    break;
                                                  case 'rename':
                                                    _rename(item);
                                                    break;
                                                  case 'docx':
                                                    _download(item, 'docx');
                                                    break;
                                                  case 'pdf':
                                                    _download(item, 'pdf');
                                                    break;
                                                  case 'delete':
                                                    _delete(item);
                                                    break;
                                                }
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                    value: 'open',
                                                    child: Text(
                                                        'Open / Continue Editing')),
                                                PopupMenuItem(
                                                    value: 'rename',
                                                    child: Text('Rename')),
                                                PopupMenuItem(
                                                    value: 'docx',
                                                    child: Text(
                                                        'Download Word (.docx)')),
                                                PopupMenuItem(
                                                    value: 'pdf',
                                                    child: Text(
                                                        'Download PDF')),
                                                PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('Delete',
                                                        style: TextStyle(
                                                            color: _error))),
                                              ],
                                            ),
                                          ]),
                                          const SizedBox(height: 8),
                                          Row(children: [
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                  color: _gold.withValues(
                                                      alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(6)),
                                              child: Text(_typeLabel(type),
                                                  style: const TextStyle(
                                                      color: _goldLight,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                            if ((item['case_title'] ?? '')
                                                .toString()
                                                .isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Expanded(
                                                  child: Text(
                                                      '• ${item['case_title']}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: const TextStyle(
                                                          color: _textMuted,
                                                          fontSize: 11))),
                                            ],
                                          ]),
                                          const SizedBox(height: 6),
                                          Text(
                                              'Updated ${_shortDate(item['updated_at'])}'
                                              '${(item['version'] ?? 1) > 1 ? ' • v${item['version']}' : ''}',
                                              style: const TextStyle(
                                                  color: _textMuted,
                                                  fontSize: 10.5)),
                                        ]),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }

  String _shortDate(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}
