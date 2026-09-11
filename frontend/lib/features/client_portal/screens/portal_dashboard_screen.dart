import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/realtime_events.dart';
import '../../auth/providers/auth_provider.dart';

// Same allow-list/format helpers used by the dedicated My Documents screen
// (portal_documents_screen.dart) — duplicated here (Dart privacy is
// per-file) since this dashboard tab has its own, separate upload sheet.
const Map<String, List<String>> _dashAllowedExtByType = {
  'Document': ['doc', 'docx', 'txt'],
  'PDF': ['pdf'],
  'Photo': ['jpg', 'jpeg', 'png', 'webp'],
  'Video': ['mp4', 'mov', 'avi', 'mkv', 'webm'],
  'Other': [
    'pdf', 'doc', 'docx', 'txt',
    'jpg', 'jpeg', 'png', 'webp',
    'mp4', 'mov', 'avi', 'mkv', 'webm',
    'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'zip',
  ],
};

const int _dashMaxUploadFileBytes = 6 * 1024 * 1024;

const Map<String, String> _dashExtToMime = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'txt': 'text/plain',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'csv': 'text/csv',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'zip': 'application/zip',
};

String _dashExtOf(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i == -1 || i == fileName.length - 1) return '';
  return fileName.substring(i + 1).toLowerCase();
}

String _dashFormatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// Normalizes whatever the backend sends in `consultation_type` — the booking
// screen currently sends "Audio Call" / "Video Call" / "Chat" / "Office
// Visit", but this also accepts snake_case/lowercase variants ("audio_call",
// "video") without needing an API change, so the right action always renders
// instead of every consultation defaulting to chat.
String _consultationAction(String rawType) {
  final t = rawType.toLowerCase();
  if (t.contains('audio')) return 'audio';
  if (t.contains('video')) return 'video';
  if (t.contains('chat')) return 'chat';
  return 'chat'; // Office Visit and anything unrecognized keep the prior chat fallback.
}

// ── Green/White Theme Colors ───────────────────────
const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _teal = Color(0xFF06B6D4);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

class PortalDashboardScreen extends StatefulWidget {
  const PortalDashboardScreen({super.key});
  @override
  State<PortalDashboardScreen> createState() => _PortalDashboardScreenState();
}

class _PortalDashboardScreenState extends State<PortalDashboardScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  List<dynamic> _cases = [];
  List<dynamic> _hearings = [];
  List<dynamic> _invoices = [];
  List<dynamic> _chatRooms = [];
  List<dynamic> _documents = [];
  List<dynamic> _consultations = [];
  bool _loading = true;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this)
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
    // The lawyer accepting/rejecting, starting a session, or a payment/
    // document update all already push a notification (see
    // utils.NotifyWithRef on the backend) — this refreshes the same data
    // this screen already loads on open, the instant one of those arrives,
    // instead of only on the next manual pull-to-refresh.
    RealtimeEvents.instance.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent() {
    if (RealtimeEvents.instance.matches([
      'booking_', 'incoming_call_', 'chat_session_started', 'call_response_',
    ])) {
      _loadData();
    }
  }

  @override
  void dispose() {
    RealtimeEvents.instance.removeListener(_onRealtimeEvent);
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DioClient.instance.get('/portal/my-cases'),
        DioClient.instance.get('/portal/my-hearings'),
        DioClient.instance.get('/portal/my-invoices'),
        DioClient.instance.get('/chat/rooms'),
        DioClient.instance.get('/portal/my-documents'),
        DioClient.instance.get('/portal/my-consultations'),
      ]);
      setState(() {
        _cases = results[0].data['data'] ?? [];
        _hearings = results[1].data['data'] ?? [];
        _invoices = results[2].data['data'] ?? [];
        _chatRooms = results[3].data['data'] ?? [];
        _documents = results[4].data['data'] ?? [];
        _consultations = results[5].data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final screens = [
      _HomeTab(
          cases: _cases,
          hearings: _hearings,
          invoices: _invoices,
          consultations: _consultations,
          auth: auth,
          fadeAnim: _fadeAnim,
          onRefresh: _loadData,
          onTabChange: (i) => setState(() => _selectedIndex = i)),
      _CasesTab(cases: _cases, documents: _documents),
      _DocumentsTab(documents: _documents, cases: _cases, onRefresh: _loadData),
      _BillingTab(invoices: _invoices),
      _ChatTab(chatRooms: _chatRooms, auth: auth),
      _ProfileTab(auth: auth),
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _loading ? _buildLoading() : screens[_selectedIndex],
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: _selectedIndex,
        onTap: (i) {
          HapticFeedback.lightImpact();
          setState(() => _selectedIndex = i);
        },
      ),
    );
  }

  Widget _buildLoading() => Container(
        color: _bg,
        child: const Center(child: CircularProgressIndicator(color: _green)),
      );
}

// ── Bottom Nav ─────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;
  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.gavel_rounded, 'label': 'Cases'},
      {'icon': Icons.folder_rounded, 'label': 'Docs'},
      {'icon': Icons.receipt_long_rounded, 'label': 'Bills'},
      {'icon': Icons.chat_rounded, 'label': 'Chat'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        border: Border(top: BorderSide(color: _border, width: 0.8)),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: SafeArea(
          child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items.asMap().entries.map((e) {
            final sel = selectedIndex == e.key;
            return GestureDetector(
              onTap: () => onTap(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: sel ? _green.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(e.value['icon'] as IconData,
                      color: sel ? _green : _textMuted, size: 22),
                  const SizedBox(height: 2),
                  Text(e.value['label'] as String,
                      style: TextStyle(
                          color: sel ? _green : _textMuted,
                          fontSize: 9,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                ]),
              ),
            );
          }).toList(),
        ),
      )),
    );
  }
}

