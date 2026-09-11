import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/realtime_events.dart';
import '../../../core/utils/file_opener.dart';
import '../../auth/providers/auth_provider.dart';

// The backend's maxInlineChatFileBytes (chat_controller.go) caps the
// *base64-encoded* string at 8MB, and base64 inflates size by ~4/3 — so the
// raw-byte cap here has to be 6MB, not 8MB, or a file between 6-8MB passes
// this check and still gets rejected by the server as "too large" once
// encoded (same calibration document_upload_sheet.dart already uses).
const _maxAttachmentBytes = 6 * 1024 * 1024;
const _allowedDocExtensions = [
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'
];

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

/// Local-only state for an attachment upload in flight — never persisted,
/// just enough to render a spinner or a Retry action on that one bubble.
class _PendingAttachment {
  final Uint8List bytes;
  final bool uploading;
  final bool failed;
  const _PendingAttachment(
      {required this.bytes, required this.uploading, required this.failed});
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

  // Real presence — replaces the previous hardcoded "Online" text. Polled
  // alongside messages so it stays fresh without a second network timer.
  bool? _peerOnline;
  DateTime? _peerLastSeen;

  // In-flight/failed attachment uploads, keyed by the temp message id, so a
  // failed upload can show a Retry action on that specific bubble instead of
  // silently vanishing or blocking the whole thread.
  final Map<String, _PendingAttachment> _pendingAttachments = {};

