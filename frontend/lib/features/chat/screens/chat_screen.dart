import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../auth/providers/auth_provider.dart';

// Lawyer theme (navy)
const _bgLawyer = Color(0xFFF6F5FB);
const _brownHeader1 = Color(0xFF150E3D);
const _brownHeader2 = Color(0xFF0B0726);

// Client theme (green)
const _bgClient = Color(0xFFF0FAF6);
const _greenHeader1 = Color(0xFF0A4A32);
const _greenHeader2 = Color(0xFF0D6E4F);

// Shared
const _bgCard = Color(0xFFFFFFFF);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1A1A1A);
const _textMuted = Color(0xFF6B6B6B);
const _cream = Color(0xFFEDE9F9);
const _bg = Color(0xFFF6F5FB);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  const ChatScreen({super.key, required this.roomId, required this.roomName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollingTimer;
  late AnimationController _sendCtrl;
  late Animation<double> _sendScale;

  @override
  void initState() {
    super.initState();
    _sendCtrl = AnimationController(
        duration: const Duration(milliseconds: 150), vsync: this);
    _sendScale = Tween<double>(begin: 1.0, end: 0.9).animate(_sendCtrl);
    _loadMessages();
    _pollingTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _loadMessages(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _sendCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res =
          await DioClient.instance.get('/chat/rooms/${widget.roomId}/messages');
      final msgs = res.data['data'] ?? [];
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
        });
        if (msgs.isNotEmpty && !silent) _scrollToBottom();
      }
    } catch (e) {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.lightImpact();
    _sendCtrl.forward().then((_) => _sendCtrl.reverse());
    setState(() => _sending = true);
    _msgCtrl.clear();

    final tempMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'message': text,
      'is_mine': true,
      'sender_name': 'Me',
      'sender_role': 'user',
      'message_type': 'text',
      'is_read': false,
      'is_deleted_by_sender': false,
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() => _messages.add(tempMsg));
    _scrollToBottom();

    try {
      final res = await DioClient.instance.post(
          '/chat/rooms/${widget.roomId}/messages',
          data: {'message': text, 'message_type': 'text'});
      if (res.data['success'] == true) {
        final newMsg = res.data['data'];
        if (mounted)
          setState(() {
            final idx = _messages.indexWhere((m) => m['id'] == tempMsg['id']);
            if (idx != -1) _messages[idx] = {...newMsg, 'is_mine': true};
            _sending = false;
          });
      } else {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempMsg['id']);
          _sending = false;
        });
        _msgCtrl.text = text;
        _showError('Failed to send message');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempMsg['id']);
          _sending = false;
        });
        _msgCtrl.text = text;
        _showError('Could not send. Check connection.');
      }
    }
    _scrollToBottom();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFD9534F),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await DioClient.instance.delete('/chat/messages/$messageId');
      setState(() => _messages.removeWhere((m) => m['id'] == messageId));
      HapticFeedback.lightImpact();
    } catch (e) {
      _showError('Cannot delete this message');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _showDeleteDialog(String messageId) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Delete Message',
                  style:
                      TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
              content: const Text('Delete this message?',
                  style: TextStyle(color: _textMuted)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: _textMuted))),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteMessage(messageId);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD9534F),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Delete',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final myId = auth.user?.id ?? '';
    final role = auth.user?.roleName ?? 'lawyer';
    final isClient = role == 'client';

    // Role-based colors
    final bgColor = isClient ? _bgClient : _bgLawyer;
    final headerColor1 = isClient ? _greenHeader1 : _brownHeader1;
    final headerColor2 = isClient ? _greenHeader2 : _brownHeader2;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: bgColor,
        body: Container(
          child: Column(children: [
            // ── Dynamic Header ──
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [headerColor1, headerColor2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      // Avatar
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                        ),
                        child: Center(
                            child: Text(
                          widget.roomName.isNotEmpty
                              ? widget.roomName[0].toUpperCase()
                              : 'C',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16),
                        )),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(widget.roomName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            Row(children: [
                              Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFF4CAF7D),
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              const Text('Online',
                                  style: TextStyle(
                                      color: Color(0xFF4CAF7D), fontSize: 10)),
                            ]),
                          ])),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white),
                        onPressed: () => _loadMessages(),
                      ),
                    ]),
                  )),
            ),

            // ── Messages Area ──
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: isClient ? const Color(0xFF0D6E4F) : _brown))
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                    color: _brown.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _border)),
                                child: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: _brownLight,
                                    size: 38),
                              ),
                              const SizedBox(height: 16),
                              const Text('No messages yet',
                                  style: TextStyle(
                                      color: _textPri,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              const Text('Say hello! 👋',
                                  style: TextStyle(
                                      color: _textMuted, fontSize: 13)),
                            ]))
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final msg = _messages[i];
                            final isMine = msg['is_mine'] == true ||
                                msg['sender_id'] == myId;
                            final isTemp =
                                (msg['id'] as String).startsWith('temp_');

                            Widget? separator;
                            if (i == 0) {
                              separator =
                                  _DateSeparator(msg['created_at'] ?? '');
                            } else {
                              final prev = _messages[i - 1];
                              final prevDate = (prev['created_at'] ?? '')
                                  .toString()
                                  .substring(0, 10);
                              final currDate = (msg['created_at'] ?? '')
                                  .toString()
                                  .substring(0, 10);
                              if (prevDate != currDate)
                                separator =
                                    _DateSeparator(msg['created_at'] ?? '');
                            }

                            return Column(children: [
                              if (separator != null) separator,
                              _MessageBubble(
                                message: msg,
                                isMine: isMine,
                                isPending: isTemp,
                                onLongPress: isMine && !isTemp
                                    ? () => _showDeleteDialog(msg['id'])
                                    : null,
                              ),
                            ]);
                          },
                        ),
            ),

            // ── Input Bar ──
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: _bgCard,
                border: Border(
                    top: BorderSide(
                        color: isClient ? const Color(0xFFB2DFD0) : _border,
                        width: 0.8)),
                boxShadow: [
                  BoxShadow(
                      color: (isClient ? const Color(0xFF0D6E4F) : _brown)
                          .withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, -3))
                ],
              ),
              child: SafeArea(
                  child: Row(children: [
                // Text input
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isClient ? const Color(0xFFF0FAF6) : _bg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: isClient ? const Color(0xFFB2DFD0) : _border,
                          width: 0.8),
                    ),
                    child: TextField(
                      controller: _msgCtrl,
                      style: const TextStyle(color: _textPri, fontSize: 14),
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: _textMuted, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send button
                ScaleTransition(
                  scale: _sendScale,
                  child: GestureDetector(
                    onTap: _sending ? null : _sendMessage,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: _sending
                            ? null
                            : LinearGradient(
                                colors: isClient
                                    ? [
                                        const Color(0xFF0D6E4F),
                                        const Color(0xFF1A9E72)
                                      ]
                                    : [
                                        const Color(0xFF150E3D),
                                        const Color(0xFF3D2C8D)
                                      ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                        color: _sending ? _cream : null,
                        shape: BoxShape.circle,
                        boxShadow: _sending
                            ? []
                            : [
                                BoxShadow(
                                    color: _brown.withValues(alpha: 0.35),
                                    blurRadius: 8)
                              ],
                      ),
                      child: _sending
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                  color: _brown, strokeWidth: 2))
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ])),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Date Separator ─────────────────────────────────
class _DateSeparator extends StatelessWidget {
  final String dateStr;
  const _DateSeparator(this.dateStr);