// ── Home Tab ───────────────────────────────────────
class _HomeTab extends StatelessWidget {
  final List<dynamic> cases, hearings, invoices, consultations;
  final AuthProvider auth;
  final Animation<double> fadeAnim;
  final VoidCallback onRefresh;
  final Function(int) onTabChange;
  const _HomeTab(
      {required this.cases,
      required this.hearings,
      required this.invoices,
      required this.consultations,
      required this.auth,
      required this.fadeAnim,
      required this.onRefresh,
      required this.onTabChange});

  void _showAllHearings(BuildContext context, List<dynamic> hearings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, ctrl) {
          final now = DateTime.now();
          final todayStr =
              '${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}';
          final today = hearings
              .where((h) =>
                  (h['hearing_date'] ?? '').toString().substring(0, 10) ==
                  todayStr)
              .toList();
          final upcoming = hearings
              .where((h) =>
                  (h['hearing_date'] ?? '')
                      .toString()
                      .substring(0, 10)
                      .compareTo(todayStr) >
                  0)
              .toList();
          final past = hearings
              .where((h) =>
                  (h['hearing_date'] ?? '')
                      .toString()
                      .substring(0, 10)
                      .compareTo(todayStr) <
                  0)
              .toList();

          return ListView(
              controller: ctrl,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: const Color(0xFFB2DFD0),
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Text('All Hearings',
                    style: TextStyle(
                        color: Color(0xFF0A2E1F),
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                if (today.isNotEmpty) ...[
                  _HearingSection('📅 Today', today, const Color(0xFF0D6E4F)),
                  const SizedBox(height: 16),
                ],
                if (upcoming.isNotEmpty) ...[
                  _HearingSection(
                      '⏰ Upcoming', upcoming, const Color(0xFF4A90D9)),
                  const SizedBox(height: 16),
                ],
                if (past.isNotEmpty) ...[
                  _HearingSection(
                      '🕐 Past Hearings', past, const Color(0xFF8B5E3C)),
                ],
                if (hearings.isEmpty)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Text('No hearings yet',
                              style: TextStyle(color: Color(0xFF4A7A63))))),
                const SizedBox(height: 40),
              ]);
        },
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final activeCases = cases.where((c) => c['status'] == 'active').length;
    final wonCases = cases.where((c) => c['status'] == 'won').length;
    final pendingInvoices = invoices
        .where((i) =>
            i['status'] == 'pending' || i['status'] == 'pending_verification')
        .length;
    final upcomingHearings =
        hearings.where((h) => h['status'] == 'scheduled').length;

    return FadeTransition(
      opacity: fadeAnim,
      child: RefreshIndicator(
        color: _green,
        onRefresh: () async => onRefresh(),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
              child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0A4A32),
                  Color(0xFF0D6E4F),
                  Color(0xFF1A9E72)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4), width: 2),
                        ),
                        child: Center(
                            child: Text(auth.user?.initials ?? 'C',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('${_greeting()},',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12)),
                            Text(auth.user?.name ?? 'Client',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                          ])),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        child: const Text('CLIENT',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11)),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      _StatChip(
                          '$activeCases', 'Active', const Color(0xFF4CAF7D)),
                      const SizedBox(width: 8),
                      _StatChip('$wonCases', 'Won', const Color(0xFFFFD700)),
                      const SizedBox(width: 8),
                      _StatChip('$upcomingHearings', 'Hearings', Colors.white),
                      const SizedBox(width: 8),
                      _StatChip(
                          '$pendingInvoices', 'Bills', const Color(0xFFFFB347)),
                    ]),
                  ]),
            )),
          )),
          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _QuickBtn(
                    Icons.gavel_rounded, 'Cases', _green, () => onTabChange(1)),
                const SizedBox(width: 10),
                _QuickBtn(Icons.folder_rounded, 'Documents', _teal,
                    () => onTabChange(2)),
                const SizedBox(width: 10),
                _QuickBtn(Icons.receipt_long_rounded, 'Billing',
                    const Color(0xFF2E8B57), () => onTabChange(3)),
                const SizedBox(width: 10),
                _QuickBtn(Icons.chat_rounded, 'Chat', const Color(0xFF7C3AED),
                    () => onTabChange(4)),
              ]),
              const SizedBox(height: 12),
              // Find Lawyer banner
              GestureDetector(
                onTap: () => context.push('/portal/find-lawyer'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF0A4A32), Color(0xFF1A9E72)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: _green.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(children: [
                    Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.search_rounded,
                            color: Colors.white, size: 26)),
                    const SizedBox(width: 14),
                    const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Find a Lawyer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          Text('Search by practice area, city & more',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('Search',
                          style: TextStyle(
                              color: _green,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              if (hearings.isNotEmpty) ...[
                _SectionHeader('📅 Upcoming Hearings',
                    onSeeAll: () => _showAllHearings(context, hearings)),
                const SizedBox(height: 10),
                ...hearings.take(2).map((h) => _HearingCard(
                    hearing: h,
                    onTap: () => _showAllHearings(context, hearings))),
                const SizedBox(height: 20),
              ],
              // ── My Consultations ──────────────────
              if (consultations.isNotEmpty) ...[
                _SectionHeader('📅 My Consultations', onSeeAll: null),
                const SizedBox(height: 10),
                ...consultations.take(3).map((c) => _ConsultationCard(
                      consultation: c,
                      context: context,
                    )),
                const SizedBox(height: 20),
              ],
              if (cases.isNotEmpty) ...[
                _SectionHeader('⚖️ My Cases', onSeeAll: () => onTabChange(1)),
                const SizedBox(height: 10),
                ...cases.take(3).map((c) => _CaseCard(
                    caseData: c, onTap: () => context.push('/portal/cases'))),
                const SizedBox(height: 20),
              ],
              if (invoices.any((i) => i['status'] == 'pending')) ...[
                _SectionHeader('💰 Pending Bills',
                    onSeeAll: () => onTabChange(3)),
                const SizedBox(height: 10),
                ...invoices
                    .where((i) => i['status'] == 'pending')
                    .take(2)
                    .map((inv) => _InvoiceCard(invoice: inv)),
              ],
              const SizedBox(height: 80),
            ]),
          )),
        ]),
      ),
    );
  }
}

