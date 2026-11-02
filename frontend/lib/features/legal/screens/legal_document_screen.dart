import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFF0A0A14);
const _gold = Color(0xFFD4A017);

/// Renders a published legal document (Terms of Service / Privacy Policy)
/// fetched live from the backend's admin-editable content — previously the
/// registration screens linked these by name only, with no tap handler and
/// nowhere in the app that actually displayed the admin-published text.
class LegalDocumentScreen extends StatefulWidget {
  /// 'terms' or 'privacy' — matches the backend's doc_type values exactly
  /// (GetCurrentLegalDocument rejects anything else with a 400).
  final String docType;
  const LegalDocumentScreen({super.key, required this.docType});

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  bool _loading = true;
  String? _error;
  String _title = '';
  String _content = '';
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _label =>
      widget.docType == 'privacy' ? 'Privacy Policy' : 'Terms of Service';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res =
          await DioClient.instance.get('/content/legal/${widget.docType}/current');
      final data = res.data['data'] ?? {};
      setState(() {
        _title = _label;
        _content = (data['content'] ?? '').toString();
        _version = (data['version'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        // A firm that hasn't published one yet (or a transient failure)
        // shouldn't look like a crash — just say so plainly.
        _error = DioClient.describeError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        title: Text(_label,
            style:
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _gold))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.white38, size: 40),
                            const SizedBox(height: 12),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14)),
                            const SizedBox(height: 16),
                            OutlinedButton(
                                onPressed: _load,
                                child: const Text('Retry')),
                          ]),
                    ),
                  )
                : _content.trim().isEmpty
                    ? const Center(
                        child: Text('This document has not been published yet.',
                            style: TextStyle(color: Colors.white60)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700)),
                              if (_version.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Version $_version',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12)),
                              ],
                              const SizedBox(height: 16),
                              Text(_content,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      height: 1.5)),
                              const SizedBox(height: 40),
                            ]),
                      ),
      ),
    );
  }
}
