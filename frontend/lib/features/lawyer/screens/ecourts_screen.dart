import 'package:dio/dio.dart';
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
const _blue = Color(0xFF4A90D9);

class EcourtsScreen extends StatefulWidget {
  const EcourtsScreen({super.key});
  @override
  State<EcourtsScreen> createState() => _EcourtsScreenState();
}

class _EcourtsScreenState extends State<EcourtsScreen> {
  final _cnrCtrl = TextEditingController();
  Map<String, dynamic>? _caseData;
  bool _loading = false;
  String? _error;

  // Recent CNR lookups (local)
  final List<String> _recentCNRs = [];

  @override
  void dispose() {
    _cnrCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchCNR(String cnr) async {
    if (cnr.trim().isEmpty) return;
    final cleanCNR = cnr.trim().toUpperCase();
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _error = null;
      _caseData = null;
    });

    try {
      // The endpoint is /court/case-status?cnr=. This screen previously called
      // '/court/cnr/<cnr>', which no route ever served — every lookup 404'd,
      // was swallowed by the empty `catch (_) {}` below, and silently fell
      // through to the "go visit ecourts.gov.in yourself" placeholder. The
      // feature looked implemented and never once worked.
      final res = await DioClient.instance.get(
        '/court/case-status',
        queryParameters: {'cnr': cleanCNR},
      );
      if (res.data['success'] == true && res.data['data'] != null) {
        final data = res.data['data'] as Map<String, dynamic>;
        setState(() {
          _caseData = {
            'cnr_number': data['cnr'] ?? cleanCNR,
            'case_number': data['case_number'] ?? '-',
            'case_type': data['case_type'] ?? '-',
            'status': data['status'] ?? '-',
            'stage': data['stage'] ?? '-',
            'court': data['court_name'] ?? '-',
            'judge': data['judge_name'] ?? '-',
            'next_hearing': data['next_hearing_date'] ?? '-',
            'filing_date': data['filing_date'] ?? '-',
            'petitioners': data['petitioners'] ?? const [],
            'respondents': data['respondents'] ?? const [],
            'hearing_history': data['hearing_history'] ?? const [],
            'orders': data['orders'] ?? const [],
            'from_cache': data['from_cache'] ?? false,
            'attribution': data['attribution_note'] ?? '',
            'is_fallback': false,
          };
          _loading = false;
          if (!_recentCNRs.contains(cleanCNR)) _recentCNRs.insert(0, cleanCNR);
          if (_recentCNRs.length > 5) _recentCNRs.removeLast();
        });
        return;
      }
    } on DioException catch (e) {
      // 503 means no court-data source is configured yet, which is a normal
      // state for a deployment awaiting NIC approval — fall through to the
      // guidance card. Anything else is a real error and the user should see
      // it rather than a message implying the case simply isn't available.
      final code = e.response?.statusCode;
      if (code != null && code != 503 && code != 404) {
        setState(() {
          _loading = false;
          _error = DioClient.describeError(e);
        });
        return;
      }
      if (code == 404) {
        setState(() {
          _loading = false;
          _error = 'No court record found for CNR $cleanCNR. '
              'Check the number and try again.';
        });
        return;
      }
    } catch (_) {
      // Fall through to the guidance card below.
    }