// ── Cases Tab ──────────────────────────────────────
class _CasesTab extends StatelessWidget {
  final List<dynamic> cases, documents;
  const _CasesTab({required this.cases, required this.documents});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  const Text('My Cases',
                      style: TextStyle(
                          color: _textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('${cases.length} cases',
                        style: const TextStyle(
                            color: _green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              Expanded(
                child: cases.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Icon(Icons.gavel_rounded,
                                color: _green.withValues(alpha: 0.3), size: 64),
                            const SizedBox(height: 12),
                            const Text('No cases yet',
                                style:
                                    TextStyle(color: _textMuted, fontSize: 16)),
                          ]))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: cases.length,
                        itemBuilder: (_, i) {
                          final c = cases[i];
                          final caseDocs = documents
                              .where((d) => d['case_id'] == c['id'])
                              .toList();
                          return _CaseCard(
                              caseData: c,
                              docCount: caseDocs.length,
                              onTap: () => context.push('/portal/cases'));
                        }),
              ),
            ]), // Column
          ), // SafeArea
        ]), // Stack
      );
}

// ── Documents Tab ──────────────────────────────────
class _DocumentsTab extends StatefulWidget {
  final List<dynamic> documents, cases;
  final VoidCallback onRefresh;
  const _DocumentsTab(
      {required this.documents, required this.cases, required this.onRefresh});
  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  bool _uploading = false;
  String? _selectedCaseId;
  double _uploadProgress = 0;

