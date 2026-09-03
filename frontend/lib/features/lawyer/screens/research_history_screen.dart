import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);

/// Lists the lawyer's own past AI Legal Research queries (server-persisted
/// via /ai/research/history — see ai_controller.go's LegalResearch), with
/// search and newest/oldest sort. Tapping an entry opens the full saved
/// result via ResearchHistoryDetailScreen.
class ResearchHistoryScreen extends StatefulWidget {
  const ResearchHistoryScreen({super.key});
  @override
  State<ResearchHistoryScreen> createState() => _ResearchHistoryScreenState();
}

class _ResearchHistoryScreenState extends State<ResearchHistoryScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;
  String _sort = 'newest';
  final _searchCtrl = TextEditingController();

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
      _error = null;
    });
    try {
      final res = await DioClient.instance.get('/ai/research/history',
          queryParameters: {
            'q': _searchCtrl.text.trim(),
            'sort': _sort,
            'limit': 50,
          });
      setState(() {
        _items = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

  Future<void> _delete(String id) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this research?',
            style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: const Text(
            'This will permanently remove this query and its result from your history.',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFD9534F)))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DioClient.instance.delete('/ai/research/history/$id');
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e['id'] == id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Deleted'),
          backgroundColor: Color(0xFF2E8B57),
          behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete: ${DioClient.describeError(e)}'),
          backgroundColor: const Color(0xFFD9534F),
          behavior: SnackBarBehavior.floating));
    }
  }

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
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Text('Research History',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.sort_rounded, color: Colors.white),
                      onSelected: (v) {
                        setState(() => _sort = v);
                        _load();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'newest', child: Text('Newest first')),
                        PopupMenuItem(value: 'oldest', child: Text('Oldest first')),
                      ],
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14)),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: _textPri, fontSize: 14),
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search your research history...',
                        hintStyle: TextStyle(color: _textMuted, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: _brown, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                ),
              ])),
        ),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _brown));
    }
    if (_error != null) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded, color: _textMuted, size: 40),
        const SizedBox(height: 12),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry')),
      ]));
    }
    if (_items.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history_rounded,
            color: _brown.withValues(alpha: 0.3), size: 48),
        const SizedBox(height: 12),
        const Text('No research history yet',
            style: TextStyle(
                color: _textPri, fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        const Text('Your past AI Legal Research queries will appear here.',
            style: TextStyle(color: _textMuted, fontSize: 12)),
      ]));
    }
    return RefreshIndicator(
      color: _brown,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          final date = (item['created_at'] ?? '').toString();
          final shortDate = date.length >= 10 ? date.substring(0, 10) : date;
          return Dismissible(
            key: ValueKey(item['id']),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              await _delete(item['id']);
              return false; // _delete already updates state on success
            },
            background: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                  color: const Color(0xFFD9534F),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/lawyer/ai-research/history/${item['id']}'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border, width: 0.8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(item['query'] ?? '',
                            style: const TextStyle(
                                color: _textPri,
                                fontWeight: FontWeight.w700,
                                fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded,
                        color: _textMuted.withValues(alpha: 0.6), size: 18),
                  ]),
                  const SizedBox(height: 6),
                  Text(item['preview'] ?? '',
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.schedule_rounded, color: _textMuted, size: 12),
                    const SizedBox(width: 4),
                    Text(shortDate,
                        style: const TextStyle(color: _textMuted, fontSize: 11)),
                  ]),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full saved result for one past research query.
class ResearchHistoryDetailScreen extends StatefulWidget {
  final String id;
  const ResearchHistoryDetailScreen({super.key, required this.id});
  @override
  State<ResearchHistoryDetailScreen> createState() =>
      _ResearchHistoryDetailScreenState();
}

class _ResearchHistoryDetailScreenState
    extends State<ResearchHistoryDetailScreen> {
  Map<String, dynamic>? _item;
  bool _loading = true;
  String? _error;

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
      final res =
          await DioClient.instance.get('/ai/research/history/${widget.id}');
      setState(() {
        _item = res.data['data'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

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
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => context.pop()),
                  const Expanded(
                      child: Text('Research Result',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700))),
                  const SizedBox(width: 48),
                ]),
              )),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _brown))
              : _item == null
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: _textMuted, size: 40),
                            const SizedBox(height: 12),
                            Text(_error ?? 'Research entry not found',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 13)),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 16),
                                  label: const Text('Retry')),
                            ],
                          ]))
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border, width: 0.8)),
                        child:
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('QUERY',
                              style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          Text(_item!['query'] ?? '',
                              style: const TextStyle(
                                  color: _textPri,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border, width: 0.8)),
                        child: SelectableText(_item!['response'] ?? '',
                            style: const TextStyle(
                                color: _textPri, fontSize: 13, height: 1.6)),
                      ),
                      const SizedBox(height: 40),
                    ]),
        ),
      ]),
    );
  }
}