    // No court-data source configured — tell the user where to look instead.
    setState(() {
      _loading = false;
      _caseData = {
        'cnr_number': cleanCNR,
        'status': 'Available on eCourts Portal',
        'message': 'Live case lookup is not enabled on this account yet. '
            'Check CNR $cleanCNR on ecourts.gov.in or in the eCourts app.',
        'court': 'Check on eCourts Portal',
        'judge': '-',
        'next_hearing': '-',
        'case_type': 'CNR Lookup',
        'is_fallback': true,
      };
      if (!_recentCNRs.contains(cleanCNR)) _recentCNRs.insert(0, cleanCNR);
      if (_recentCNRs.length > 5) _recentCNRs.removeLast();
    });
  }

  // Search from cases in our system by CNR
  Future<void> _searchFromSystem(String cnr) async {
    if (cnr.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await DioClient.instance
          .get('/cases', queryParameters: {'cnr': cnr.trim()});
      final cases = res.data['data'] as List? ?? [];
      if (cases.isNotEmpty) {
        final c = cases.first;
        setState(() {
          _caseData = {
            'cnr_number': cnr.trim(),
            'case_title': c['case_title'] ?? '',
            'case_number': c['case_number'] ?? '',
            'case_type': c['case_type'] ?? '',
            'court': c['court_name'] ?? '',
            'court_location': c['court_location'] ?? '',
            'judge': c['judge_name'] ?? '',
            'status': c['status'] ?? '',
            'client': c['client_name'] ?? '',
            'is_fallback': false,
          };
          _loading = false;
        });
      } else {
        _searchCNR(cnr);
      }
    } catch (e) {
      _searchCNR(cnr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
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
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Column(children: [
                      Text('eCourts Case Status',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Search by CNR Number',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 10)),
                    ])),
                  ]),
                ),

                // CNR Search Box
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(children: [
                    Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14)),
                      child: TextField(
                        controller: _cnrCtrl,
                        style: const TextStyle(color: _textPri, fontSize: 14),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'Enter CNR Number (e.g. MHAU010012342024)',
                          hintStyle:
                              const TextStyle(color: _textMuted, fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: _brown, size: 20),
                          suffixIcon: GestureDetector(
                            onTap: () => _searchFromSystem(_cnrCtrl.text),
                            child: Container(
                              margin: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: _brown,
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                          border: InputBorder.none,
                          filled: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onSubmitted: _searchFromSystem,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        'Format: State Code + District Code + Case Number + Year',
                        style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ]),
                ),
              ])),
        ),

        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                // _error was assigned but never rendered, so a failed lookup
                // just returned the user to the empty search screen with no
                // indication anything had gone wrong.
                : _error != null
                    ? _buildError()
                    : _caseData != null
                        ? _buildResult()
                        : _buildHome()),
      ]),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off_rounded, size: 48, color: _brownDark),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: _textPri, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => setState(() => _error = null),
              child: const Text('Try another CNR',
                  style: TextStyle(color: _brown, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

  Widget _buildHome() => ListView(padding: const EdgeInsets.all(16), children: [
        // Recent CNRs
        if (_recentCNRs.isNotEmpty) ...[
          const Text('Recent Searches',
              style: TextStyle(
                  color: _textPri, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ..._recentCNRs.map((cnr) => GestureDetector(
                onTap: () {
                  _cnrCtrl.text = cnr;
                  _searchFromSystem(cnr);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border, width: 0.8)),
                  child: Row(children: [
                    const Icon(Icons.history_rounded,
                        color: _textMuted, size: 18),
                    const SizedBox(width: 10),
                    Text(cnr,
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: _textMuted, size: 12),
                  ]),
                ),
              )),
          const SizedBox(height: 20),
        ],

        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _blue.withValues(alpha: 0.2))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.info_outline_rounded, color: _blue, size: 18),
              SizedBox(width: 8),
              Text('About CNR Number',
                  style: TextStyle(
                      color: _blue, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            const Text(
                'CNR (Case Number Record) is a unique 16-digit number assigned to every case filed in Indian courts.\n\nFormat: [State Code][District Code][Case No][Year]\nExample: MHAU010012342024',
                style: TextStyle(color: _textPri, fontSize: 12, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 16),

        // State codes reference
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Common State Codes',
                style: TextStyle(
                    color: _textPri,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ['MH', 'Maharashtra'],
                  ['DL', 'Delhi'],
                  ['KA', 'Karnataka'],
                  ['TN', 'Tamil Nadu'],
                  ['GJ', 'Gujarat'],
                  ['RJ', 'Rajasthan'],
                  ['UP', 'Uttar Pradesh'],
                  ['WB', 'West Bengal'],
                  ['MP', 'Madhya Pradesh'],
                ]
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: _brown.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text('${s[0]} - ${s[1]}',
                              style: const TextStyle(
                                  color: _brown,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList()),
          ]),
        ),
        const SizedBox(height: 40),
      ]);

  Widget _buildResult() {
    final d = _caseData!;
    final isFallback = d['is_fallback'] == true;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // CNR badge
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: isFallback
                  ? [_brown.withValues(alpha: 0.8), _brownDark]
                  : [const Color(0xFF2E8B57), const Color(0xFF1A7A40)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.qr_code_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('CNR Number',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text(d['cnr_number'] ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8)),
            child: Text(isFallback ? 'External' : 'Found',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      if (isFallback) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.open_in_new_rounded, color: _blue, size: 18),
              SizedBox(width: 8),
              Text('Check on eCourts Portal',
                  style: TextStyle(
                      color: _blue, fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
            const SizedBox(height: 10),
            Text(d['message'] ?? '',
                style: const TextStyle(
                    color: _textPri, fontSize: 13, height: 1.5)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10)),
              child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🌐 Website: ecourts.gov.in',
                        style: TextStyle(color: _textPri, fontSize: 12)),
                    SizedBox(height: 4),
                    Text('📱 App: eCourts Services (Play Store / App Store)',
                        style: TextStyle(color: _textPri, fontSize: 12)),
                    SizedBox(height: 4),
                    Text('📞 Helpline: 1800-103-0212',
                        style: TextStyle(color: _textPri, fontSize: 12)),
                  ]),
            ),
          ]),
        ),
      ] else ...[
        _InfoCard('Case Details', Icons.gavel_rounded, [
          _InfoRow('Case Title', d['case_title'] ?? '-'),
          _InfoRow('Case Number', d['case_number'] ?? '-'),
          _InfoRow('Case Type', d['case_type'] ?? '-'),
          _InfoRow('Status', d['status'] ?? '-'),
        ]),
        const SizedBox(height: 10),
        _InfoCard('Court Details', Icons.account_balance_rounded, [
          _InfoRow('Court Name', d['court'] ?? '-'),
          _InfoRow('Location', d['court_location'] ?? '-'),
          _InfoRow('Judge', d['judge'] ?? '-'),
          _InfoRow('Next Hearing', d['next_hearing'] ?? '-'),
        ]),
        if ((d['client'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _InfoCard('Client', Icons.person_rounded, [
            _InfoRow('Client Name', d['client'] ?? '-'),
          ]),
        ],
      ],

      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _caseData = null;
          _cnrCtrl.clear();
        }),
        icon: const Icon(Icons.search_rounded, color: _brown),
        label: const Text('Search Another CNR',
            style: TextStyle(color: _brown, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12)),
      ),
      const SizedBox(height: 40),
    ]);
  }

  Widget _InfoCard(String title, IconData icon, List<Widget> rows) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: _brown, borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, color: Colors.white, size: 14)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: _textPri,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
          const Divider(color: Color(0xFFE6E3F4), height: 16, thickness: 0.6),
          ...rows,
        ]),
      );

  Widget _InfoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPri,
                      fontWeight: FontWeight.w600,
                      fontSize: 13))),
        ]),
      );
}
