import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

class PortalMessagesScreen extends StatefulWidget {
  const PortalMessagesScreen({super.key});
  @override
  State<PortalMessagesScreen> createState() => _PortalMessagesScreenState();
}

class _PortalMessagesScreenState extends State<PortalMessagesScreen> {
  List<dynamic> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/chat/rooms');
      setState(() {
        _rooms = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _formatTime(String t) {
    try {
      final dt = DateTime.parse(t).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0)
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (diff.inDays == 1) return 'Yesterday';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Text('Messages',
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
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _rooms.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: Icon(Icons.chat_bubble_rounded,
                                    color: _green, size: 36)),
                            const SizedBox(height: 16),
                            const Text('No Messages Yet',
                                style: TextStyle(
                                    color: _textPri,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text(
                                'Your lawyer will create a chat room when you are onboarded.',
                                style:
                                    TextStyle(color: _textMuted, fontSize: 13),
                                textAlign: TextAlign.center),
                          ]))
                    : RefreshIndicator(
                        color: _green,
                        backgroundColor: _bgCard,
                        onRefresh: _loadRooms,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rooms.length,
                          itemBuilder: (_, i) {
                            final room = _rooms[i];
                            final name = room['room_name'] ??
                                room['other_name'] ??
                                'Lawyer';
                            final lastMsg = room['last_message'] ?? '';
                            final lastTime = room['last_message_at'] ?? '';
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                context
                                    .push(
                                        '/chat/${room['id']}?name=${Uri.encodeComponent(name)}')
                                    .then((_) => _loadRooms());
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                    color: _bgCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border:
                                        Border.all(color: _border, width: 0.8),
                                    boxShadow: [
                                      BoxShadow(
                                          color: _green.withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ]),
                                child: Row(children: [
                                  Container(
                                      width: 48,
                                      height: 48,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(colors: [
                                          Color(0xFF0A4A32),
                                          Color(0xFF1A9E72)
                                        ]),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                          child: Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : 'L',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 18)))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(name,
                                            style: const TextStyle(
                                                color: _textPri,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                        const SizedBox(height: 2),
                                        Text(
                                            lastMsg.isEmpty
                                                ? 'Start a conversation'
                                                : lastMsg,
                                            style: TextStyle(
                                                color: lastMsg.isEmpty
                                                    ? _textMuted
                                                    : _textMuted,
                                                fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ])),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (lastTime.isNotEmpty)
                                          Text(_formatTime(lastTime),
                                              style: const TextStyle(
                                                  color: _textMuted,
                                                  fontSize: 10)),
                                        const SizedBox(height: 4),
                                        const Icon(Icons.chevron_right_rounded,
                                            color: _textMuted, size: 20),
                                      ]),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}
