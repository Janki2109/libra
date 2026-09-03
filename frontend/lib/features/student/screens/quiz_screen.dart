import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF0F4FF);
const _bgCard = Color(0xFFFFFFFF);
const _blue = Color(0xFF1565C0);
const _border = Color(0xFFBBDEFB);
const _textPri = Color(0xFF0A1628);
const _textMuted = Color(0xFF546E7A);
const _gold = Color(0xFFFFD700);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  String? _selectedSubject;
  String? _selectedType;
  List<Map<String, dynamic>> _questions = [];
  int _currentQ = 0;
  int? _selectedAnswer;
  bool _answered = false;
  int _score = 0;
  bool _loading = false;
  bool _finished = false;
  String? _error; // clean, user-friendly message only — never a raw exception

  final List<Map<String, dynamic>> _subjects = [
    {
      'name': 'Constitutional Law',
      'icon': '📜',
      'color': const Color(0xFF1565C0)
    },
    {'name': 'BNS / IPC', 'icon': '⚖️', 'color': const Color(0xFFD9534F)},
    {
      'name': 'Law of Contracts',
      'icon': '🤝',
      'color': const Color(0xFF2E8B57)
    },
    {'name': 'Law of Evidence', 'icon': '🔍', 'color': const Color(0xFF7C3AED)},
    {
      'name': 'Family Law',
      'icon': '👨‍👩‍👧',
      'color': const Color(0xFFD4A017)
    },
    {'name': 'Company Law', 'icon': '🏢', 'color': const Color(0xFF0288D1)},
    {
      'name': 'Mixed (All Topics)',
      'icon': '🎯',
      'color': const Color(0xFF0A1628)
    },
  ];

  final List<Map<String, dynamic>> _types = [
    {'name': 'MCQ (10 Questions)', 'icon': '✅', 'count': 10, 'type': 'mcq'},
    {
      'name': 'Subject Quiz (15 Q)',
      'icon': '📚',
      'count': 15,
      'type': 'subject'
    },
    {'name': 'Mock Exam (25 Q)', 'icon': '📝', 'count': 25, 'type': 'mock'},
    {'name': 'Case Based (5 Q)', 'icon': '⚖️', 'count': 5, 'type': 'case'},
  ];

  Future<void> _startQuiz() async {
    if (_selectedSubject == null || _selectedType == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _questions = [];
      _currentQ = 0;
      _score = 0;
      _finished = false;
    });
    HapticFeedback.lightImpact();

    final typeMap = _types.firstWhere((t) => t['name'] == _selectedType);
    final count = typeMap['count'] as int;
    final type = typeMap['type'] as String;

    try {
      // The Groq key(s) and rotation live on the backend only (services/
      // groq_service.go) — this screen never talks to Groq directly.
      final response = await DioClient.instance.post('/ai/quiz', data: {
        'subject': _selectedSubject,
        'count': count,
        'quiz_type': type,
      });

      String raw = response.data['data']?['content'] ?? '[]';
      // Clean JSON
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      if (start >= 0 && end >= 0) raw = raw.substring(start, end + 1);

      List<Map<String, dynamic>> parsed = [];
      if (raw.isNotEmpty && raw.contains('{')) {
        final list = _parseJson(raw);
        parsed = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      setState(() {
        _questions = parsed.take(count).toList();
        _loading = false;
        // An empty/unparseable result is effectively a failure too — show
        // the same clean retry state instead of a blank quiz.
        if (_questions.isEmpty) {
          _error = 'AI is temporarily unavailable. Please try again.';
        }
      });
    } catch (e) {
      // Never surface a raw DioException/HTTP status to the user — the
      // backend already tried every configured Groq key before giving up.
      setState(() {
        _loading = false;
        _error = 'AI is temporarily unavailable. Please try again.';
      });
    }
  }

  List<dynamic> _parseJson(String raw) {
    try {
      final cleaned = raw.replaceAll('\n', ' ').replaceAll('\r', '');
      if (cleaned.startsWith('[')) {
        return List<dynamic>.from(jsonDecode(cleaned));
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  void _selectAnswer(int idx) {
    if (_answered) return;
    HapticFeedback.lightImpact();
    final correct = _questions[_currentQ]['correct'] as int;
    setState(() {
      _selectedAnswer = idx;
      _answered = true;
      if (idx == correct) {
        _score++;
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _nextQuestion() {
    if (_currentQ < _questions.length - 1) {
      setState(() {
        _currentQ++;
        _selectedAnswer = null;
        _answered = false;
      });
    } else {
      setState(() => _finished = true);
      _submitResult();
    }
  }

  /// Records the score so certificate eligibility (e.g. "Score 80%+ in
  /// Constitutional Law Quiz") has something real to check against — quizzes
  /// used to be graded entirely on-device and forgotten the moment the
  /// screen closed. Fire-and-forget: a failed submission shouldn't block the
  /// student from seeing their own result.
  Future<void> _submitResult() async {
    if (_questions.isEmpty || _selectedSubject == null) return;
    final pct = (_score / _questions.length * 100).round();
    try {
      await DioClient.instance.post('/student/quiz/submit', data: {
        'subject': _selectedSubject,
        'score_percent': pct,
      });
    } catch (_) {}
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
                        if (_questions.isNotEmpty)
                          setState(() {
                            _questions = [];
                            _selectedSubject = null;
                            _selectedType = null;
                            _finished = false;
                          });
                        else
                          context.pop();
                      }),
                  const Expanded(
                      child: Text('Legal Quiz',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700))),
                  if (_questions.isNotEmpty && !_finished)
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${_currentQ + 1}/${_questions.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                ]),
              )),
        ),

        Expanded(
            child: _loading
                ? _buildLoading()
                : _error != null
                    ? _buildError()
                    : _finished
                        ? _buildResult()
                        : _questions.isEmpty
                            ? _buildSetup()
                            : _buildQuestion()),
      ]),
    );
  }

  // Small, professional error state — replaces the old raw-exception
  // SnackBar. Retry re-runs the same request with the same subject/type.
  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.08),
                    shape: BoxShape.circle),
                child: const Icon(Icons.cloud_off_rounded,
                    color: _blue, size: 30)),
            const SizedBox(height: 16),
            Text(_error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _textPri, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _startQuiz,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text('Retry',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() {
                _error = null;
                _selectedSubject = null;
                _selectedType = null;
              }),
              child: const Text('Choose a different subject',
                  style: TextStyle(color: _textMuted, fontSize: 12)),
            ),
          ]),
        ),
      );

  Widget _buildLoading() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: _blue),
        const SizedBox(height: 20),
        const Text('Generating Questions...',
            style: TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Preparing $_selectedSubject quiz',
            style: const TextStyle(color: _textMuted, fontSize: 13)),
      ]));

  Widget _buildSetup() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Select Subject',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.5),
          itemCount: _subjects.length,
          itemBuilder: (_, i) {
            final s = _subjects[i];
            final sel = _selectedSubject == s['name'];
            final color = s['color'] as Color;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedSubject = s['name']);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: sel ? color.withValues(alpha: 0.12) : _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel ? color : _border, width: sel ? 2 : 0.8)),
                child: Row(children: [
                  Text(s['icon'], style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(s['name'],
                          style: TextStyle(
                              color: sel ? color : _textPri,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 11),
                          maxLines: 2)),
                  if (sel)
                    Icon(Icons.check_circle_rounded, color: color, size: 16),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('Select Quiz Type',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ..._types.map((t) {
          final sel = _selectedType == t['name'];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedType = t['name']);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: sel ? _blue.withValues(alpha: 0.08) : _bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: sel ? _blue : _border, width: sel ? 2 : 0.8)),
              child: Row(children: [
                Text(t['icon'], style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(t['name'],
                        style: TextStyle(
                            color: sel ? _blue : _textPri,
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w500))),
                if (sel)
                  const Icon(Icons.check_circle_rounded,
                      color: _blue, size: 20),
              ]),
            ),
          );
        }),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: (_selectedSubject != null && _selectedType != null)
                ? _startQuiz
                : null,
            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
            label: const Text('Start Quiz',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ),
        const SizedBox(height: 40),
      ]);

  Widget _buildQuestion() {
    if (_questions.isEmpty || _currentQ >= _questions.length)
      return const SizedBox();
    final q = _questions[_currentQ];
    final options = List<String>.from(q['options'] ?? []);
    final correct = q['correct'] as int? ?? 0;
    final explanation = q['explanation'] as String? ?? '';

    // Progress bar
    final progress = (_currentQ + 1) / _questions.length;

    return Column(children: [
      // Progress
      LinearProgressIndicator(
          value: progress,
          backgroundColor: _border,
          valueColor: const AlwaysStoppedAnimation(_blue),
          minHeight: 4),

      Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        // Score
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Question ${_currentQ + 1}',
              style: const TextStyle(color: _textMuted, fontSize: 12)),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('Score: $_score',
                  style: const TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w700,
                      fontSize: 12))),
        ]),
        const SizedBox(height: 14),

        // Question
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _blue.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]),
          child: Text(q['question'] ?? '',
              style: const TextStyle(
                  color: _textPri,
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 16),

        // Options
        ...options.asMap().entries.map((e) {
          final i = e.key;
          final opt = e.value;
          Color bgColor = _bgCard;
          Color borderColor = _border;
          Color textColor = _textPri;
          IconData? trailingIcon;

          if (_answered) {
            if (i == correct) {
              bgColor = _green.withValues(alpha: 0.08);
              borderColor = _green;
              textColor = _green;
              trailingIcon = Icons.check_circle_rounded;
            } else if (i == _selectedAnswer) {
              bgColor = _red.withValues(alpha: 0.08);
              borderColor = _red;
              textColor = _red;
              trailingIcon = Icons.cancel_rounded;
            }
          } else if (_selectedAnswer == i) {
            bgColor = _blue.withValues(alpha: 0.08);
            borderColor = _blue;
            textColor = _blue;
          }

          return GestureDetector(
            onTap: () => _selectAnswer(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: borderColor,
                      width: _answered && i == correct ? 2 : 0.8)),
              child: Row(children: [
                Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: borderColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor, width: 0.8)),
                    child: Center(
                        child: Text(['A', 'B', 'C', 'D'][i],
                            style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)))),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(opt.length > 2 ? opt.substring(3) : opt,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500))),
                if (trailingIcon != null)
                  Icon(trailingIcon, color: borderColor, size: 20),
              ]),
            ),
          );
        }),

        // Explanation
        if (_answered && explanation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _blue.withValues(alpha: 0.2))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.lightbulb_rounded, color: _blue, size: 16),
                SizedBox(width: 6),
                Text('Explanation',
                    style: TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              Text(explanation,
                  style: const TextStyle(
                      color: _textPri, fontSize: 13, height: 1.4)),
            ]),
          ),
        ],

        if (_answered) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _nextQuestion,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text(
                  _currentQ < _questions.length - 1
                      ? 'Next Question →'
                      : 'See Results',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ])),
    ]);
  }

  Widget _buildResult() {
    final total = _questions.length;
    final pct = total > 0 ? (_score / total * 100).round() : 0;
    final passed = pct >= 60;
    final grade = pct >= 90
        ? 'A+'
        : pct >= 80
            ? 'A'
            : pct >= 70
                ? 'B'
                : pct >= 60
                    ? 'C'
                    : 'F';
    final color = pct >= 60 ? _green : _red;

    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 20),
      // Score circle
      Center(
          child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 3),
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 20)
                  ]),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(grade,
                        style: TextStyle(
                            color: color,
                            fontSize: 36,
                            fontWeight: FontWeight.w900)),
                    Text('$_score/$total',
                        style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    Text('$pct%',
                        style: TextStyle(
                            color: color.withValues(alpha: 0.7), fontSize: 13)),
                  ]))),
      const SizedBox(height: 24),
      Text(passed ? '🎉 Congratulations!' : '📚 Keep Studying!',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color, fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
          pct >= 90
              ? 'Outstanding performance!'
              : pct >= 70
                  ? 'Good job! Keep it up!'
                  : pct >= 60
                      ? 'Passed! Review weak areas.'
                      : 'Review your notes and try again.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 14)),
      const SizedBox(height: 30),

      // Stats
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border, width: 0.8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _StatCol('$_score', 'Correct', _green),
          _StatCol('${total - _score}', 'Wrong', _red),
          _StatCol('$total', 'Total', _blue),
          _StatCol('$pct%', 'Score', color),
        ]),
      ),
      const SizedBox(height: 20),
      if (passed)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withValues(alpha: 0.3))),
          child: const Row(children: [
            Text('🏆', style: TextStyle(fontSize: 24)),
            SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Certificate Eligible!',
                      style: TextStyle(
                          color: Color(0xFFB8860B),
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Text('Go to Certificates to claim your achievement',
                      style: TextStyle(color: Color(0xFF8B5E3C), fontSize: 11)),
                ])),
          ]),
        ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child: OutlinedButton(
          onPressed: () => setState(() {
            _questions = [];
            _finished = false;
            _score = 0;
          }),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('Try Again',
              style: TextStyle(color: _blue, fontWeight: FontWeight.w700)),
        )),
        const SizedBox(width: 12),
        Expanded(
            child: ElevatedButton(
          onPressed: () => setState(() {
            _questions = [];
            _selectedSubject = null;
            _selectedType = null;
            _finished = false;
            _score = 0;
          }),
          style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('New Quiz',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        )),
      ]),
      const SizedBox(height: 40),
    ]);
  }

  Widget _StatCol(String value, String label, Color color) => Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: _textMuted, fontSize: 11)),
      ]);
}
