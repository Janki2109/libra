import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/dio_client.dart';

// Professional blue + white legal-tech theme.
const _bg = Color(0xFFF4F7FC);
const _bgCard = Color(0xFFFFFFFF);
const _blue = Color(0xFF1B3B7A); // navy/royal blue primary
const _blueLight = Color(0xFF4A90D9); // light blue accent
const _border = Color(0xFFDCE5F5);
const _textPri = Color(0xFF10203D);
const _textMuted = Color(0xFF64748B);
const _surface = Color(0xFFEFF4FC);

class AILawyerScreen extends StatefulWidget {
  const AILawyerScreen({super.key});
  @override
  State<AILawyerScreen> createState() => _AILawyerScreenState();
}

class _AILawyerScreenState extends State<AILawyerScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'ai',
      'text':
          '⚖️ Namaste! I am LexAI, your AI Legal Advisor.\n\nI can help you with:\n• Indian laws & IPC/CrPC/BNS sections\n• Legal rights & remedies\n• Case analysis & advice\n• Court procedures\n\nAsk me anything about Indian law! 🏛️'
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String? _lastQuestion; // lets the Retry button resend the same question

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    _lastQuestion = text.trim();
    setState(() {
      _messages.add({'role': 'user', 'text': text.trim()});
      _loading = true;
    });
    _msgCtrl.clear();
    _scrollToBottom();
    try {
      final reply = await _askAdvisor(text.trim());
      setState(() {
        _messages.add({'role': 'ai', 'text': reply});
        _loading = false;
      });
    } catch (e) {
      // Never surface a raw DioException/HTTP status to the user — the
      // backend already tried every configured Groq key before giving up.
      setState(() {
        _messages.add({
          'role': 'error',
          'text':
              'LexAI is temporarily unavailable. Please try again in a moment.'
        });
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  // The Groq key(s) and rotation live on the backend only (services/
  // groq_service.go) — this screen never talks to Groq directly, and never
  // sees which of the 5 configured keys actually served the request.
  Future<String> _askAdvisor(String question) async {
    final recent = _messages.length > 6
        ? _messages.sublist(_messages.length - 6)
        : _messages;
    final history = <Map<String, String>>[];
    for (final msg in recent) {
      if (msg['role'] == 'user') {
        history.add({'role': 'user', 'content': msg['text'] ?? ''});
      } else if (msg['role'] == 'ai' &&
          msg['text'] != _messages.first['text']) {
        history.add({'role': 'assistant', 'content': msg['text'] ?? ''});
      }
    }
    history.add({'role': 'user', 'content': question});

    final response = await DioClient.instance
        .post('/ai/legal-advisor', data: {'messages': history});
    return response.data['data']?['content'] ?? 'No response received.';
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients)
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  final List<String> _quickQuestions = [
    '🔍 What is bail?',
    '📋 Rights when arrested?',
    '🏠 Tenant rights?',
    '💰 Cheque bounce law?',
    '👨‍👩‍👧 Divorce procedure?',
    '🔒 What is FIR?',
    '⚖️ What is IPC 302?',
    '📜 Article 21 rights?'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _blue,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4), width: 1)),
              child: const Center(
                  child: Icon(Icons.balance_rounded,
                      color: Colors.white, size: 18))),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LexAI - Legal Advisor',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            Text('Powered by Groq AI',
                style: TextStyle(color: Colors.white70, fontSize: 9)),
          ]),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: () => setState(() {
                    _messages.clear();
                    _messages.add({
                      'role': 'ai',
                      'text':
                          '⚖️ Chat cleared! Ask me anything about Indian law. 🏛️'
                    });
                  }))
        ],
      ),
      body: Column(children: [
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
        if (_messages.length <= 1)
          SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _quickQuestions.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _sendMessage(_quickQuestions[i].substring(3)),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: _blueLight.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: _blueLight.withValues(alpha: 0.3))),
                    child: Text(_quickQuestions[i],
                        style: const TextStyle(
                            color: _blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              )),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(
              color: _bgCard,
              border: Border(top: BorderSide(color: _border, width: 0.8)),
              boxShadow: [
                BoxShadow(
                    color: _blue.withValues(alpha: 0.06),
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
                hintText: 'Ask any legal question...',
                hintStyle: const TextStyle(color: _textMuted),
                filled: true,
                fillColor: _surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        BorderSide(color: _blueLight.withValues(alpha: 0.3))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: _blue)),
              ),
              onSubmitted: _loading ? null : _sendMessage,
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loading ? null : () => _sendMessage(_msgCtrl.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _loading ? _surface : _blue,
                  shape: BoxShape.circle,
                ),
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            color: _blue, strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildMessage(Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    final isError = msg['role'] == 'error';
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
                      color: (isError ? Colors.redAccent : _blue)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle),
                  child: Center(
                      child: Icon(
                          isError
                              ? Icons.error_outline_rounded
                              : Icons.balance_rounded,
                          color: isError ? Colors.redAccent : _blue,
                          size: 16))),
              const SizedBox(width: 8),
            ],
            Flexible(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUser
                      ? _blue
                      : isError
                          ? Colors.red.withValues(alpha: 0.06)
                          : _bgCard,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser
                      ? null
                      : Border.all(
                          color: isError
                              ? Colors.redAccent.withValues(alpha: 0.3)
                              : _border,
                          width: 0.8),
                  boxShadow: isUser
                      ? [
                          BoxShadow(
                              color: _blue.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Text(msg['text'] ?? '',
                    style: TextStyle(
                        color: isUser
                            ? Colors.white
                            : isError
                                ? const Color(0xFFB91C1C)
                                : _textPri,
                        fontSize: 14,
                        height: 1.5)),
              ),
              if (isError) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _lastQuestion == null
                      ? null
                      : () => _sendMessage(_lastQuestion!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: _blue, borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Retry',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
            ])),
            if (isUser) ...[
              const SizedBox(width: 8),
              Container(
                  width: 32,
                  height: 32,
                  decoration:
                      BoxDecoration(color: _blue, shape: BoxShape.circle),
                  child: const Center(
                      child: Icon(Icons.person_rounded,
                          color: Colors.white, size: 18))),
            ],
          ]),
    );
  }

  Widget _buildTyping() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Center(
                child: Icon(Icons.balance_rounded, color: _blue, size: 16))),
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
            _Dot(400)
          ]),
        ),
      ]),
    );
  }
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
            decoration: const BoxDecoration(
                color: _blue, shape: BoxShape.circle)),
      );
}