  IconData _icon(String? type, String? name) {
    final t = (type ?? '').toLowerCase();
    final n = (name ?? '').toLowerCase();
    if (t.contains('pdf') || n.endsWith('.pdf'))
      return Icons.picture_as_pdf_rounded;
    if (t.contains('image') || n.endsWith('.jpg') || n.endsWith('.png'))
      return Icons.image_rounded;
    if (t.contains('video') || n.endsWith('.mp4'))
      return Icons.videocam_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _color(String? type, String? name) {
    final t = (type ?? '').toLowerCase();
    final n = (name ?? '').toLowerCase();
    if (t.contains('pdf') || n.endsWith('.pdf')) return const Color(0xFFD9534F);
    if (t.contains('image') || n.endsWith('.jpg') || n.endsWith('.png'))
      return _teal;
    if (t.contains('video') || n.endsWith('.mp4'))
      return const Color(0xFF7C3AED);
    return _green;
  }

  void _showUploadDialog() {
    final nameCtrl = TextEditingController();
    String selectedType = 'Document';
    String selectedCategory = 'General';
    PlatformFile? pickedFile;
    bool picking = false;
    final types = ['Document', 'PDF', 'Photo', 'Video', 'Other'];
    final categories = [
      'General',
      'Court Order',
      'Petition',
      'Agreement',
      'Evidence',
      'Identity Proof',
      'Other'
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) {
            Future<void> pickFile() async {
              setS(() => picking = true);
              try {
                final allowed =
                    _dashAllowedExtByType[selectedType] ?? const <String>[];
                final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: allowed,
                    withData: true);
                if (result == null || result.files.isEmpty) return;
                final f = result.files.single;
                final ext = _dashExtOf(f.name);
                if (!allowed.contains(ext)) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(
                            'Unsupported file type for $selectedType. Allowed: ${allowed.join(', ').toUpperCase()}'),
                        backgroundColor: const Color(0xFFD9534F)));
                  return;
                }
                if (f.size > _dashMaxUploadFileBytes) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content:
                            Text('File is too large. Maximum size is 6 MB.'),
                        backgroundColor: Color(0xFFD9534F)));
                  return;
                }
                if (f.bytes == null) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text(
                            'Could not read the selected file. Please try again.'),
                        backgroundColor: Color(0xFFD9534F)));
                  return;
                }
                setS(() => pickedFile = f);
              } finally {
                setS(() => picking = false);
              }
            }

            return Padding(
                padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: _border,
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 16),
                      Row(children: [
                        Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                                color: _green,
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.upload_rounded,
                                color: Colors.white, size: 20)),
                        const SizedBox(width: 12),
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Upload Document',
                                  style: TextStyle(
                                      color: _textPri,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              Text('Select a file from your device',
                                  style: TextStyle(
                                      color: _textMuted, fontSize: 12)),
                            ]),
                      ]),
                      const SizedBox(height: 16),
                      if (widget.cases.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border, width: 0.8)),
                          child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                            value: _selectedCaseId,
                            hint: const Text('Select Case (optional)',
                                style:
                                    TextStyle(color: _textMuted, fontSize: 13)),
                            dropdownColor: _bgCard,
                            style: const TextStyle(color: _textPri),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                color: _green),
                            isExpanded: true,
                            items: widget.cases
                                .map<DropdownMenuItem<String>>((c) =>
                                    DropdownMenuItem(
                                        value: c['id'],
                                        child: Text(c['case_title'] ?? 'Case',
                                            style:
                                                const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) => setS(() => _selectedCaseId = v),
                          )),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                          height: 50,
                          child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: types.map((t) {
                                final sel = selectedType == t;
                                return GestureDetector(
                                  onTap: () => setS(() {
                                    selectedType = t;
                                    pickedFile = null;
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color:
                                          sel ? _green.withValues(alpha: 0.12) : _bg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: sel ? _green : _border,
                                          width: sel ? 2 : 1),
                                    ),
                                    child: Text(t,
                                        style: TextStyle(
                                            color: sel ? _green : _textMuted,
                                            fontWeight: sel
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            fontSize: 12)),
                                  ),
                                );
                              }).toList())),
                      const SizedBox(height: 12),
                      _sheetField(nameCtrl, 'Document Name *',
                          Icons.drive_file_rename_outline_rounded),
                      const SizedBox(height: 12),
                      pickedFile == null
                          ? _DashPickFileButton(
                              loading: picking,
                              allowedExt:
                                  _dashAllowedExtByType[selectedType] ??
                                      const [],
                              onTap: picking ? null : pickFile,
                            )
                          : _DashPickedFilePreview(
                              file: pickedFile!,
                              onRemove: () => setS(() => pickedFile = null),
                              onChange: pickFile,
                            ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border, width: 0.8)),
                        child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                          value: selectedCategory,
                          dropdownColor: _bgCard,
                          style: const TextStyle(color: _textPri),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: _green),
                          isExpanded: true,
                          items: categories
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) => setS(() => selectedCategory = v!),
                        )),
                      ),
                      if (_uploading) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                              value:
                                  _uploadProgress > 0 ? _uploadProgress : null,
                              backgroundColor: _border,
                              color: _green,
                              minHeight: 6),
                        ),
                        const SizedBox(height: 6),
                        Text(
                            _uploadProgress > 0
                                ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                                : 'Uploading...',
                            style:
                                const TextStyle(color: _textMuted, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _uploading
                              ? null
                              : () async {
                                  if (nameCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Please enter document name'),
                                            backgroundColor:
                                                Color(0xFFD9534F)));
                                    return;
                                  }
                                  final file = pickedFile;
                                  if (file == null || file.bytes == null) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Please select a file to upload'),
                                            backgroundColor:
                                                Color(0xFFD9534F)));
                                    return;
                                  }
                                  setS(() {
                                    _uploading = true;
                                    _uploadProgress = 0;
                                  });
                                  try {
                                    final ext = _dashExtOf(file.name);
                                    final title = nameCtrl.text.trim();
                                    final storedName = ext.isNotEmpty &&
                                            !title
                                                .toLowerCase()
                                                .endsWith('.$ext')
                                        ? '$title.$ext'
                                        : title;
                                    await DioClient.instance.post(
                                        '/portal/documents/upload',
                                        data: {
                                          'file_name': storedName,
                                          'file_content':
                                              base64Encode(file.bytes!),
                                          'file_type': ext.isNotEmpty
                                              ? ext
                                              : selectedType.toLowerCase(),
                                          'file_size': file.size,
                                          'mime_type':
                                              _dashExtToMime[ext] ??
                                                  'application/octet-stream',
                                          'category': selectedCategory,
                                          'case_id': _selectedCaseId ?? '',
                                          'description': 'Uploaded by client',
                                        },
                                        onSendProgress: (sent, total) {
                                      if (total > 0)
                                        setS(() =>
                                            _uploadProgress = sent / total);
                                    });
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    widget.onRefresh();
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Document uploaded! Lawyer can see it.'),
                                        backgroundColor: Color(0xFF2E8B57),
                                        behavior: SnackBarBehavior.floating,
                                      ));
                                  } catch (e) {
                                    setS(() => _uploading = false);
                                    if (ctx.mounted)
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Upload failed. Please try again.'),
                                              backgroundColor:
                                                  Color(0xFFD9534F)));
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _green,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14))),
                          child: _uploading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Add Document',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                        ),
                      ),
                    ]),
              );
          }),
    );
  }

  Widget _sheetField(TextEditingController ctrl, String label, IconData icon) =>
      TextField(
          controller: ctrl,
          style: const TextStyle(color: _textPri, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
            prefixIcon: Icon(icon, color: _green, size: 18),
            filled: true,
            fillColor: _bg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border, width: 0.8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _green, width: 1.5)),
          ));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  const Text('My Documents',
                      style: TextStyle(
                          color: _textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${widget.documents.length} files',
                      style: const TextStyle(color: _textMuted, fontSize: 12)),
                ]),
              ),
              Expanded(
                child: widget.documents.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: Icon(Icons.folder_open_rounded,
                                    color: _green, size: 44)),
                            const SizedBox(height: 16),
                            const Text('No documents yet',
                                style: TextStyle(
                                    color: _textPri,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text(
                                'Upload files from your device to share with lawyer',
                                style:
                                    TextStyle(color: _textMuted, fontSize: 13)),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _showUploadDialog,
                              icon: const Icon(Icons.add_rounded,
                                  color: Colors.white),
                              label: const Text('Add Document',
                                  style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                            ),
                          ]))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: widget.documents.length,
                        itemBuilder: (_, i) {
                          final doc = widget.documents[i];
                          return _DocCard(
                              doc: doc,
                              color: _color(doc['file_type'], doc['file_name']),
                              icon: _icon(doc['file_type'], doc['file_name']));
                        }),
              ),
            ]), // Column
          ), // SafeArea
        ]), // Stack
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showUploadDialog,
          backgroundColor: _green,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Add Document',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      );
}

class _DashPickFileButton extends StatelessWidget {
  final bool loading;
  final List<String> allowedExt;
  final VoidCallback? onTap;
  const _DashPickFileButton(
      {required this.loading, required this.allowedExt, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 1.2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (loading)
              const SizedBox(
                  width: 28,
                  height: 28,
                  child:
                      CircularProgressIndicator(color: _green, strokeWidth: 2.5))
            else
              const Icon(Icons.cloud_upload_rounded, color: _green, size: 32),
            const SizedBox(height: 8),
            Text(loading ? 'Opening file picker...' : 'Tap to select a file',
                style: const TextStyle(
                    color: _textPri, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(allowedExt.map((e) => e.toUpperCase()).join(', '),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _textMuted.withValues(alpha: 0.8), fontSize: 10)),
          ]),
        ),
      );
}

