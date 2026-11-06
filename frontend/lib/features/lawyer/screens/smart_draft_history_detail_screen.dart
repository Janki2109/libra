import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

const _bg = AppColors.bg;
const _bgCard = AppColors.bgCard;
const _gold = AppColors.gold;
const _border = AppColors.border;
const _textPri = AppColors.textPrimary;
const _textMuted = AppColors.textSecondary;
const _error = AppColors.error;
const _success = Color(0xFF2E8B57);

/// Opens one saved Smart Draft history item -- fetched fresh from
/// GET /ai/history/:id, which is ownership-checked server-side against the
/// authenticated Lawyer's own user_id, never a locally-cached copy. "Continue
/// Editing" saves a NEW version via PUT (never overwrites in place), so an
/// earlier version always stays reachable through the version list below.
class SmartDraftHistoryDetailScreen extends StatefulWidget {
  final String itemId;
  const SmartDraftHistoryDetailScreen({super.key, required this.itemId});
  @override
  State<SmartDraftHistoryDetailScreen> createState() =>
      _SmartDraftHistoryDetailScreenState();
}

class _SmartDraftHistoryDetailScreenState
    extends State<SmartDraftHistoryDetailScreen> {
  Map<String, dynamic>? _item;
  List<dynamic> _versions = [];
  bool _loading = true;
  String? _error_;
  bool _editing = false;
  bool _saving = false;
  final _editCtrl = TextEditingController();
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error_ = null;
    });
    try {
      final res =
          await DioClient.instance.get('/ai/history/${widget.itemId}');
      final versionsRes = await DioClient.instance
          .get('/ai/history/${widget.itemId}/versions');
      setState(() {
        _item = res.data['data'];
        _versions = versionsRes.data['data'] ?? [];
        _editCtrl.text = (_item?['output_text'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error_ = DioClient.describeError(e);
      });
    }
  }

  Future<void> _openVersion(String versionId) async {
    if (versionId == widget.itemId) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) =>
              SmartDraftHistoryDetailScreen(itemId: versionId)),
    );
  }

  Future<void> _saveNewVersion() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await DioClient.instance
          .put('/ai/history/${widget.itemId}', data: {
        'output_text': _editCtrl.text,
      });
      final newId = res.data['data']?['id'];
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved as a new version'),
            backgroundColor: _success,
            behavior: SnackBarBehavior.floating));
        _changed = true;
        if (newId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    SmartDraftHistoryDetailScreen(itemId: newId as String)),
          );
          return;
        }
      }
      setState(() {
        _editing = false;
        _saving = false;
      });
      _load();
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save: ${DioClient.describeError(e)}'),
            backgroundColor: _error,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.pop(_changed);
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: AppColors.primaryDark,
          title: Text(_item?['title'] ?? 'Smart Draft History',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => context.pop(_changed)),
          actions: [
            if (_item != null && !_loading)
              IconButton(
                tooltip: _editing ? 'Cancel editing' : 'Continue Editing',
                icon: Icon(_editing ? Icons.close_rounded : Icons.edit_rounded,
                    color: Colors.white),
                onPressed: () => setState(() {
                  if (_editing) _editCtrl.text = (_item?['output_text'] ?? '').toString();
                  _editing = !_editing;
                }),
              ),
          ],
        ),
        floatingActionButton: _editing
            ? FloatingActionButton.extended(
                onPressed: _saving ? null : _saveNewVersion,
                backgroundColor: _gold,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, color: Colors.white),
                label: Text(_saving ? 'Saving...' : 'Save New Version',
                    style: const TextStyle(color: Colors.white)),
              )
            : null,
        body: _loading
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
                : _item == null
                    ? const Center(
                        child: Text('Not found',
                            style: TextStyle(color: _textMuted)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_versions.length > 1) ...[
                                const Text('Versions',
                                    style: TextStyle(
                                        color: _textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 36,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _versions.length,
                                    itemBuilder: (_, i) {
                                      final v = _versions[i];
                                      final isCurrent =
                                          v['id'] == widget.itemId;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                          label: Text('v${v['version']}',
                                              style: TextStyle(
                                                  color: isCurrent
                                                      ? Colors.white
                                                      : _textPri,
                                                  fontSize: 12)),
                                          selected: isCurrent,
                                          selectedColor: _gold,
                                          backgroundColor: _bgCard,
                                          onSelected: (_) =>
                                              _openVersion(v['id']),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if ((_item?['input_text'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                Text(
                                    _item!['activity_type'] == 'tool' ||
                                            _item!['activity_type'] ==
                                                'file_analysis'
                                        ? 'Input'
                                        : 'Prompt',
                                    style: const TextStyle(
                                        color: _textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: _bgCard,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _border)),
                                  child: Text(
                                      (_item!['input_text'] ?? '').toString(),
                                      style: const TextStyle(
                                          color: _textMuted, fontSize: 12.5)),
                                ),
                                const SizedBox(height: 16),
                              ],
                              const Text('Result',
                                  style: TextStyle(
                                      color: _textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              _editing
                                  ? TextField(
                                      controller: _editCtrl,
                                      maxLines: null,
                                      minLines: 12,
                                      style: const TextStyle(
                                          color: _textPri, fontSize: 13.5),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: _bgCard,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide:
                                                const BorderSide(color: _border)),
                                      ),
                                    )
                                  : Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          color: _bgCard,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border:
                                              Border.all(color: _border)),
                                      child: SelectableText(
                                          (_item!['output_text'] ?? '')
                                              .toString(),
                                          style: const TextStyle(
                                              color: _textPri, fontSize: 13.5)),
                                    ),
                              const SizedBox(height: 80),
                            ]),
                      ),
      ),
    );
  }
}
