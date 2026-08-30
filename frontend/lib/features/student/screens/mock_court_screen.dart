import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF0F4FF);
const _bgCard = Color(0xFFFFFFFF);
const _navy = Color(0xFF0A1628);
const _blue = Color(0xFF1565C0);
const _border = Color(0xFFBBDEFB);
const _textPri = Color(0xFF0A1628);
const _textMuted = Color(0xFF546E7A);
const _gold = Color(0xFFFFD700);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);

class MockCourtScreen extends StatefulWidget {
  const MockCourtScreen({super.key});
  @override
  State<MockCourtScreen> createState() => _MockCourtScreenState();
}

class _MockCourtScreenState extends State<MockCourtScreen> {
  int _step = 0; // 0=select, 1=case, 2=argue, 3=result
  String? _selectedType;
  Map<String, dynamic>? _caseData;
  final _argumentCtrl = TextEditingController();
  final _submissionCtrl = TextEditingController();
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error; // clean, user-friendly message only — never a raw exception
  String _role = 'Prosecution'; // Prosecution or Defence

  final List<Map<String, dynamic>> _caseTypes = [
    {
      'name': 'Criminal Case',
      'icon': '🔍',
      'color': _red,
      'desc': 'Murder, theft, assault cases'
    },
    {
      'name': 'Civil Dispute',
      'icon': '⚖️',
      'color': _blue,
      'desc': 'Property, contract disputes'
    },
    {
      'name': 'Family Matter',
      'icon': '👨‍👩‍👧',
      'color': Color(0xFFD4A017),
      'desc': 'Divorce, custody, maintenance'
    },
    {
      'name': 'Consumer Case',
      'icon': '🛒',
      'color': Color(0xFF2E8B57),
      'desc': 'Consumer forum complaints'
    },
    {
      'name': 'Constitutional',
      'icon': '📜',
      'color': Color(0xFF7C3AED),
      'desc': 'Fundamental rights violations'
    },
  ];