class _DashPickedFilePreview extends StatelessWidget {
  final PlatformFile file;
  final VoidCallback onRemove;
  final VoidCallback onChange;
  const _DashPickedFilePreview(
      {required this.file, required this.onRemove, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final ext = _dashExtOf(file.name);
    final isImage = _dashAllowedExtByType['Photo']!.contains(ext);
    final isVideo = _dashAllowedExtByType['Video']!.contains(ext);

    Widget thumb;
    if (isImage && file.bytes != null) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child:
            Image.memory(file.bytes!, width: 52, height: 52, fit: BoxFit.cover),
      );
    } else {
      final icon = isVideo
          ? Icons.videocam_rounded
          : ext == 'pdf'
              ? Icons.picture_as_pdf_rounded
              : Icons.insert_drive_file_rounded;
      thumb = Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Stack(alignment: Alignment.center, children: [
          Icon(icon, color: _green, size: 26),
          if (isVideo)
            const Positioned(
                bottom: 4,
                right: 4,
                child: Icon(Icons.play_circle_fill_rounded,
                    color: _green, size: 16)),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green, width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Selected File',
            style: TextStyle(
                color: _textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Text('${ext.toUpperCase()} · ${_dashFormatFileSize(file.size)}',
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFD9534F), size: 16),
              label: const Text('Remove',
                  style: TextStyle(
                      color: Color(0xFFD9534F), fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD9534F)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onChange,
              icon: const Icon(Icons.sync_alt_rounded, color: _green, size: 16),
              label: const Text('Change File',
                  style: TextStyle(color: _green, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _green),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Doc Card ───────────────────────────────────────
class _DocCard extends StatelessWidget {
  final dynamic doc;
  final Color color;
  final IconData icon;
  const _DocCard({required this.doc, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final name = doc['file_name'] ?? 'Document';
    final category = doc['category'] ?? '';
    final date = (doc['created_at'] ?? '').toString();
    final dateStr = date.length >= 10 ? date.substring(0, 10) : '';
    final url = doc['file_url'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: _green.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Row(children: [
        Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 26)),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [
            if (category.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(category,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 6),
            Text(dateStr,
                style: const TextStyle(color: _textMuted, fontSize: 10)),
          ]),
          if (url.isNotEmpty)
            Text(url,
                style: const TextStyle(color: _teal, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ])),
        if (url.isNotEmpty)
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Link copied!'),
                    backgroundColor: Color(0xFF2E8B57)));
            },
            child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.copy_rounded, color: color, size: 16)),
          ),
      ]),
    );
  }
}

// ── Billing Tab ────────────────────────────────────
class _BillingTab extends StatelessWidget {
  final List<dynamic> invoices;
  const _BillingTab({required this.invoices});

  double get _totalPending => invoices
      .where((i) => i['status'] == 'pending')
      .fold(0.0, (s, i) => s + ((i['total_amount'] ?? 0.0) as num).toDouble());
  double get _totalPaid => invoices
      .where((i) => i['status'] == 'paid')
      .fold(0.0, (s, i) => s + ((i['total_amount'] ?? 0.0) as num).toDouble());

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          SafeArea(
              child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Billing & Payments',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: _BillStat('₹${_totalPending.toStringAsFixed(0)}',
                      'Pending', const Color(0xFFD4A017))),
              const SizedBox(width: 12),
              Expanded(
                  child: _BillStat('₹${_totalPaid.toStringAsFixed(0)}', 'Paid',
                      const Color(0xFF2E8B57))),
              const SizedBox(width: 12),
              Expanded(child: _BillStat('${invoices.length}', 'Total', _green)),
            ]),
            const SizedBox(height: 20),
            ...invoices.map((inv) => _InvoiceCard(invoice: inv)),
            const SizedBox(height: 40),
          ])), // ListView + SafeArea
        ]), // Stack
      );
}

// ── Chat Tab ───────────────────────────────────────
class _ChatTab extends StatelessWidget {
  final List<dynamic> chatRooms;
  final AuthProvider auth;
  const _ChatTab({required this.chatRooms, required this.auth});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Messages',
                        style: TextStyle(
                            color: _textPri,
                            fontSize: 22,
                            fontWeight: FontWeight.w800))),
              ),
              Expanded(
                child: chatRooms.isEmpty
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
                                    color: _green, size: 38)),
                            const SizedBox(height: 16),
                            const Text('No conversations yet',
                                style:
                                    TextStyle(color: _textMuted, fontSize: 16)),
                          ]))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: chatRooms.length,
                        itemBuilder: (_, i) {
                          final room = chatRooms[i];
                          final lawyerName = room['lawyer_name'] ??
                              room['other_name'] ??
                              'Your Lawyer';
                          final lastMsg = room['last_message'] ?? 'Tap to chat';
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              context
                                  .push('/chat/${room['id']}?name=$lawyerName');
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
                                        color: _green.withValues(alpha: 0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2))
                                  ]),
                              child: Row(children: [
                                Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [
                                        Color(0xFF0D6E4F),
                                        Color(0xFF1A9E72)
                                      ]),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                        child: Text(
                                            lawyerName.isNotEmpty
                                                ? lawyerName[0].toUpperCase()
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
                                      Text(lawyerName,
                                          style: const TextStyle(
                                              color: _textPri,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15)),
                                      const Text('Advocate',
                                          style: TextStyle(
                                              color: _green, fontSize: 11)),
                                      Text(lastMsg,
                                          style: const TextStyle(
                                              color: _textMuted, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ])),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: _green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: const Row(children: [
                                    Icon(Icons.chat_rounded,
                                        color: _green, size: 14),
                                    SizedBox(width: 4),
                                    Text('Chat',
                                        style: TextStyle(
                                            color: _green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                  ]),
                                ),
                              ]),
                            ),
                          );
                        }),
              ),
            ]), // Column
          ), // SafeArea
        ]), // Stack
      );
}