  @override
  void initState() {
    super.initState();
    _sendCtrl = AnimationController(
        duration: const Duration(milliseconds: 150), vsync: this);
    _sendScale = Tween<double>(begin: 1.0, end: 0.9).animate(_sendCtrl);
    _loadMessages();
    _loadPresence();
    // The 3s poll below is a safety net only now — a new message already
    // pushes a real notification the instant it's sent (see
    // notifyOtherChatParticipants on the backend), so this listener is what
    // makes the thread actually update immediately instead of waiting for
    // the next poll tick.
    RealtimeEvents.instance.addListener(_onRealtimeEvent);
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadMessages(silent: true);
      _loadPresence();
    });
  }

  void _onRealtimeEvent() {
    if (RealtimeEvents.instance.lastType == 'chat_message') {
      _loadMessages(silent: true);
    }
  }

  @override
  void dispose() {
    RealtimeEvents.instance.removeListener(_onRealtimeEvent);
    _pollingTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _sendCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPresence() async {
    try {
      final res =
          await DioClient.instance.get('/chat/rooms/${widget.roomId}/presence');
      final data = res.data['data'];
      if (!mounted || data == null) return;
      setState(() {
        _peerOnline = data['online'] == true;
        final lastSeen = data['last_seen'];
        _peerLastSeen =
            lastSeen != null ? DateTime.tryParse(lastSeen.toString()) : null;
      });
    } catch (_) {
      // Presence is a nice-to-have overlay on the chat, not a hard
      // dependency — a failed poll just leaves the last-known state showing
      // rather than erroring or blocking the message list.
    }
  }

  String _presenceLabel() {
    if (_peerOnline == null) return '';
    if (_peerOnline == true) return 'Online';
    if (_peerLastSeen == null) return 'Offline';
    final diff = DateTime.now().difference(_peerLastSeen!.toLocal());
    if (diff.inMinutes < 1) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    return 'Last seen ${diff.inDays}d ago';
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

  void _showAttachmentOptions() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: _border, borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.image_rounded,
                      color: Color(0xFF4A90D9))),
              title: const Text('Photo',
                  style: TextStyle(color: _textPri, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendPhoto();
              },
            ),
            ListTile(
              leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: _brown.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.description_rounded, color: _brown)),
              title: const Text('Document',
                  style: TextStyle(color: _textPri, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendDocument();
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickAndSendPhoto() async {
    final XFile? picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxAttachmentBytes) {
      _showError('Photo is too large. Max size is 8 MB.');
      return;
    }
    if (!mounted) return;
    // Preview before sending, per spec — a lightweight confirm dialog rather
    // than a full editor screen, matching this app's existing dialog style.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send this photo?',
            style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, fit: BoxFit.contain, height: 220),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _brown),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
    _sendAttachment(
      bytes: bytes,
      fileName: picked.name.isNotEmpty ? picked.name : 'photo.$ext',
      mimeType: 'image/$ext',
      messageType: 'image',
    );
  }

  Future<void> _pickAndSendDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedDocExtensions,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    if (file.size > _maxAttachmentBytes) {
      _showError('File is too large. Max size is 8 MB.');
      return;
    }
    _sendAttachment(
      bytes: file.bytes!,
      fileName: file.name,
      mimeType: _mimeTypeForExtension(file.extension ?? ''),
      messageType: 'file',
    );
  }

  String _mimeTypeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt': return 'text/plain';
      case 'csv': return 'text/csv';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _sendAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String messageType,
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = {
      'id': tempId,
      'message': '',
      'is_mine': true,
      'sender_name': 'Me',
      'sender_role': 'user',
      'message_type': messageType,
      'file_name': fileName,
      'mime_type': mimeType,
      'has_file': true,
      'is_read': false,
      'is_deleted_by_sender': false,
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() {
      _messages.add(tempMsg);
      _pendingAttachments[tempId] =
          _PendingAttachment(bytes: bytes, uploading: true, failed: false);
    });
    _scrollToBottom();
    await _uploadAttachment(tempId, tempMsg, bytes, fileName, mimeType, messageType);
  }

  Future<void> _uploadAttachment(String tempId, Map tempMsg, Uint8List bytes,
      String fileName, String mimeType, String messageType) async {
    setState(() => _pendingAttachments[tempId] =
        _PendingAttachment(bytes: bytes, uploading: true, failed: false));
    try {
      final res = await DioClient.instance.post(
          '/chat/rooms/${widget.roomId}/messages',
          data: {
            'message': '',
            'message_type': messageType,
            'file_name': fileName,
            'mime_type': mimeType,
            'file_content': base64Encode(bytes),
          });
      if (!mounted) return;
      if (res.data['success'] == true) {
        final newMsg = res.data['data'];
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) _messages[idx] = {...newMsg, 'is_mine': true};
          _pendingAttachments.remove(tempId);
          // The just-sent bytes are cached locally so the sender's own
          // bubble can render an image immediately without a round trip
          // back to the server it just uploaded to.
          if (newMsg['id'] != null) {
            _fileCache[newMsg['id'].toString()] = bytes;
          }
        });
      } else {
        setState(() => _pendingAttachments[tempId] =
            _PendingAttachment(bytes: bytes, uploading: false, failed: true));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAttachments[tempId] =
          _PendingAttachment(bytes: bytes, uploading: false, failed: true));
      // The bubble already shows a Retry action for "failed", but that alone
      // doesn't say *why* — a 413 (too large) and a dropped connection look
      // identical without this, so a user just sees "upload not working"
      // with no way to tell whether retrying will ever help.
      _showError('Attachment failed: ${DioClient.describeError(e)}');
    }
  }

  void _retryAttachment(String tempId) {
    final msg = _messages.firstWhere((m) => m['id'] == tempId, orElse: () => null);
    final pending = _pendingAttachments[tempId];
    if (msg == null || pending == null) return;
    _uploadAttachment(tempId, msg, pending.bytes,
        (msg['file_name'] ?? 'file').toString(),
        (msg['mime_type'] ?? '').toString(),
        (msg['message_type'] ?? 'file').toString());
  }

  void _removeFailedAttachment(String tempId) {
    setState(() {
      _messages.removeWhere((m) => m['id'] == tempId);
      _pendingAttachments.remove(tempId);
    });
  }

  // Fetched attachment bytes, keyed by real message id — avoids re-fetching
  // an image every time the 3s poll rebuilds the message list.
  final Map<String, Uint8List> _fileCache = {};

  Future<Uint8List?> _fetchAttachment(String messageId) async {
    if (_fileCache.containsKey(messageId)) return _fileCache[messageId];
    try {
      final res =
          await DioClient.instance.get('/chat/messages/$messageId/file');
      final b64 = res.data['data']?['file_content'] as String?;
      if (b64 == null) return null;
      final bytes = base64Decode(b64);
      _fileCache[messageId] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAttachment(Map message) async {
    final id = message['id'].toString();
    final fileName = (message['file_name'] ?? 'document').toString();
    final mimeType = (message['mime_type'] ?? '').toString().isNotEmpty
        ? message['mime_type'].toString()
        : 'application/octet-stream';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Opening $fileName...'),
        duration: const Duration(seconds: 1),
        backgroundColor: _brown,
        behavior: SnackBarBehavior.floating));
    final bytes = await _fetchAttachment(id);
    if (!mounted) return;
    if (bytes == null) {
      _showError('Could not load this attachment.');
      return;
    }
    final result = await openDocumentBytes(
        bytes: bytes, fileName: fileName, mimeType: mimeType);
    if (!mounted) return;
    if (!result.success) {
      _showError(result.message ?? 'Could not open this file.');
    }
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
                            if (_presenceLabel().isNotEmpty)
                              Row(children: [
                                Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                        color: _peerOnline == true
                                            ? const Color(0xFF4CAF7D)
                                            : Colors.white38,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 4),
                                Text(_presenceLabel(),
                                    style: TextStyle(
                                        color: _peerOnline == true
                                            ? const Color(0xFF4CAF7D)
                                            : Colors.white60,
                                        fontSize: 10)),
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
                                pending: isTemp ? _pendingAttachments[msg['id']] : null,
                                onLongPress: isMine && !isTemp
                                    ? () => _showDeleteDialog(msg['id'])
                                    : null,
                                onRetryAttachment: isTemp
                                    ? () => _retryAttachment(msg['id'])
                                    : null,
                                onRemoveFailedAttachment: isTemp
                                    ? () => _removeFailedAttachment(msg['id'])
                                    : null,
                                onOpenAttachment: () => _openAttachment(msg),
                                fetchImageBytes: () => _fetchAttachment(msg['id'].toString()),
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
                // Attachment button
                GestureDetector(
                  onTap: _showAttachmentOptions,
                  child: Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isClient ? const Color(0xFFF0FAF6) : _bg,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isClient ? const Color(0xFFB2DFD0) : _border,
                          width: 0.8),
                    ),
                    child: Icon(Icons.add_rounded,
                        color: isClient ? const Color(0xFF0D6E4F) : _brown),
                  ),
                ),
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
                        filled: false,
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
  final _PendingAttachment? pending;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetryAttachment;
  final VoidCallback? onRemoveFailedAttachment;
  final VoidCallback onOpenAttachment;
  final Future<Uint8List?> Function() fetchImageBytes;
  const _MessageBubble(
      {required this.message,
      required this.isMine,
      this.isPending = false,
      this.pending,
      this.onLongPress,
      this.onRetryAttachment,
      this.onRemoveFailedAttachment,
      required this.onOpenAttachment,
      required this.fetchImageBytes});

  String _formatTime(String t) {
    try {
      final dt = DateTime.parse(t).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  bool get _hasAttachment {
    final type = (message['message_type'] ?? 'text').toString();
    return (type == 'image' || type == 'file') &&
        (message['has_file'] == true || pending != null);
  }

  Widget _buildAttachment(BuildContext context, bool isMine) {
    if (!_hasAttachment) return const SizedBox.shrink();
    final isImage = (message['message_type'] ?? '') == 'image';
    final fileName = (message['file_name'] ?? 'Attachment').toString();

    // A failed upload shows the local bytes with a Retry action — the
    // message never silently vanishes, and never looks like it sent when it
    // didn't.
    if (pending != null && pending!.failed) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xFFD9534F).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFD9534F), size: 16),
            const SizedBox(width: 6),
            Expanded(
                child: Text('Upload failed: $fileName',
                    style: const TextStyle(
                        color: Color(0xFFD9534F), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            TextButton(
              onPressed: onRetryAttachment,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Retry',
                  style: TextStyle(
                      color: Color(0xFFD9534F), fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: onRemoveFailedAttachment,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text('Remove',
                  style: TextStyle(color: isMine ? Colors.white70 : _textMuted)),
            ),
          ]),
        ]),
      );
    }

    if (pending != null && pending!.uploading) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isMine ? Colors.white : _brown)),
          const SizedBox(width: 8),
          Flexible(
              child: Text('Uploading $fileName...',
                  style: TextStyle(
                      color: isMine ? Colors.white : _textPri, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ]),
      );
    }

    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: onOpenAttachment,
          child: pending != null
              ? Image.memory(pending!.bytes,
                  width: 200, height: 200, fit: BoxFit.cover)
              : FutureBuilder<Uint8List?>(
                  future: fetchImageBytes(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Container(
                          width: 200,
                          height: 200,
                          color: Colors.black.withValues(alpha: 0.05),
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    if (snapshot.data == null) {
                      return Container(
                        width: 200,
                        height: 120,
                        color: Colors.black.withValues(alpha: 0.05),
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_rounded,
                            color: _textMuted),
                      );
                    }
                    return Image.memory(snapshot.data!,
                        width: 200, height: 200, fit: BoxFit.cover);
                  },
                ),
        ),
      );
    }

    // Document attachment — icon + name, tap to open via the shared
    // file-opener (same one Documents uses).
    return GestureDetector(
      onTap: onOpenAttachment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withValues(alpha: 0.12)
              : _brown.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insert_drive_file_rounded,
              color: isMine ? Colors.white : _brown, size: 20),
          const SizedBox(width: 8),
          Flexible(
              child: Text(fileName,
                  style: TextStyle(
                      color: isMine ? Colors.white : _textPri,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Icon(Icons.download_rounded,
              color: isMine ? Colors.white70 : _textMuted, size: 16),
        ]),
      ),
    );
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
                  if (!isDeleted) _buildAttachment(context, isMine),
                  if (!isDeleted && text.toString().trim().isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                          top: _hasAttachment ? 6 : 0),
                      child: Text(
                        text,
                        style: TextStyle(
                          color: isMine ? Colors.white : _textPri,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (isDeleted)
                    Text(
                      '🗑 Deleted',
                      style: TextStyle(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.85)
                            : _textMuted,
                        fontSize: 14,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
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
