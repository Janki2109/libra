import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

// ── Professional Legal Blue Theme ───────────────────
const _bg = Color(0xFFF6F9FF);
const _bgCard = Color(0xFFFFFFFF);
const _navy = Color(0xFF0B1E3D);
const _pink = Color(0xFF1D4ED8); // primary accent (kept name to avoid touching every call site)
const _blueLight = Color(0xFFEAF2FF);
const _gold = Color(0xFFC9A227);
const _border = Color(0xFFDCE6F7);
const _textPri = Color(0xFF16213E);
const _textMuted = Color(0xFF64748B);

class LegalChallengeScreen extends StatefulWidget {
  const LegalChallengeScreen({super.key});
  @override
  State<LegalChallengeScreen> createState() => _LegalChallengeScreenState();
}

class _LegalChallengeScreenState extends State<LegalChallengeScreen>
    with TickerProviderStateMixin {
  int _step = 0;
  String? _selectedCategory;
  Map<String, dynamic>? _challenge;
  Map<String, dynamic>? _result;
  Map<String, String> _answers = {};
  int _currentQuestion = 0;
  bool _loading = false;
  String? _challengeId;

  late AnimationController _bounceCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _bounceAnim;
  late Animation<double> _pulseAnim;
  late Animation<Offset> _slideAnim;

  final List<Map<String, dynamic>> _categories = [
    {
      'name': 'Criminal Law',
      'icon': '🔍',
      'color': const Color(0xFFDC2626),
      'desc': 'Murder, theft, assault',
      'fact': 'IPC has 511 sections!',
      'gradient': [Color(0xFFDC2626), Color(0xFFEF4444)]
    },
    {
      'name': 'Civil Law',
      'icon': '⚖️',
      'color': const Color(0xFF3B82F6),
      'desc': 'Disputes & damages',
      'fact': 'Civil cases → no jail!',
      'gradient': [Color(0xFF3B82F6), Color(0xFF06B6D4)]
    },
    {
      'name': 'Family Law',
      'icon': '👨‍👩‍👧',
      'color': const Color(0xFFE91E8C),
      'desc': 'Custody & divorce',
      'fact': 'Hindu Marriage Act 1955',
      'gradient': [Color(0xFFE91E8C), Color(0xFFFF6BB3)]
    },
    {
      'name': 'Contract Law',
      'icon': '📝',
      'color': const Color(0xFFD97706),
      'desc': 'Agreements & breaches',
      'fact': 'Contract Act from 1872!',
      'gradient': [Color(0xFFD97706), Color(0xFFF59E0B)]
    },
    {
      'name': 'Cyber Law',
      'icon': '💻',
      'color': const Color(0xFF059669),
      'desc': 'Digital crimes',
      'fact': 'IT Act covers cyber crimes',
      'gradient': [Color(0xFF059669), Color(0xFF34D399)]
    },
    {
      'name': 'Property Law',
      'icon': '🏠',
      'color': const Color(0xFFD97706),
      'desc': 'Land disputes',
      'fact': 'TPA 1882 governs transfers',
      'gradient': [Color(0xFFD97706), Color(0xFFFBBF24)]
    },
    {
      'name': 'Constitutional',
      'icon': '🏛️',
      'color': const Color(0xFF7C3AED),
      'desc': 'Fundamental rights',
      'fact': 'Constitution has 395 articles!',
      'gradient': [Color(0xFF7C3AED), Color(0xFF9F67FF)]
    },
    {
      'name': 'Random Case',
      'icon': '🎲',
      'color': const Color(0xFFE91E8C),
      'desc': 'Surprise challenge!',
      'fact': 'Test all legal knowledge',
      'gradient': [Color(0xFFE91E8C), Color(0xFFFF6BB3)]
    },
  ];

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _pulseCtrl = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this)
      ..repeat(reverse: true);
    _slideCtrl = AnimationController(
        duration: const Duration(milliseconds: 400), vsync: this);
    _bounceAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut));
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _slideAnim = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateChallenge(String category) async {
    setState(() {
      _loading = true;
      _selectedCategory = category;
    });
    try {
      final res = await DioClient.instance.post('/challenges/generate', data: {
        'category': category == 'Random Case'
            ? _categories[DateTime.now().millisecond % 7]['name']
            : category,
      });
      setState(() {
        _challenge = res.data['data'];
        _challengeId = _challenge!['challenge_id'];
        _answers = {};
        _currentQuestion = 0;
        _step = 1;
        _loading = false;
      });
      _bounceCtrl.forward(from: 0);
      _slideCtrl.forward(from: 0);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.error_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Failed to generate. Check internet!')
          ]),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
    }
  }

  Future<void> _submitAnswers() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.post(
          '/challenges/$_challengeId/submit',
          data: {'answers': _answers});
      setState(() {
        _result = res.data['data'];
        _step = 3;
        _loading = false;
      });
      HapticFeedback.heavyImpact();
      _bounceCtrl.forward(from: 0);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _questions => _challenge?['questions'] ?? [];

  String _qTypeLabel(String type) {
    switch (type) {
      case 'evidence':
        return '🔬 Evidence Analysis';
      case 'reasoning':
        return '⚖️ Legal Reasoning';
      case 'truefalse':
        return '✅ True or False';
      case 'decision':
        return '👨‍⚖️ Final Verdict';
      default:
        return '❓ Legal Knowledge';
    }
  }

  Color _qTypeColor(String type) {
    switch (type) {
      case 'evidence':
        return const Color(0xFF059669);
      case 'reasoning':
        return const Color(0xFFD97706);
      case 'truefalse':
        return const Color(0xFF3B82F6);
      case 'decision':
        return _pink;
      default:
        return const Color(0xFF7C3AED);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (_step == 0) {
              context.pop();
              return;
            }
            showDialog(
                context: context,
                builder: (_) => AlertDialog(
                      backgroundColor: _bgCard,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: const Text('Quit Challenge?',
                          style: TextStyle(
                              color: _textPri, fontWeight: FontWeight.w700)),
                      content: const Text('Your progress will be lost.',
                          style: TextStyle(color: _textMuted)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Continue',
                                style: TextStyle(color: _pink))),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _step = 0;
                              _answers = {};
                              _challenge = null;
                              _result = null;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          child: const Text('Quit',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ));
          },
        ),
        title: Text(
          _step == 0
              ? '⚖️ Case Challenge'
              : _step == 1
                  ? '📋 Case Brief'
                  : _step == 2
                      ? 'Question ${_currentQuestion + 1} of ${_questions.length}'
                      : '🏆 Results',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_step == 2)
            Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                    child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('${_answers.length}/${_questions.length} done',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                ))),
        ],
      ),
      body: _loading
          ? _buildLoading()
          : _step == 0
              ? _buildCategorySelect()
              : _step == 1
                  ? _buildCaseView()
                  : _step == 2
                      ? _buildQuizView()
                      : _buildResultView(),
    );
  }

  Widget _buildLoading() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        ScaleTransition(
            scale: _pulseAnim,
            child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_navy, _pink]),
                    shape: BoxShape.circle),
                child: const Center(
                    child: Text('⚖️', style: TextStyle(fontSize: 50))))),
        const SizedBox(height: 24),
        const Text('Groq AI is generating',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w700)),
        const Text('your unique case...',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Every case is 100% different!',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 24),
        const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(color: _pink, strokeWidth: 3)),
      ]));

  Widget _buildCategorySelect() => LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                          color: _navy.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                            color: _blueLight, shape: BoxShape.circle),
                        child: const Center(
                            child: Text('⚖️', style: TextStyle(fontSize: 32)))),
                    const SizedBox(height: 14),
                    const Text('AI Legal Challenge',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _navy,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('10 unique questions • Powered by Groq AI',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: const [
                        _HeroBadgeWidget(Icons.quiz_rounded, '10 Qs'),
                        _HeroBadgeWidget(Icons.bolt_rounded, 'Earn XP',
                            iconColor: _gold),
                        _HeroBadgeWidget(Icons.emoji_events_rounded, 'Unique',
                            iconColor: _gold),
                      ],
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text('Choose Category',
                style: TextStyle(
                    color: _navy, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...List.generate(_categories.length, (i) {
              final cat = _categories[i];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 200 + (i * 60)),
                builder: (_, v, child) => Opacity(
                    opacity: v.clamp(0.0, 1.0),
                    child: Transform.translate(
                        offset: Offset(30 * (1 - v), 0), child: child)),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _generateChallenge(cat['name']);
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: _bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                        boxShadow: [
                          BoxShadow(
                              color: _navy.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: _blueLight,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Center(
                                  child: Text(cat['icon'],
                                      style: const TextStyle(fontSize: 22)))),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text(cat['name'],
                                    style: const TextStyle(
                                        color: _navy,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(cat['desc'],
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text('💡 ${cat['fact']}',
                                    style: const TextStyle(
                                        color: _pink, fontSize: 10)),
                              ])),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward_ios_rounded,
                              color: _textMuted.withValues(alpha: 0.6), size: 16),
                        ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
          ],
        );
      });

  Widget _buildCaseView() {
    final suspects = _challenge?['suspects'] as List? ?? [];
    final witnesses = _challenge?['witnesses'] as List? ?? [];
    final evidence = _challenge?['evidence'] as List? ?? [];

    return SlideTransition(
        position: _slideAnim,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _pink.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                        color: _pink.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFB5166E),
                                Color(0xFFE91E8C)
                              ]),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('📁 $_selectedCategory',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700))),
                      const Spacer(),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Row(children: [
                            Icon(Icons.auto_awesome,
                                color: Color(0xFF059669), size: 12),
                            SizedBox(width: 4),
                            Text('Groq AI',
                                style: TextStyle(
                                    color: Color(0xFF059669), fontSize: 10))
                          ])),
                    ]),
                    const SizedBox(height: 12),
                    Text(_challenge?['case_title'] ?? '',
                        style: const TextStyle(
                            color: _textPri,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.3)),
                    const SizedBox(height: 12),
                    Divider(color: _border, thickness: 0.6),
                    const SizedBox(height: 10),
                    const Row(children: [
                      Icon(Icons.description_rounded,
                          color: Color(0xFFD97706), size: 14),
                      SizedBox(width: 6),
                      Text('Case Description',
                          style: TextStyle(
                              color: Color(0xFFD97706),
                              fontWeight: FontWeight.w700,
                              fontSize: 13))
                    ]),
                    const SizedBox(height: 8),
                    Text(_challenge?['case_story'] ?? '',
                        style: const TextStyle(
                            color: _textPri, fontSize: 13, height: 1.7)),
                  ])),
          const SizedBox(height: 14),
          if (suspects.isNotEmpty) ...[
            _SecHeader('🕵️ Suspects', const Color(0xFFDC2626)),
            const SizedBox(height: 8),
            ...suspects.map((s) => _InfoCard(
                s['name'] ?? '', s['description'] ?? '',
                extra: 'Motive: ${s['motive'] ?? ''}',
                color: const Color(0xFFDC2626))),
            const SizedBox(height: 14)
          ],
          if (witnesses.isNotEmpty) ...[
            _SecHeader('👤 Witnesses', const Color(0xFF3B82F6)),
            const SizedBox(height: 8),
            ...witnesses.map((w) => _InfoCard(
                w['name'] ?? '', '"${w['statement'] ?? ''}"',
                color: const Color(0xFF3B82F6))),
            const SizedBox(height: 14)
          ],
          if (evidence.isNotEmpty) ...[
            _SecHeader('🔬 Evidence', const Color(0xFF059669)),
            const SizedBox(height: 8),
            ...evidence.map((e) => _InfoCard(
                e['item'] ?? '', e['description'] ?? '',
                extra: 'Type: ${e['type'] ?? ''}',
                color: const Color(0xFF059669))),
            const SizedBox(height: 20)
          ],
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _pink.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _pink.withValues(alpha: 0.2))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _CaseStat('10', 'Questions', Icons.quiz_rounded),
                    _CaseStat('150', 'Max XP', Icons.bolt_rounded),
                    _CaseStat('3', 'Max Stars', Icons.star_rounded),
                  ])),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  setState(() {
                    _step = 2;
                    _currentQuestion = 0;
                  });
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text('Start Investigation 🔍',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ]),
              )),
          const SizedBox(height: 40),
        ]));
  }

  Widget _buildQuizView() {
    if (_questions.isEmpty)
      return const Center(
          child: Text('No questions', style: TextStyle(color: _textMuted)));
    final q = _questions[_currentQuestion];
    final qId = q['id'] ?? 'q${_currentQuestion + 1}';
    final options = (q['options'] as List?)?.cast<String>() ?? [];
    final type = q['type'] ?? 'mcq';
    final typeColor = _qTypeColor(type);
    final isAnswered = _answers.containsKey(qId);
    final selectedAns = _answers[qId];
    final correctAns = q['correct_answer'] ?? '';

    return Column(children: [
      Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: _bgCard,
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Question ${_currentQuestion + 1} of ${_questions.length}',
                  style: const TextStyle(color: _textMuted, fontSize: 12)),
              Text(
                  '${((_currentQuestion + 1) / _questions.length * 100).toInt()}%',
                  style: TextStyle(
                      color: typeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (_currentQuestion + 1) / _questions.length,
                  backgroundColor: _border,
                  valueColor: AlwaysStoppedAnimation(typeColor),
                  minHeight: 8,
                )),
            const SizedBox(height: 8),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_questions.length, (i) {
                  Color dotColor = i < _currentQuestion
                      ? const Color(0xFF059669)
                      : i == _currentQuestion
                          ? typeColor
                          : _border;
                  return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: i == _currentQuestion ? 16 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: dotColor,
                          borderRadius: BorderRadius.circular(4)));
                })),
          ])),
      Expanded(
          child: SlideTransition(
              position: _slideAnim,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: typeColor.withValues(alpha: 0.3))),
                      child: Text(_qTypeLabel(type),
                          style: TextStyle(
                              color: typeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)))
                ]),
                const SizedBox(height: 14),
                Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: _bgCard,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: typeColor.withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(
                              color: typeColor.withValues(alpha: 0.08),
                              blurRadius: 15,
                              offset: const Offset(0, 4))
                        ]),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Center(
                                  child: Text('${_currentQuestion + 1}',
                                      style: TextStyle(
                                          color: typeColor,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16)))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(q['question'] ?? '',
                                  style: const TextStyle(
                                      color: _textPri,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      height: 1.5))),
                        ])),
                const SizedBox(height: 16),
                ...options.asMap().entries.map((entry) {
                  final i = entry.key;
                  final option = entry.value;
                  final isSelected = selectedAns == option;
                  final isCorrect = isAnswered && option == correctAns;
                  final isWrong =
                      isAnswered && isSelected && option != correctAns;
                  Color borderColor = _border;
                  Color bgColor = _bgCard;
                  IconData? trailIcon;
                  Color? trailColor;
                  if (isCorrect) {
                    borderColor = const Color(0xFF059669);
                    bgColor = const Color(0xFF059669).withValues(alpha: 0.08);
                    trailIcon = Icons.check_circle_rounded;
                    trailColor = const Color(0xFF059669);
                  } else if (isWrong) {
                    borderColor = const Color(0xFFDC2626);
                    bgColor = const Color(0xFFDC2626).withValues(alpha: 0.08);
                    trailIcon = Icons.cancel_rounded;
                    trailColor = const Color(0xFFDC2626);
                  } else if (isSelected) {
                    borderColor = typeColor;
                    bgColor = typeColor.withValues(alpha: 0.08);
                  }
                  final letters = ['A', 'B', 'C', 'D'];
                  return GestureDetector(
                    onTap: isAnswered
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _answers[qId] = option;
                            });
                            Future.delayed(const Duration(milliseconds: 1500),
                                () {
                              if (mounted &&
                                  _currentQuestion < _questions.length - 1) {
                                _slideCtrl.reset();
                                setState(() {
                                  _currentQuestion++;
                                });
                                _slideCtrl.forward();
                              }
                            });
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: borderColor,
                              width: isSelected || isCorrect ? 2 : 1)),
                      child: Row(children: [
                        AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                                color: isCorrect
                                    ? const Color(0xFF059669)
                                    : isWrong
                                        ? const Color(0xFFDC2626)
                                        : isSelected
                                            ? typeColor
                                            : _border.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8)),
                            child: Center(
                                child: Text(
                                    i < letters.length
                                        ? letters[i]
                                        : '${i + 1}',
                                    style: TextStyle(
                                        color:
                                            isSelected || isCorrect || isWrong
                                                ? Colors.white
                                                : _textMuted,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13)))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(option,
                                style: TextStyle(
                                    color: isCorrect
                                        ? const Color(0xFF059669)
                                        : isWrong
                                            ? const Color(0xFFDC2626)
                                            : isSelected
                                                ? typeColor
                                                : _textPri,
                                    fontWeight: isSelected || isCorrect
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    fontSize: 14))),
                        if (trailIcon != null)
                          Icon(trailIcon, color: trailColor, size: 22),
                      ]),
                    ),
                  );
                }),
                if (isAnswered && (q['explanation'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.2))),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lightbulb_rounded,
                                color: Color(0xFFD97706), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  const Text('Explanation',
                                      style: TextStyle(
                                          color: Color(0xFFD97706),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(q['explanation'],
                                      style: const TextStyle(
                                          color: _textPri,
                                          fontSize: 12,
                                          height: 1.5)),
                                ])),
                          ])),
                ],
              ]))),
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _bgCard,
              border: Border(top: BorderSide(color: _border, width: 0.8))),
          child: Row(children: [
            if (_currentQuestion > 0) ...[
              Expanded(
                  child: OutlinedButton(
                onPressed: () {
                  _slideCtrl.reset();
                  setState(() {
                    _currentQuestion--;
                  });
                  _slideCtrl.forward();
                },
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child:
                    const Text('← Back', style: TextStyle(color: _textMuted)),
              )),
              const SizedBox(width: 12)
            ],
            Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentQuestion < _questions.length - 1) {
                      _slideCtrl.reset();
                      setState(() {
                        _currentQuestion++;
                      });
                      _slideCtrl.forward();
                    } else {
                      if (_answers.length < _questions.length) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Answer all ${_questions.length} questions first!'),
                            backgroundColor: const Color(0xFFD97706),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))));
                      } else {
                        _submitAnswers();
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentQuestion == _questions.length - 1
                        ? const Color(0xFF059669)
                        : _pink,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                      _currentQuestion < _questions.length - 1
                          ? 'Next →'
                          : 'Submit Verdict ⚖️',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                )),
          ])),
    ]);
  }

  Widget _buildResultView() {
    final accuracy = (_result?['accuracy'] ?? 0.0).toDouble();
    final stars = (_result?['stars'] ?? 0) as int;
    final xpEarned = (_result?['xp_earned'] ?? 0) as int;
    final totalXP = (_result?['total_xp'] ?? 0) as int;
    final level = (_result?['level'] ?? 1) as int;
    final correct = (_result?['correct'] ?? 0) as int;
    final total = (_result?['total'] ?? 0) as int;
    final passed = _result?['passed'] ?? false;
    final message = _result?['message'] ?? '';
    final badges = (_result?['badges'] as List?)?.cast<String>() ?? [];

    return ScaleTransition(
        scale: _bounceAnim,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: passed
                        ? [const Color(0xFFB5166E), const Color(0xFFE91E8C)]
                        : [const Color(0xFFD97706), const Color(0xFFF59E0B)]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: (passed ? _pink : const Color(0xFFD97706))
                          .withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8))
                ],
              ),
              child: Column(children: [
                Text(
                    stars == 3
                        ? '🏆'
                        : stars == 2
                            ? '⭐'
                            : stars == 1
                                ? '✅'
                                : '📚',
                    style: const TextStyle(fontSize: 72)),
                const SizedBox(height: 8),
                Text(passed ? 'Case Solved! 🎉' : 'Keep Practicing!',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: const Color(0xFF546E7A), fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        3,
                        (i) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration:
                                    Duration(milliseconds: 500 + (i * 200)),
                                curve: Curves.elasticOut,
                                builder: (_, v, __) => Transform.scale(
                                    scale: v,
                                    child: Icon(
                                        i < stars
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        color: Colors.amber,
                                        size: 40)))))),
              ])),
          const SizedBox(height: 20),
          GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _ScoreCard(
                    '${accuracy.toInt()}%',
                    'Accuracy',
                    Icons.percent_rounded,
                    accuracy >= 70
                        ? const Color(0xFF059669)
                        : const Color(0xFFD97706)),
                _ScoreCard('$correct / $total', 'Correct',
                    Icons.check_circle_rounded, const Color(0xFF3B82F6)),
                _ScoreCard('+$xpEarned XP', 'XP Earned', Icons.bolt_rounded,
                    const Color(0xFFD97706)),
                _ScoreCard('Level $level', 'Current Level',
                    Icons.military_tech_rounded, _pink),
              ]),
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _pink.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                        color: _pink.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]),
              child: Column(children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Level $level',
                          style: const TextStyle(
                              color: _pink, fontWeight: FontWeight.w700)),
                      Text('$totalXP / ${level * 500} XP',
                          style:
                              const TextStyle(color: _textMuted, fontSize: 12)),
                    ]),
                const SizedBox(height: 8),
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: (totalXP % 500) / 500.0),
                      duration: const Duration(milliseconds: 1500),
                      curve: Curves.easeOut,
                      builder: (_, v, __) => LinearProgressIndicator(
                          value: v.clamp(0.0, 1.0),
                          backgroundColor: _border,
                          valueColor: const AlwaysStoppedAnimation(_pink),
                          minHeight: 12),
                    )),
              ])),
          const SizedBox(height: 16),
          if (badges.isNotEmpty) ...[
            const Text('🏅 Badges Earned',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: badges
                    .map((b) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: _pink,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(b,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ))
                    .toList()),
            const SizedBox(height: 16),
          ],
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _step = 0;
                _answers = {};
                _currentQuestion = 0;
                _challenge = null;
                _result = null;
              }),
              icon: const Icon(Icons.refresh_rounded, color: _pink),
              label: const Text('New Case', style: TextStyle(color: _pink)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _pink),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.home_rounded, color: Colors.white),
              label: const Text('Home', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _pink,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
          ]),
          const SizedBox(height: 40),
        ]));
  }
}

// ── Helpers ────────────────────────────────────────
class _HeroBadgeWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const _HeroBadgeWidget(this.icon, this.label, {this.iconColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: _blueLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: iconColor ?? _pink),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: _navy, fontSize: 11, fontWeight: FontWeight.w700))
        ]),
      );
}

Widget _CaseStat(String value, String label, IconData icon) =>
    Column(children: [
      Icon(icon, color: _pink, size: 20),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(
              color: _textPri, fontSize: 16, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: _textMuted, fontSize: 10)),
    ]);

Widget _SecHeader(String title, Color color) => Text(title,
    style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700));

class _InfoCard extends StatelessWidget {
  final String title, subtitle;
  final String? extra;
  final Color color;
  const _InfoCard(this.title, this.subtitle, {this.extra, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: _pink.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          Text(subtitle,
              style:
                  const TextStyle(color: _textPri, fontSize: 12, height: 1.4)),
          if (extra != null) ...[
            const SizedBox(height: 4),
            Text(extra!,
                style: const TextStyle(color: _textMuted, fontSize: 11))
          ],
        ]),
      );
}

class _ScoreCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _ScoreCard(this.value, this.label, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                  color: _pink.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w800))),
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 10)),
        ]),
      );
}