// ── Profile Tab ────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final AuthProvider auth;
  const _ProfileTab({required this.auth});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
            child: ListView(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter),
            ),
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.push('/profile/edit'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 5),
                      Text('Edit Profile',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Stack(children: [
                Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5), width: 2.5),
                    ),
                    child: Center(
                        child: Text(auth.user?.initials ?? 'C',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 34)))),
                Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                            color: Color(0xFF4CAF7D), shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16))),
              ]),
              const SizedBox(height: 14),
              Text(auth.user?.name ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('VERIFIED CLIENT',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              Text(auth.user?.email ?? '',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
            ]),
          ),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _InfoTile(Icons.person_outline_rounded, 'Full Name',
                    auth.user?.name ?? '', _green),
                const SizedBox(height: 10),
                _InfoTile(Icons.email_outlined, 'Email', auth.user?.email ?? '',
                    _teal),
                const SizedBox(height: 10),
                _InfoTile(Icons.phone_outlined, 'Phone',
                    auth.user?.phone ?? 'Not added', const Color(0xFF2E8B57)),
                const SizedBox(height: 20),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Features',
                        style: TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
                const SizedBox(height: 10),
                _SettingsTile(
                    icon: Icons.gavel_rounded,
                    title: 'My Cases',
                    subtitle: 'View all your legal cases',
                    color: _green,
                    onTap: () => context.push('/portal/cases')),
                const SizedBox(height: 8),
                _SettingsTile(
                    icon: Icons.receipt_long_rounded,
                    title: 'Payment History',
                    subtitle: 'All invoices & payments',
                    color: const Color(0xFF2E8B57),
                    onTap: () => context.push('/portal/invoices')),
                const SizedBox(height: 8),
                _SettingsTile(
                    icon: Icons.folder_rounded,
                    title: 'My Documents',
                    subtitle: 'Upload & manage files',
                    color: _teal,
                    onTap: () => context.push('/portal/documents')),
                const SizedBox(height: 8),
                _SettingsTile(
                    icon: Icons.history_rounded,
                    title: 'Call History',
                    subtitle: 'Past chat, audio & video consultations',
                    color: const Color(0xFF4A90D9),
                    onTap: () => context.push('/portal/consultation-history')),
                const SizedBox(height: 8),
                _SettingsTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    subtitle: 'Case updates & reminders',
                    color: const Color(0xFFD4A017),
                    onTap: () => context.push('/notifications')),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await auth.logout();
                      if (context.mounted) context.go('/login');
                    },
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    label: const Text('Sign Out',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD9534F),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                  ),
                ),
                const SizedBox(height: 40),
              ])),
        ])),
      );
}


class _CaseCard extends StatelessWidget {
  final dynamic caseData;
  final int docCount;
  final VoidCallback onTap;
  const _CaseCard(
      {required this.caseData, required this.onTap, this.docCount = 0});

  @override
  Widget build(BuildContext context) {
    final c = caseData;
    final status = c['status'] ?? 'active';
    Color sc;
    switch (status) {
      case 'won':
        sc = const Color(0xFFD4A017);
        break;
      case 'lost':
        sc = const Color(0xFFD9534F);
        break;
      case 'pending':
        sc = const Color(0xFFD4A017);
        break;
      default:
        sc = _green;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sc.withValues(alpha: 0.25)),
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
              decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.gavel_rounded, color: sc, size: 22)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(c['case_title'] ?? 'Case',
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(c['court_name'] ?? c['case_type'] ?? '',
                    style: const TextStyle(color: _textMuted, fontSize: 12)),
                if (docCount > 0)
                  Text('📁 $docCount documents',
                      style: const TextStyle(color: _teal, fontSize: 11)),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sc.withValues(alpha: 0.3))),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: sc, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: _textMuted, size: 12),
          ]),
        ]),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final dynamic invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final status = invoice['status'] ?? 'pending';
    final isPaid = status == 'paid';
    final isPending = status == 'pending_verification';
    final amount = ((invoice['total_amount'] ?? 0.0) as num).toDouble();
    final color = isPaid
        ? const Color(0xFF2E8B57)
        : isPending
            ? const Color(0xFFD4A017)
            : const Color(0xFFD9534F);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: _green.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Row(children: [
        Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(
                isPaid ? Icons.check_circle_rounded : Icons.receipt_rounded,
                color: color,
                size: 22)),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(invoice['invoice_number'] ?? '',
              style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w700, fontSize: 14)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          if (isPending)
            const Text('⏳ Awaiting verification',
                style: TextStyle(color: Color(0xFFD4A017), fontSize: 11)),
        ])),
        if (!isPaid && !isPending)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(
                  '/portal/payment/${invoice['id']}?amount=$amount&invoice=${invoice['invoice_number']}');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: _green, borderRadius: BorderRadius.circular(10)),
              child: const Text('Pay Now',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
          )
        else if (isPending)
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xFFD4A017).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('Pending',
                  style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontWeight: FontWeight.w700,
                      fontSize: 12)))
        else
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF2E8B57), size: 24),
      ]),
    );
  }
}

class _HearingCard extends StatelessWidget {
  final dynamic hearing;
  final VoidCallback? onTap;
  const _HearingCard({required this.hearing, this.onTap});
  @override
  Widget build(BuildContext context) {
    final dateStr = (hearing['hearing_date'] ?? '').toString();
    final shortDate = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
    final status = hearing['status'] ?? 'scheduled';
    final sc = status == 'completed'
        ? const Color(0xFF2E8B57)
        : status == 'cancelled'
            ? const Color(0xFFD9534F)
            : status == 'adjourned'
                ? const Color(0xFFD4A017)
                : _green;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sc.withValues(alpha: 0.2), width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _green.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.event_rounded, color: sc, size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(hearing['case_title'] ?? 'Hearing',
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(shortDate,
                    style: TextStyle(
                        color: sc, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(hearing['court_name'] ?? '',
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: sc, fontSize: 10, fontWeight: FontWeight.w700))),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_ios_rounded,
              color: _textMuted, size: 12),
        ]),
      ),
    );
  }
}

