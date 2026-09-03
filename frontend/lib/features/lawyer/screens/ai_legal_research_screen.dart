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
const _surface = Color(0xFFF6F5FB);

class AILegalResearchScreen extends StatefulWidget {
  const AILegalResearchScreen({super.key});
  @override
  State<AILegalResearchScreen> createState() => _AILegalResearchScreenState();
}

class _AILegalResearchScreenState extends State<AILegalResearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  // Quick research topics
  final List<Map<String, dynamic>> _quickTopics = [
    {
      'label': 'BNS Sections',
      'icon': '📋',
      'query':
          'Explain the important sections of Bharatiya Nyaya Sanhita (BNS) that replaced IPC'
    },
    {
      'label': 'Bail Laws',
      'icon': '🔓',
      'query':
          'Explain bail provisions under BNSS - anticipatory bail, regular bail, conditions'
    },
    {
      'label': 'Property Law',
      'icon': '🏠',
      'query':
          'Explain important property laws in India - Transfer of Property Act, registration'
    },
    {
      'label': 'Cheque Bounce',
      'icon': '🏦',
      'query':
          'Explain Section 138 NI Act - cheque bounce law, procedure, penalty'
    },
    {
      'label': 'Divorce Law',
      'icon': '👨‍👩‍👧',
      'query':
          'Explain divorce laws in India - Hindu Marriage Act, grounds, procedure'
    },
    {
      'label': 'Consumer Rights',
      'icon': '🛒',
      'query':
          'Explain Consumer Protection Act 2019 - rights, remedies, consumer courts'
    },
    {
      'label': 'Cyber Crime',
      'icon': '💻',
      'query':
          'Explain IT Act 2000 and cyber crime laws in India - important sections'
    },
    {
      'label': 'POCSO Act',
      'icon': '🔒',
      'query': 'Explain POCSO Act - Protection of Children from Sexual Offences'
    },
    {
      'label': 'Labour Laws',
      'icon': '👷',
      'query':
          'Explain important labour laws in India - Industrial Disputes Act, Factories Act'
    },
    {
      'label': 'Company Law',
      'icon': '🏢',
      'query':
          'Explain Companies Act 2013 - incorporation, directors, liability'
    },
    {
      'label': 'Tax Laws',
      'icon': '💰',
      'query': 'Explain Income Tax Act and GST - key provisions for lawyers'
    },
    {
      'label': 'Constitution',
      'icon': '📜',
      'query':
          'Explain Fundamental Rights under Constitution of India - Articles 12-35'
    },
  ];

  // Landmark cases
  final List<Map<String, dynamic>> _landmarkCases = [
    {
      'case': 'Kesavananda Bharati vs State of Kerala',
      'year': '1973',
      'topic': 'Basic Structure Doctrine',
      'icon': '🏛️'
    },
    {
      'case': 'Maneka Gandhi vs Union of India',
      'year': '1978',
      'topic': 'Article 21 - Right to Life',
      'icon': '⚖️'
    },
    {
      'case': 'Vishaka vs State of Rajasthan',
      'year': '1997',
      'topic': 'Sexual Harassment at Workplace',
      'icon': '👩‍⚖️'
    },
    {
      'case': 'Shah Bano Case',
      'year': '1985',
      'topic': 'Muslim Women Maintenance',
      'icon': '📋'
    },
    {
      'case': 'K.S. Puttaswamy vs Union of India',
      'year': '2017',
      'topic': 'Right to Privacy',
      'icon': '🔒'
    },
    {
      'case': 'Navtej Singh Johar vs Union of India',
      'year': '2018',
      'topic': 'Section 377 - LGBTQ Rights',
      'icon': '🌈'
    },
    {
      'case': 'Indra Sawhney vs Union of India',
      'year': '1992',
      'topic': 'OBC Reservation - Mandal Commission',
      'icon': '📊'
    },
    {
      'case': 'A.K. Gopalan vs State of Madras',
      'year': '1950',
      'topic': 'Preventive Detention',
      'icon': '🔏'
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _messages.add({
      'role': 'ai',
      'text':
          '⚖️ Welcome to AI Legal Research!\n\nI can help you:\n• Search Acts & Sections (BNS, IPC, CrPC, BNSS)\n• Find Case Laws & Judgments\n• Research Property, Family, Criminal Law\n• Explain legal concepts simply\n\nWhat would you like to research today?'
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _research(String query) async {
    if (query.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _messages.add({'role': 'user', 'text': query.trim()});
      _loading = true;
    });
    _msgCtrl.clear();
    _searchCtrl.clear();
    _tabCtrl.animateTo(0); // Switch to chat tab
    _scrollToBottom();

    try {
      final reply = await _askResearchAI(query.trim());
      setState(() {
        _messages.add({'role': 'ai', 'text': reply});
        _loading = false;
      });
    } catch (e) {
      // The backend already retries every configured Groq key before
      // giving up, so a failure here means the service is genuinely
      // unavailable — never show the raw DioException/HTTP text.
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': '⚠️ AI service is temporarily unavailable. Please try again.'
        });
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  /// The Groq key(s) and rotation live entirely on the backend
  /// (services/groq_service.go) — this screen only sends conversation
  /// history and the latest question, never talks to Groq directly, and
  /// never sees or stores an API key.
  Future<String> _askResearchAI(String question) async {
    // Add recent messages for context
    final recent = _messages.length > 6
        ? _messages.sublist(_messages.length - 6)
        : _messages;
    final messages = <Map<String, String>>[];
    for (final msg in recent) {
      if (msg['role'] == 'user')
        messages.add({'role': 'user', 'content': msg['text'] ?? ''});
      else if (msg['role'] == 'ai' && msg != _messages.first)
        messages.add({'role': 'assistant', 'content': msg['text'] ?? ''});
    }
    messages.add({'role': 'user', 'content': question});

    final response = await DioClient.instance
        .post('/ai/research', data: {'messages': messages});
    return response.data['data']?['content'] ?? 'No response.';
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients)
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // ── Header ──────────────────────────────
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
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Column(children: [
                      Text('AI Legal Research',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Powered by Groq AI',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 10)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.history_rounded,
                          color: Colors.white),
                      tooltip: 'Research History',
                      onPressed: () =>
                          context.push('/lawyer/ai-research/history'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white),
                      onPressed: () => setState(() {
                        _messages.clear();
                        _messages.add({
                          'role': 'ai',
                          'text':
                              '⚖️ Research cleared! Ask me anything about Indian law.'
                        });
                      }),
                    ),
                  ]),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14)),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: _textPri, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search Acts, Sections, Case Laws...',
                        hintStyle:
                            const TextStyle(color: _textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: _brown, size: 20),
                        suffixIcon: GestureDetector(
                          onTap: () => _research(_searchCtrl.text),
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: _brown,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.send_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                        border: InputBorder.none,
                        filled: false,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onSubmitted: _research,
                    ),
                  ),
                ),

                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: const Color(0xFFFFD700),
                  indicatorWeight: 3,
                  labelColor: const Color(0xFFFFD700),
                  unselectedLabelColor: Colors.white60,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  // Non-scrollable equal-width tabs wrap these emoji+text
                  // labels to 2 lines on narrow screens, overflowing the
                  // TabBar's fixed height — FittedBox scales the label down
                  // to fit its tab instead of wrapping it.
                  tabs: const [
                    Tab(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('💬 Research', maxLines: 1))),
                    Tab(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('📋 Acts & Laws', maxLines: 1))),
                    Tab(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('⚖️ Case Laws', maxLines: 1))),
                  ],
                ),
              ])),
        ),

        // ── Content ──────────────────────────────
        Expanded(
            child: TabBarView(controller: _tabCtrl, children: [
          _buildChatTab(),
          _buildActsTab(),
          _buildCasesTab(),
        ])),
      ]),
    );
  }

  // ── Chat/Research Tab ────────────────────────────
  Widget _buildChatTab() => Column(children: [
        Expanded(
            child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(16),
          itemCount: _messages.length + (_loading ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == _messages.length) return _buildTyping();
            return _buildMessage(_messages[i]);
          },
        )),
        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(
              color: _bgCard,
              border: Border(top: BorderSide(color: _border, width: 0.8)),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -2))
              ]),
          child: Row(children: [
            Expanded(
                child: TextField(
              controller: _msgCtrl,
              style: const TextStyle(color: _textPri),
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask about any law, section, or case...',
                hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
                filled: true,
                fillColor: _surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: _brown)),
              ),
              onSubmitted: _loading ? null : _research,
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loading ? null : () => _research(_msgCtrl.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _loading ? _surface : _brown,
                  shape: BoxShape.circle,
                ),
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            color: _brown, strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]);

  // ── Acts & Laws Tab ──────────────────────────────
  Widget _buildActsTab() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Quick Research Topics',
            style: TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Tap any topic to get detailed research',
            style: TextStyle(color: _textMuted, fontSize: 12)),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.4),
          itemCount: _quickTopics.length,
          itemBuilder: (_, i) {
            final t = _quickTopics[i];
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _research(t['query']);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                          color: _brown.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ]),
                child: Row(children: [
                  Text(t['icon'], style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(t['label'],
                          style: const TextStyle(
                              color: _textPri,
                              fontWeight: FontWeight.w600,
                              fontSize: 12),
                          maxLines: 2)),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 20),

        // Common searches
        const Text('Common Searches',
            style: TextStyle(
                color: _textPri, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'IPC 420',
              'IPC 302',
              'Section 138 NI Act',
              'Article 21',
              'CRPC 161',
              'BNS 103',
              'Section 498A',
              'Article 32',
              'POCSO 4',
              'IT Act 66C',
              'GST Fraud',
              'Domestic Violence Act',
            ]
                .map((s) => GestureDetector(
                      onTap: () => _research(
                          'Explain $s in detail with recent judgments'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: _brown.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _border)),
                        child: Text(s,
                            style: const TextStyle(
                                color: _brown,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ))
                .toList()),
        const SizedBox(height: 40),
      ]);

  // ── Case Laws Tab ────────────────────────────────
  Widget _buildCasesTab() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Landmark Cases',
            style: TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Tap to get full case analysis',
            style: TextStyle(color: _textMuted, fontSize: 12)),
        const SizedBox(height: 14),
        ..._landmarkCases.map((c) => GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _research(
                    'Explain the case ${c['case']} (${c['year']}) - facts, judgment, significance, impact on Indian law');
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                          color: _brown.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ]),
                child: Row(children: [
                  Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: _brown.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: Text(c['icon'],
                              style: const TextStyle(fontSize: 22)))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(c['case'],
                            style: const TextStyle(
                                color: _textPri,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(c['topic'],
                            style: const TextStyle(
                                color: _brown,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        Text(c['year'],
                            style: const TextStyle(
                                color: _textMuted, fontSize: 10)),
                      ])),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: _textMuted, size: 13),
                ]),
              ),
            )),
        const SizedBox(height: 40),
      ]);

  Widget _buildMessage(Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: _brown.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Center(
                    child: Text('⚖️', style: TextStyle(fontSize: 14)))),
            const SizedBox(width: 8),
          ],
          Flexible(
              child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: isUser
                  ? const LinearGradient(colors: [_brown, _brownDark])
                  : null,
              color: isUser ? null : _bgCard,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser ? null : Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Text(msg['text'] ?? '',
                style: TextStyle(
                    color: isUser ? Colors.white : _textPri,
                    fontSize: 13,
                    height: 1.6)),
          )),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
                width: 32,
                height: 32,
                decoration:
                    const BoxDecoration(color: _brown, shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 18)),
          ],
        ],
      ),
    );
  }

  Widget _buildTyping() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: _brown.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Center(
                  child: Text('⚖️', style: TextStyle(fontSize: 14)))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border, width: 0.8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _Dot(0),
              const SizedBox(width: 4),
              _Dot(200),
              const SizedBox(width: 4),
              _Dot(400),
            ]),
          ),
        ]),
      );
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot(this.delay);
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _ctrl,
        child: Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: _brown, shape: BoxShape.circle)),
      );
}
