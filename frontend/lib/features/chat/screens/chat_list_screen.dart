import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<dynamic> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      if (now.difference(dt).inDays == 0) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
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
        body: Container(
          child: Column(children: [
            // Header
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF0B0726), Color(0xFF150E3D)],
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
                      IconButton(
                        icon: const Icon(Icons.edit_rounded,
                            color: Color(0xFFFFD700)),
                        onPressed: () {},
                      ),
                    ]),
                  )),
            ),

            // List
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _brown))
                  : _rooms.isEmpty
                      ? _EmptyChats()
                      : RefreshIndicator(
                          color: _brown,
                          backgroundColor: _bgCard,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                            itemCount: _rooms.length,
                            itemBuilder: (_, i) {
                              final room = _rooms[i];
                              final name = room['other_name'] ??
                                  room['lawyer_name'] ??
                                  'Client';
                              final lastMsg =
                                  room['last_message'] ?? 'No messages yet';
                              final time =
                                  _formatTime(room['last_message_at'] ?? '');
                              final unread = room['unread_count'] ?? 0;
                              final initials =
                                  name.isNotEmpty ? name[0].toUpperCase() : 'C';

                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  context.push(
                                      '/chat/${room["id"]}?name=${Uri.encodeComponent(name)}');
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _bgCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border:
                                        Border.all(color: _border, width: 0.8),
                                    boxShadow: [
                                      BoxShadow(
                                          color: _brown.withValues(alpha: 0.07),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3))
                                    ],
                                  ),
                                  child: Row(children: [
                                    // Avatar
                                    Stack(children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF150E3D),
                                                Color(0xFF3D2C8D)
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                            child: Text(initials,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 18))),
                                      ),
                                      Positioned(
                                          bottom: 1,
                                          right: 1,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                                color: const Color(0xFF2E8B57),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: _bgCard, width: 2)),
                                          )),
                                    ]),
                                    const SizedBox(width: 12),
                                    // Info
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(name,
                                              style: const TextStyle(
                                                  color: _textPri,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15)),
                                          const SizedBox(height: 3),
                                          Text(lastMsg,
                                              style: const TextStyle(
                                                  color: _textMuted,
                                                  fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ])),
                                    const SizedBox(width: 8),
                                    // Time + badge
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(time,
                                              style: const TextStyle(
                                                  color: _textMuted,
                                                  fontSize: 11)),
                                          const SizedBox(height: 5),
                                          if (unread > 0)
                                            Container(
                                              width: 20,
                                              height: 20,
                                              decoration: const BoxDecoration(
                                                  color: _brown,
                                                  shape: BoxShape.circle),
                                              child: Center(
                                                  child: Text('$unread',
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight
                                                              .w700))),
                                            ),
                                        ]),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ]),
        ), // Container
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: _brown,
          child: const Icon(Icons.edit_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: _brown.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: _border)),
          child: const Icon(Icons.chat_bubble_outline_rounded,
              color: _brownLight, size: 38),
        ),
        const SizedBox(height: 16),
        const Text('No messages yet',
            style: TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('Start a conversation with your clients',
            style: TextStyle(color: _textMuted, fontSize: 13)),
      ]));
}