// ── Hearing Section ───────────────────────────────
Widget _HearingSection(String title, List<dynamic> hearings, Color color) {
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(width: 6),
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Text('${hearings.length}',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700))),
    ]),
    const SizedBox(height: 10),
    ...hearings.map((h) {
      final status = h['status'] ?? 'scheduled';
      final sc = status == 'completed'
          ? const Color(0xFF2E8B57)
          : status == 'cancelled'
              ? const Color(0xFFD9534F)
              : status == 'adjourned'
                  ? const Color(0xFFD4A017)
                  : const Color(0xFF4A90D9);
      final date = (h['hearing_date'] ?? '').toString();
      final shortDate = date.length >= 10 ? date.substring(0, 10) : date;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sc.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF0D6E4F).withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.event_rounded, color: sc, size: 22)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(h['case_title'] ?? 'Hearing',
                      style: const TextStyle(
                          color: Color(0xFF0A2E1F),
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(shortDate,
                      style: TextStyle(
                          color: sc,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  Text(h['court_name'] ?? '',
                      style: const TextStyle(
                          color: Color(0xFF4A7A63), fontSize: 11)),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: sc, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
          ]),
          // Show order summary if available
          if ((h['order_summary'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFF0D6E4F).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFB2DFD0))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.gavel_rounded,
                          color: Color(0xFF0D6E4F), size: 12),
                      SizedBox(width: 4),
                      Text('Order Summary',
                          style: TextStyle(
                              color: Color(0xFF0D6E4F),
                              fontWeight: FontWeight.w700,
                              fontSize: 11)),
                    ]),
                    const SizedBox(height: 4),
                    Text(h['order_summary'],
                        style: const TextStyle(
                            color: Color(0xFF0A2E1F),
                            fontSize: 11,
                            height: 1.4)),
                  ]),
            ),
          ],
          // Next date
          if ((h['next_date'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xFFD4A017).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFD4A017).withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.event_repeat_rounded,
                    color: Color(0xFFD4A017), size: 13),
                const SizedBox(width: 6),
                const Text('Next: ',
                    style: TextStyle(color: Color(0xFF4A7A63), fontSize: 11)),
                Text(
                    h['next_date'].toString().length >= 10
                        ? h['next_date'].toString().substring(0, 10)
                        : h['next_date'],
                    style: const TextStyle(
                        color: Color(0xFFD4A017),
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ]),
            ),
          ],
        ]),
      );
    }).toList(),
  ]);
}

// ── Consultation Card ──────────────────────────────
class _ConsultationCard extends StatelessWidget {
  final dynamic consultation;
  final BuildContext context;
  const _ConsultationCard({required this.consultation, required this.context});