  // The Groq key(s) and rotation live on the backend only (services/
  // groq_service.go) — this screen never talks to Groq directly. A single
  // call here already means the backend tried every configured key in order
  // before either succeeding or giving up, so no client-side retry loop is
  // needed — one failure here already means all keys failed.
  Future<void> _generateCase() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await DioClient.instance
          .post('/ai/mock-court/case', data: {'case_type': _selectedType});
      String raw = response.data['data']?['content'] ?? '{}';
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start >= 0 && end >= 0) raw = raw.substring(start, end + 1);
      setState(() {
        _caseData = jsonDecode(raw);
        _loading = false;
        _step = 1;
      });
    } catch (e) {
      // Never surface a raw DioException/HTTP status to the student — the
      // backend already tried every configured Groq key before giving up.
      // Selection (case type + role) is untouched, so pressing Retry just
      // re-runs the same request.
      setState(() {
        _loading = false;
        _error = 'AI service is temporarily unavailable. Please try again.';
      });
    }
  }

  Future<void> _submitArguments() async {
    if (_argumentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please write your arguments!'),
          backgroundColor: _red));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    HapticFeedback.lightImpact();
    try {
      final response = await DioClient.instance.post('/ai/mock-court/evaluate', data: {
        'case_title': _caseData?['title'] ?? '',
        'case_facts': _caseData?['facts'] ?? '',
        'issues': (_caseData?['issues'] as List?)?.join(', ') ?? '',
        'role': _role,
        'arguments': _argumentCtrl.text,
        'submission': _submissionCtrl.text,
      });
      String raw = response.data['data']?['content'] ?? '{}';
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start >= 0 && end >= 0) raw = raw.substring(start, end + 1);
      setState(() {
        _result = jsonDecode(raw);
        _loading = false;
        _step = 3;
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      // Arguments/submission text is untouched (controllers aren't cleared),
      // so the student's work is preserved and Retry just resends it.
      setState(() {
        _loading = false;
        _error = 'AI service is temporarily unavailable. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _argumentCtrl.dispose();
    _submissionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0A1628), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () {
                        if (_step > 0)
                          setState(() {
                            _step = _step == 3 ? 0 : _step - 1;
                            _result = null;
                            _caseData = null;
                          });
                        else
                          context.pop();
                      }),
                  const Expanded(
                      child: Column(children: [
                    Text('Mock Court',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text('Practice your arguments',
                        style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ])),
                  // Step indicator
                  Row(
                      children: List.generate(
                          3,
                          (i) => Container(
                                margin: const EdgeInsets.only(left: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _step > i
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.3),
                                ),
                              ))),
                ]),
              )),
        ),
        Expanded(
            child: _loading
                ? _buildLoading()
                : _error != null
                    ? _buildError()
                    : _step == 0
                        ? _buildSelectType()
                        : _step == 1
                            ? _buildCase()
                            : _step == 2
                                ? _buildArgue()
                                : _buildResult()),
      ]),
    );
  }

  Widget _buildError() => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.cloud_off_rounded, color: _red, size: 32),
          ),
          const SizedBox(height: 16),
          Text(_error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _textPri, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _step == 2 ? _submitArguments : _generateCase,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ));

  Widget _buildLoading() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🏛️', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        const CircularProgressIndicator(color: _blue),
        const SizedBox(height: 16),
        Text(_step == 0 ? 'Generating Case...' : 'Judge is evaluating...',
            style: const TextStyle(
                color: _textPri, fontSize: 15, fontWeight: FontWeight.w600)),
      ]));

  Widget _buildSelectType() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0A1628), Color(0xFF1565C0)]),
                borderRadius: BorderRadius.circular(16)),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🏛️ Welcome to Mock Court',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text(
                      '• AI generates a real case\n• You argue as Prosecution or Defence\n• AI Judge scores your performance\n• Earn XP for good arguments!',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.5)),
                ])),
        const SizedBox(height: 20),
        const Text('Select Case Type',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ..._caseTypes.map((t) {
          final sel = _selectedType == t['name'];
          final color = t['color'] as Color;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedType = t['name']);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: sel ? color.withValues(alpha: 0.08) : _bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: sel ? color : _border, width: sel ? 2 : 0.8)),
              child: Row(children: [
                Text(t['icon'], style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(t['name'],
                          style: TextStyle(
                              color: sel ? color : _textPri,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      Text(t['desc'],
                          style:
                              const TextStyle(color: _textMuted, fontSize: 12)),
                    ])),
                if (sel)
                  Icon(Icons.check_circle_rounded, color: color, size: 22),
              ]),
            ),
          );
        }),
        const SizedBox(height: 20),
        // Role selection
        const Text('Your Role',
            style: TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: GestureDetector(
            onTap: () => setState(() => _role = 'Prosecution'),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _role == 'Prosecution'
                        ? _red.withValues(alpha: 0.08)
                        : _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _role == 'Prosecution' ? _red : _border,
                        width: _role == 'Prosecution' ? 2 : 0.8)),
                child: Column(children: [
                  const Text('⚔️', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 6),
                  const Text('Prosecution',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const Text('Argue against defendant',
                      style: TextStyle(color: _textMuted, fontSize: 10),
                      textAlign: TextAlign.center),
                ])),
          )),
          const SizedBox(width: 10),
          Expanded(
              child: GestureDetector(
            onTap: () => setState(() => _role = 'Defence'),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color:
                        _role == 'Defence' ? _blue.withValues(alpha: 0.08) : _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _role == 'Defence' ? _blue : _border,
                        width: _role == 'Defence' ? 2 : 0.8)),
                child: Column(children: [
                  const Text('🛡️', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 6),
                  const Text('Defence',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const Text('Defend the accused',
                      style: TextStyle(color: _textMuted, fontSize: 10),
                      textAlign: TextAlign.center),
                ])),
          )),
        ]),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _selectedType != null ? _generateCase : null,
            icon: const Icon(Icons.gavel_rounded, color: Colors.white),
            label: const Text('Start Mock Court',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ),
        const SizedBox(height: 40),
      ]);

  Widget _buildCase() {
    final c = _caseData!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border, width: 0.8)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🏛️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(c['title'] ?? '',
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    Text(c['court'] ?? '',
                        style:
                            const TextStyle(color: _textMuted, fontSize: 12)),
                  ])),
            ]),
            const SizedBox(height: 14),
            // Parties
            if (c['parties'] != null) ...[
              Row(children: [
                _PartyChip(
                    '⚔️ ${(c['parties'] as Map)['plaintiff'] ?? 'Plaintiff'}',
                    _red),
                const SizedBox(width: 8),
                const Text('vs',
                    style: TextStyle(
                        color: _textMuted, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _PartyChip(
                    '🛡️ ${(c['parties'] as Map)['defendant'] ?? 'Defendant'}',
                    _blue),
              ]),
              const SizedBox(height: 14),
            ],
            // Your role
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: (_role == 'Prosecution' ? _red : _blue)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: (_role == 'Prosecution' ? _red : _blue)
                            .withValues(alpha: 0.3))),
                child: Row(children: [
                  Text(_role == 'Prosecution' ? '⚔️' : '🛡️',
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('You are arguing for: $_role',
                      style: TextStyle(
                          color: _role == 'Prosecution' ? _red : _blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ])),
          ])),
      const SizedBox(height: 14),
      _Section('📋 Facts of the Case', c['facts'] ?? '', _blue),
      const SizedBox(height: 10),
      _Section('⚖️ Legal Issues', (c['issues'] as List?)?.join('\n• ') ?? '',
          _textPri,
          prefix: '• '),
      const SizedBox(height: 10),
      _Section(
          '📖 Applicable Laws',
          (c['applicable_laws'] as List?)?.join('\n• ') ?? '',
          Color(0xFF7C3AED),
          prefix: '• '),
      const SizedBox(height: 10),
      _Section(
          '💡 Hints for $_role',
          _role == 'Prosecution'
              ? (c['prosecution_hints'] ?? '')
              : (c['defence_hints'] ?? ''),
          _gold),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () => setState(() => _step = 2),
          icon: const Icon(Icons.mic_rounded, color: Colors.white),
          label: const Text('Prepare Arguments',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
        ),
      ),
      const SizedBox(height: 40),
    ]);
  }

  Widget _buildArgue() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color:
                    (_role == 'Prosecution' ? _red : _blue).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: (_role == 'Prosecution' ? _red : _blue)
                        .withValues(alpha: 0.2))),
            child: Text(
                'You are arguing as: $_role\nCase: ${_caseData?['title']}',
                style: const TextStyle(
                    color: _textPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        const Text('Your Oral Arguments *',
            style: TextStyle(
                color: _textPri, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Present your main arguments, cite relevant laws and cases',
            style: TextStyle(color: _textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
            controller: _argumentCtrl,
            maxLines: 8,
            style: const TextStyle(color: _textPri, fontSize: 14),
            decoration: InputDecoration(
                hintText:
                    'My Lord, the facts clearly show that...\n\nI rely on Section X of Act Y...\n\nIn the case of A vs B (Year), it was held that...',
                hintStyle: const TextStyle(color: _textMuted, fontSize: 12),
                filled: true,
                fillColor: _bgCard,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border, width: 0.8)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue, width: 1.5)))),
        const SizedBox(height: 16),
        const Text('Written Submission (Optional)',
            style: TextStyle(
                color: _textPri, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
            controller: _submissionCtrl,
            maxLines: 4,
            style: const TextStyle(color: _textPri, fontSize: 14),
            decoration: InputDecoration(
                hintText: 'Summary of arguments in written form...',
                hintStyle: const TextStyle(color: _textMuted, fontSize: 12),
                filled: true,
                fillColor: _bgCard,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border, width: 0.8)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue, width: 1.5)))),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _submitArguments,
            icon: const Icon(Icons.gavel_rounded, color: Colors.white),
            label: const Text('Submit to Judge',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ),
        const SizedBox(height: 40),
      ]);

  Widget _buildResult() {
    final r = _result!;
    final score = (r['score'] as num?)?.toInt() ?? 0;
    final grade = r['grade'] ?? 'B';
    final won = r['result'] == 'won';
    final partial = r['result'] == 'partial';
    final color = won
        ? _green
        : partial
            ? _gold
            : _red;
    final xp = (r['xp_earned'] as num?)?.toInt() ?? 100;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Score banner
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.8), color]),
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(grade,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                      Text('$score%',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ])),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      won
                          ? '⚖️ Case Won!'
                          : partial
                              ? '⚖️ Partial Victory'
                              : '⚖️ Case Lost',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text(r['verdict'] ?? '',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('+$xp XP Earned! 🏆',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ])),
          ])),
      const SizedBox(height: 16),

      // Judge remarks
      _Section('👨‍⚖️ Judge\'s Remarks', r['judge_remarks'] ?? '', _navy),
      const SizedBox(height: 10),
      if ((r['strengths'] as List?)?.isNotEmpty == true)
        _Section('✅ Strengths', (r['strengths'] as List).join('\n• '), _green,
            prefix: '• '),
      const SizedBox(height: 10),
      if ((r['weaknesses'] as List?)?.isNotEmpty == true)
        _Section(
            '❌ Areas to Improve', (r['weaknesses'] as List).join('\n• '), _red,
            prefix: '• '),
      const SizedBox(height: 10),
      if ((r['missed_points'] as List?)?.isNotEmpty == true)
        _Section('💡 Arguments You Missed',
            (r['missed_points'] as List).join('\n• '), _gold,
            prefix: '• '),
      const SizedBox(height: 20),

      Row(children: [
        Expanded(
            child: OutlinedButton(
          onPressed: () => setState(() {
            _step = 0;
            _caseData = null;
            _result = null;
            _argumentCtrl.clear();
            _submissionCtrl.clear();
          }),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('New Case',
              style: TextStyle(color: _blue, fontWeight: FontWeight.w700)),
        )),
        const SizedBox(width: 12),
        Expanded(
            child: ElevatedButton(
          onPressed: () => setState(() {
            _step = 2;
            _result = null;
            _argumentCtrl.clear();
            _submissionCtrl.clear();
          }),
          style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('Try Again',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        )),
      ]),
      const SizedBox(height: 40),
    ]);
  }

  Widget _PartyChip(String name, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Text(name,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _Section(String title, String content, Color color,
          {String prefix = ''}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border, width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Text(prefix.isNotEmpty ? '$prefix$content' : content,
              style:
                  const TextStyle(color: _textPri, fontSize: 13, height: 1.5)),
        ]),
      );
}