  String _label() {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label();
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(child: Divider(color: _border, thickness: 0.7)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border, width: 0.7),
          ),
          child: Text(label,
              style: const TextStyle(color: _textMuted, fontSize: 11)),
        ),
        Expanded(child: Divider(color: _border, thickness: 0.7)),
      ]),
    );
  }
}

// ── Message Bubble ─────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final dynamic message;
  final bool isMine;
  final bool isPending;
  final VoidCallback? onLongPress;
  const _MessageBubble(
      {required this.message,
      required this.isMine,
      this.isPending = false,
      this.onLongPress});

  String _formatTime(String t) {
    try {
      final dt = DateTime.parse(t).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = message['message'] ?? '';
    final isDeleted = message['is_deleted_by_sender'] == true;
    final time = _formatTime(message['created_at']?.toString() ?? '');
    final senderName = message['sender_name'] ?? '';
    final isRead = message['is_read'] == true;

    return Padding(
      padding: EdgeInsets.only(
          bottom: 6, left: isMine ? 48 : 0, right: isMine ? 0 : 48),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Other person avatar
          if (!isMine) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF150E3D), Color(0xFF3D2C8D)]),
                shape: BoxShape.circle,
              ),
              child: Center(
                  child: Text(
                senderName.isNotEmpty ? senderName[0].toUpperCase() : 'C',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              )),
            ),
            const SizedBox(width: 6),
          ],

          // Bubble
          GestureDetector(
            onLongPress: isDeleted ? null : onLongPress,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                // My messages: brown gradient. Theirs: white card
                gradient: isMine
                    ? const LinearGradient(
                        colors: [Color(0xFF150E3D), Color(0xFF3D2C8D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)
                    : null,
                // Note: client sees brown bubbles for their own messages too - same chat_screen
                color: isMine ? null : _bgCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18),
                ),
                border: isMine ? null : Border.all(color: _border, width: 0.8),
                boxShadow: [
                  BoxShadow(
                      color: _brown.withValues(alpha: isMine ? 0.2 : 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(senderName,
                            style: const TextStyle(
                                color: _brownLight,
                                fontSize: 10,
                                fontWeight: FontWeight.w700))),
                  Text(
                    isDeleted ? '🗑 Deleted' : text,
                    style: TextStyle(
                      color: isMine
                          ? Colors.white
                          : isDeleted
                              ? _textMuted
                              : _textPri,
                      fontSize: 14,
                      height: 1.4,
                      fontStyle:
                          isDeleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(time,
                        style: TextStyle(
                            color: isMine
                                ? Colors.white.withValues(alpha: 0.6)
                                : _textMuted,
                            fontSize: 9)),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      isPending
                          ? Icon(Icons.access_time_rounded,
                              color: Colors.white.withValues(alpha: 0.5), size: 11)
                          : Icon(
                              isRead
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              color: isRead
                                  ? const Color(0xFF7EA8C4)
                                  : Colors.white.withValues(alpha: 0.6),
                              size: 11),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