  void _showActionError(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: const Color(0xFFD9534F)));
  }

  // The client only ever JOINS a session the lawyer already started — never
  // places the call. This used to POST /portal/my-consultations/:id/call
  // (the same start-session action the lawyer uses) and join as the caller;
  // that endpoint is now lawyer-only on the backend (see
  // InitiateConsultationCall), so a client calling it gets a 403 regardless
  // of what this screen does. isCaller is false here because the client is
  // answering an already-active session, not starting one.
  void _joinCall({required bool video}) {
    final id = consultation['id'];
    if (id == null) {
      _showActionError('This booking is missing its consultation id.');
      return;
    }
    final lawyerName = (consultation['lawyer_name'] ?? 'Your Lawyer').toString();
    context.push('/call', extra: {
      'consultationId': id.toString(),
      'peerName': lawyerName,
      'video': video,
      'isCaller': false,
    });
  }

  void _callLawyer() => _joinCall(video: false);

  void _openVideoCall() => _joinCall(video: true);

  Future<void> _startChat() async {
    final lawyerId = consultation['lawyer_id'] ?? '';
    final lawyerName = consultation['lawyer_name'] ?? 'Your Lawyer';

    try {
      // Create or get existing chat room with lawyer
      final res = await DioClient.instance.post('/chat/rooms', data: {
        'lawyer_id': lawyerId,
        'room_name': lawyerName,
      });
      final roomId =
          res.data['data']?['id'] ?? res.data['data']?['room_id'] ?? '';
      if (roomId.isNotEmpty && context.mounted) {
        context.push('/chat/$roomId?name=${Uri.encodeComponent(lawyerName)}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to open chat. Please try again.'),
            backgroundColor: Color(0xFFD9534F)));
      }
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final status = consultation['status'] ?? 'pending';
    final sessionStarted = consultation['session_status'] == 'started';
    final type = consultation['consultation_type'] ?? 'Consultation';
    final date = consultation['consultation_date'] ?? '';
    final time = consultation['consultation_time'] ?? '';
    final lawyerName = consultation['lawyer_name'] ?? 'Your Lawyer';
    final meetLink = consultation['meeting_link'] ?? '';
    final notes = consultation['lawyer_notes'] ?? '';

    final Color color = status == 'confirmed'
        ? const Color(0xFF2E8B57)
        : (status == 'cancelled' || status == 'rejected' || status == 'expired')
            ? const Color(0xFFD9534F)
            : status == 'completed'
                ? const Color(0xFF4A90D9)
                : const Color(0xFFD4A017);

    final action = _consultationAction(type);
    final bool isOfficeVisit = type.toLowerCase().contains('office');
    final IconData typeIcon = isOfficeVisit
        ? Icons.business_center_rounded
        : action == 'video'
            ? Icons.videocam_rounded
            : action == 'audio'
                ? Icons.phone_rounded
                : Icons.chat_rounded;
    final String typeEmoji = isOfficeVisit
        ? '🏢'
        : action == 'video'
            ? '🎥'
            : action == 'audio'
                ? '📞'
                : '💬';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: status == 'confirmed' ? 2 : 0.8),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        // Color bar at top
        Container(
            height: 4,
            decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)))),
        Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(typeIcon, color: color, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(lawyerName,
                          style: const TextStyle(
                              color: _textPri,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      Text('$typeEmoji $type',
                          style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      if (date.isNotEmpty)
                        Text('$date${time.isNotEmpty ? " at $time" : ""}',
                            style: const TextStyle(
                                color: _textMuted, fontSize: 11)),
                    ])),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ]),

              // Payment status
              if (consultation['payment_status'] == 'paid') ...[
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2E8B57).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_rounded,
                          color: Color(0xFF2E8B57), size: 12),
                      SizedBox(width: 4),
                      Text('₹5 Paid',
                          style: TextStyle(
                              color: Color(0xFF2E8B57),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              ],

              // Lawyer confirmed message
              if (status == 'confirmed') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF2E8B57).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF2E8B57).withValues(alpha: 0.2))),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF2E8B57), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('✅ Lawyer has confirmed your consultation!',
                            style: TextStyle(
                                color: Color(0xFF2E8B57),
                                fontWeight: FontWeight.w700,
                                fontSize: 12))),
                  ]),
                ),
              ],

              // Lawyer rejected the request — the client previously had no
              // clear indication of this at all, just a red "CANCELLED"-style
              // badge with no explanation.
              if (status == 'rejected') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD9534F).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFD9534F).withValues(alpha: 0.2))),
                  child: const Row(children: [
                    Icon(Icons.cancel_outlined,
                        color: Color(0xFFD9534F), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('❌ The lawyer has rejected this booking.',
                            style: TextStyle(
                                color: Color(0xFFD9534F),
                                fontWeight: FontWeight.w700,
                                fontSize: 12))),
                  ]),
                ),
              ],

              // The lawyer never started the session within the booking
              // window — the backend's ConsultationSweeper marks this
              // automatically using server time, not the device clock.
              if (status == 'expired') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD9534F).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFD9534F).withValues(alpha: 0.2))),
                  child: const Row(children: [
                    Icon(Icons.timer_off_outlined,
                        color: Color(0xFFD9534F), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            '⏱ This booking expired — the lawyer did not start it in time.',
                            style: TextStyle(
                                color: Color(0xFFD9534F),
                                fontWeight: FontWeight.w700,
                                fontSize: 12))),
                  ]),
                ),
              ],

              // Lawyer notes
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: const Color(0xFF4A90D9).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF4A90D9).withValues(alpha: 0.15))),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes_rounded,
                            color: Color(0xFF4A90D9), size: 13),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text('Lawyer: $notes',
                                style: const TextStyle(
                                    color: _textPri, fontSize: 11))),
                      ]),
                ),
              ],

              // Meeting link
              if (meetLink.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _green.withValues(alpha: 0.2))),
                  child: Row(children: [
                    const Icon(Icons.link_rounded, color: _green, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(meetLink,
                            style: const TextStyle(color: _green, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ],

              // Action buttons
              //
              // The client never initiates chat/audio/video — only the lawyer
              // can (see InitiateConsultationCall, which now rejects a client
              // outright). Until session_status is 'started', the only thing
              // shown here is a waiting state; there is no "Call"/"Chat"
              // button to tap even when the booking itself is confirmed.
              if (status == 'confirmed' || status == 'pending') ...[
                const SizedBox(height: 12),
                Row(children: [
                  if (status == 'confirmed' && sessionStarted)
                    Expanded(
                        child: _ConsultationActionButton(
                      icon: isOfficeVisit
                          ? Icons.business_center_rounded
                          : action == 'video'
                              ? Icons.videocam_rounded
                              : action == 'audio'
                                  ? Icons.phone_rounded
                                  : Icons.chat_rounded,
                      label: isOfficeVisit
                          ? 'View Office Details'
                          : action == 'video'
                              ? 'Join Video Call'
                              : action == 'audio'
                                  ? 'Join Call'
                                  : 'Open Chat',
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        if (isOfficeVisit) {
                          _startChat();
                        } else if (action == 'video') {
                          _openVideoCall();
                        } else if (action == 'audio') {
                          _callLawyer();
                        } else {
                          _startChat();
                        }
                      },
                    ))
                  else
                    Expanded(
                        child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFD4A017).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFD4A017).withValues(alpha: 0.3))),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.hourglass_empty_rounded,
                                color: Color(0xFFD4A017), size: 16),
                            const SizedBox(width: 6),
                            Text(
                                status == 'pending'
                                    ? 'Awaiting Confirmation'
                                    : 'Waiting for Lawyer to Start',
                                style: const TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                          ]),
                    )),
                ]),
              ],
            ])),
      ]),
    );
  }
}

// Full-width, rounded, ripple-feedback action button used for all three
// consultation actions (chat / audio call / video call) so the styling stays
// identical regardless of which one renders.
class _ConsultationActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ConsultationActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: _green,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      );
}

class _StatChip extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatChip(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ]),
      ));
}

class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickBtn(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
          child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                    color: _green.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      ));
}

Widget _SectionHeader(String title, {VoidCallback? onSeeAll}) =>
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title,
          style: const TextStyle(
              color: _textPri, fontSize: 16, fontWeight: FontWeight.w700)),
      if (onSeeAll != null)
        GestureDetector(
            onTap: onSeeAll,
            child: const Text('See All',
                style: TextStyle(color: _green, fontSize: 12))),
    ]);

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _InfoTile(this.icon, this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _green.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
                Text(value,
                    style: const TextStyle(
                        color: _textPri, fontWeight: FontWeight.w600)),
              ])),
        ]),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _SettingsTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _green.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: _textPri, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
                ])),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: _textMuted, size: 14),
          ]),
        ),
      );
}

class _BillStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _BillStat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: _green.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 11)),
        ]),
      );
}
