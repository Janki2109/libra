import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../student/screens/news_webview_screen.dart';

// ── Blue/White Theme ──────────────────────────────
const _bg = Color(0xFFF0F4FF);
const _bgCard = Color(0xFFFFFFFF);
const _navy = Color(0xFF0A1628);
const _blue = Color(0xFF1565C0);
const _skyBlue = Color(0xFF0288D1);
const _lightBlue = Color(0xFF29B6F6);
const _border = Color(0xFFBBDEFB);
const _textPri = Color(0xFF0A1628);
const _textMuted = Color(0xFF546E7A);
const _gold = Color(0xFFFFD700);

class LawStudentDashboardScreen extends StatefulWidget {
  const LawStudentDashboardScreen({super.key});
  @override
  State<LawStudentDashboardScreen> createState() =>
      _LawStudentDashboardScreenState();
}

class _LawStudentDashboardScreenState extends State<LawStudentDashboardScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  Map<String, dynamic> _progress = {};
  List<dynamic> _lawyers = [];
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
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DioClient.instance.get('/student/progress'),
        DioClient.instance.get('/student/lawyers'),
      ]);
      setState(() {
        _progress = results[0].data['data']?['progress'] ?? {};
        _lawyers = results[1].data['data'] ?? [];
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
          progress: _progress,
          lawyers: _lawyers,
          auth: auth,
          fadeAnim: _fadeAnim,
          onRefresh: _loadData,
          onTabChange: (i) => setState(() => _selectedIndex = i)),
      _CasesTab(),
      _NewsTab(),
      _LawyersTab(lawyers: _lawyers),
      _ProfileTab(auth: auth, progress: _progress),
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? Container(
              color: _bg,
              child:
                  const Center(child: CircularProgressIndicator(color: _blue)))
          : screens[_selectedIndex],
      bottomNavigationBar: _BottomNav(
        selectedIndex: _selectedIndex,
        onTap: (i) {
          HapticFeedback.lightImpact();
          setState(() => _selectedIndex = i);
        },
      ),
    );
  }
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
      {'icon': Icons.menu_book_rounded, 'label': 'Library'},
      {'icon': Icons.newspaper_rounded, 'label': 'News'},
      {'icon': Icons.people_rounded, 'label': 'Lawyers'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        border: Border(top: BorderSide(color: _border, width: 0.8)),
        boxShadow: [
          BoxShadow(
              color: _blue.withValues(alpha: 0.08),
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
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? _blue.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(e.value['icon'] as IconData,
                        color: sel ? _blue : _textMuted, size: 22),
                    const SizedBox(height: 2),
                    Text(e.value['label'] as String,
                        style: TextStyle(
                            color: sel ? _blue : _textMuted,
                            fontSize: 9,
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                ),
              );
            }).toList()),
      )),
    );
  }
}

// ── Home Tab ───────────────────────────────────────
class _HomeTab extends StatelessWidget {
  final Map<String, dynamic> progress;
  final List<dynamic> lawyers;
  final AuthProvider auth;
  final Animation<double> fadeAnim;
  final VoidCallback onRefresh;
  final Function(int) onTabChange;
  const _HomeTab(
      {required this.progress,
      required this.lawyers,
      required this.auth,
      required this.fadeAnim,
      required this.onRefresh,
      required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    final xp = progress['xp'] ?? 0;
    final level = progress['level'] ?? 1;
    final cases = progress['total_cases_completed'] ?? 0;
    final streak = progress['streak'] ?? 0;
    final name = auth.user?.name ?? 'Student';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'S';

    return FadeTransition(
      opacity: fadeAnim,
      child: RefreshIndicator(
        color: _blue,
        backgroundColor: _bgCard,
        onRefresh: () async => onRefresh(),
        child: CustomScrollView(slivers: [
          // Header
          SliverToBoxAdapter(
              child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0A1628),
                  Color(0xFF1A237E),
                  Color(0xFF1565C0)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
                bottom: false,
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
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  width: 2),
                            ),
                            child: Center(
                                child: Text(initials,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const Text('Welcome back,',
                                    style: TextStyle(
                                        color: Colors.white60, fontSize: 12)),
                                Text(name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                              ])),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: _gold,
                                borderRadius: BorderRadius.circular(20)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.military_tech_rounded,
                                  color: _navy, size: 14),
                              const SizedBox(width: 4),
                              Text('Level $level',
                                  style: const TextStyle(
                                      color: _navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        // XP bar
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('$xp XP',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                              Text('${level * 500} XP to Level ${level + 1}',
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 11)),
                            ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: ((xp % 500) / 500.0).clamp(0.0, 1.0),
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              valueColor:
                                  const AlwaysStoppedAnimation(_lightBlue),
                              minHeight: 10,
                            )),
                        const SizedBox(height: 16),
                        // Stats
                        Row(children: [
                          _StatChip(Icons.military_tech_rounded, '$level',
                              'Level', _gold),
                          const SizedBox(width: 8),
                          _StatChip(
                              Icons.bolt_rounded, '$xp', 'XP', _lightBlue),
                          const SizedBox(width: 8),
                          _StatChip(Icons.gavel_rounded, '$cases', 'Cases',
                              Colors.white),
                          const SizedBox(width: 8),
                          _StatChip(Icons.local_fire_department_rounded,
                              '$streak', 'Streak', const Color(0xFFFF9800)),
                        ]),
                      ]),
                )),
          )),

          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Case Challenge banner
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  context.push('/student/challenge');
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF1565C0),
                        Color(0xFF0288D1),
                        Color(0xFF29B6F6)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: _blue.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Text('🔥 AI POWERED',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 10),
                          const Text('Case Challenge',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          const Text('Unique case every time • Earn XP!',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                                color: _bgCard,
                                borderRadius: BorderRadius.circular(20)),
                            child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Start Now',
                                      style: TextStyle(
                                          color: _blue,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13)),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward_rounded,
                                      color: _blue, size: 14),
                                ]),
                          ),
                        ])),
                    const SizedBox(width: 12),
                    const Text('⚖️', style: TextStyle(fontSize: 60)),
                  ]),
                ),
              ),
              const SizedBox(height: 20),

              // Explore
              const Text('Explore',
                  style: TextStyle(
                      color: _textPri,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _ExploreCard('📰', 'Live News', 'Court updates', _skyBlue,
                      () => onTabChange(2)),
                  _ExploreCard('📚', 'Study Library', 'Free legal resources',
                      _blue, () => onTabChange(1)),
                  _ExploreCard(
                      '💬',
                      'AI Lawyer',
                      'Ask AI anything',
                      const Color(0xFF00897B),
                      () => context.push('/student/ai-lawyer')),
                  _ExploreCard(
                      '📅',
                      'Consultation Mode',
                      'Book a lawyer consultation',
                      const Color(0xFF7C3AED),
                      () => onTabChange(3)),
                  _ExploreCard('🏆', 'Leaderboard', 'Top students', _gold,
                      () => context.push('/student/leaderboard')),
                  _ExploreCard('📖', 'Legal Notes', 'Study subjects', _blue,
                      () => context.push('/student/notes')),
                  _ExploreCard('❓', 'Quiz', 'Test knowledge', _skyBlue,
                      () => context.push('/student/quiz')),
                  _ExploreCard(
                      '🏛️',
                      'Mock Court',
                      'Argue cases',
                      const Color(0xFF7C3AED),
                      () => context.push('/student/mock-court')),
                  _ExploreCard('🎓', 'Certificates', 'Your achievements', _gold,
                      () => context.push('/student/certificates')),
                ],
              ),
              const SizedBox(height: 80),
            ]),
          )),
        ]),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _StatChip(this.icon, this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ]),
      ));
}

class _ExploreCard extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ExploreCard(
      this.emoji, this.title, this.subtitle, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                    color: _blue.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 20)))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(subtitle,
                      style: const TextStyle(color: _textMuted, fontSize: 10)),
                ])),
          ]),
        ),
      );
}

// ── Cases Tab ──────────────────────────────────────
class _CasesTab extends StatefulWidget {
  const _CasesTab();
  @override
  State<_CasesTab> createState() => _CasesTabState();
}

class _CasesTabState extends State<_CasesTab> {
  // ── Study Library (new) — separate state from the landmark-cases filter
  // above so this addition can't affect that existing behaviour.
  String _libraryCategory = 'All';
  String _librarySearch = '';

  static const List<String> _libraryCategories = [
    'All',
    'Constitutional',
    'Criminal',
    'Civil',
    'Contract',
    'Family',
    'Property',
    'Company',
    'Evidence',
    'Judiciary',
    'Bare Acts',
    'Legal Research',
    'General',
  ];

  // Every entry links to a real, free, legitimate official/academic source
  // (India Code, Legislative Dept., Law Commission of India, NHRC, Bar
  // Council of India, National Judicial Academy, NPTEL, SWAYAM, eGyanKosh,
  // Indian Kanoon, LiveLaw, Bar & Bench, LatestLaws, Legal Service India,
  // WIPO) — no pirated PDFs or unauthorized hosts.
  static const List<Map<String, dynamic>> _library = [
    // ── Constitutional ─────────────────────────
    {
      'title': 'Constitution of India – Full Text',
      'author': 'Legislative Department, Govt. of India',
      'category': 'Constitutional',
      'year': '1950',
      'source': 'legislative.gov.in',
      'desc': 'Complete text with Fundamental Rights, Duties and Directive Principles.',
      'emoji': '🏛️', 'color': Color(0xFF7C3AED),
      'url': 'https://legislative.gov.in/constitution-of-india/',
    },
    {
      'title': 'Kesavananda Bharati v. State of Kerala',
      'author': 'Supreme Court of India',
      'category': 'Constitutional',
      'year': '1973',
      'source': 'Indian Kanoon',
      'desc': 'Landmark case establishing the Basic Structure Doctrine.',
      'emoji': '⚖️', 'color': Color(0xFF1565C0),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'Maneka Gandhi v. Union of India',
      'author': 'Supreme Court of India',
      'category': 'Constitutional',
      'year': '1978',
      'source': 'Indian Kanoon',
      'desc': 'Expanded the scope of Article 21 — Right to Life and Personal Liberty.',
      'emoji': '⚖️', 'color': Color(0xFF1565C0),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'Constitutional Law of India — Video Course',
      'author': 'NPTEL / IIT Faculty',
      'category': 'Constitutional',
      'year': '',
      'source': 'NPTEL',
      'desc': 'Free video lecture course on the structure and doctrines of Indian constitutional law.',
      'emoji': '🎓', 'color': Color(0xFF0EA5E9),
      'url': 'https://nptel.ac.in/courses',
    },
    {
      'title': 'Constitutional Law Reform Reports',
      'author': 'Law Commission of India',
      'category': 'Constitutional',
      'year': '',
      'source': 'lawcommissionofindia.nic.in',
      'desc': 'Official reports examining constitutional questions and reform recommendations.',
      'emoji': '📑', 'color': Color(0xFF00897B),
      'url': 'https://lawcommissionofindia.nic.in/',
    },
    // ── Criminal ────────────────────────────────
    {
      'title': 'Indian Penal Code, 1860',
      'author': 'Ministry of Law & Justice',
      'category': 'Criminal',
      'year': '1860',
      'source': 'India Code',
      'desc': 'Primary criminal code of India — offences, punishments and general exceptions.',
      'emoji': '🔒', 'color': Color(0xFFDC2626),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Code of Criminal Procedure, 1973',
      'author': 'Ministry of Law & Justice',
      'category': 'Criminal',
      'year': '1973',
      'source': 'India Code',
      'desc': 'Procedural law governing the conduct of criminal trials in India.',
      'emoji': '🔒', 'color': Color(0xFFDC2626),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'POCSO Act, 2012',
      'author': 'Ministry of Law & Justice',
      'category': 'Criminal',
      'year': '2012',
      'source': 'India Code',
      'desc': 'Protection of Children from Sexual Offences Act — official text.',
      'emoji': '🔒', 'color': Color(0xFFDC2626),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'State of Punjab v. Sucha Singh',
      'author': 'Supreme Court of India',
      'category': 'Criminal',
      'year': '2003',
      'source': 'Indian Kanoon',
      'desc': 'Explores standards for corroboration of eyewitness testimony.',
      'emoji': '⚖️', 'color': Color(0xFFDC2626),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'Criminal Law Updates & Analysis',
      'author': 'Bar & Bench',
      'category': 'Criminal',
      'year': '',
      'source': 'barandbench.com',
      'desc': 'Ongoing coverage of major criminal law judgments and reforms.',
      'emoji': '📰', 'color': Color(0xFF0EA5E9),
      'url': 'https://www.barandbench.com',
    },
    // ── Civil ───────────────────────────────────
    {
      'title': 'Code of Civil Procedure, 1908',
      'author': 'Ministry of Law & Justice',
      'category': 'Civil',
      'year': '1908',
      'source': 'India Code',
      'desc': 'Governs civil court procedure across India.',
      'emoji': '📘', 'color': Color(0xFF059669),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Specific Relief Act, 1963',
      'author': 'Ministry of Law & Justice',
      'category': 'Civil',
      'year': '1963',
      'source': 'India Code',
      'desc': 'Provides remedies for enforcement of individual civil rights.',
      'emoji': '📘', 'color': Color(0xFF059669),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Limitation Act, 1963',
      'author': 'Ministry of Law & Justice',
      'category': 'Civil',
      'year': '1963',
      'source': 'India Code',
      'desc': 'Prescribes time limits for filing civil suits, appeals and applications.',
      'emoji': '📘', 'color': Color(0xFF059669),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Civil Procedure Reform Reports',
      'author': 'Law Commission of India',
      'category': 'Civil',
      'year': '',
      'source': 'lawcommissionofindia.nic.in',
      'desc': 'Reports recommending reform of civil procedure law.',
      'emoji': '📑', 'color': Color(0xFF00897B),
      'url': 'https://lawcommissionofindia.nic.in/',
    },
    {
      'title': 'Civil Law — Student Articles',
      'author': 'Legal Service India',
      'category': 'Civil',
      'year': '',
      'source': 'legalserviceindia.com',
      'desc': 'Free student-contributed articles explaining core civil law concepts.',
      'emoji': '📝', 'color': Color(0xFFD97706),
      'url': 'https://www.legalserviceindia.com/',
    },
    // ── Contract ────────────────────────────────
    {
      'title': 'Indian Contract Act, 1872',
      'author': 'Ministry of Law & Justice',
      'category': 'Contract',
      'year': '1872',
      'source': 'India Code',
      'desc': 'Foundational statute governing the formation and enforcement of contracts.',
      'emoji': '🤝', 'color': Color(0xFF7C3AED),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Sale of Goods Act, 1930',
      'author': 'Ministry of Law & Justice',
      'category': 'Contract',
      'year': '1930',
      'source': 'India Code',
      'desc': 'Governs contracts for the sale and delivery of goods.',
      'emoji': '🤝', 'color': Color(0xFF7C3AED),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Carlill v. Carbolic Smoke Ball Co.',
      'author': 'Classic Contract Law Case',
      'category': 'Contract',
      'year': '1893',
      'source': 'Indian Kanoon',
      'desc': 'Foundational case on offer and acceptance, widely cited in Indian courts.',
      'emoji': '⚖️', 'color': Color(0xFF7C3AED),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'Contract Act — Bare Text & Amendments',
      'author': 'LatestLaws.com',
      'category': 'Contract',
      'year': '',
      'source': 'latestlaws.com',
      'desc': 'Searchable bare-act text with amendment history.',
      'emoji': '📄', 'color': Color(0xFFD97706),
      'url': 'https://www.latestlaws.com/bare-acts/central-acts-rules/',
    },
    {
      'title': 'Law of Contracts — Video Course',
      'author': 'NPTEL / IIT Faculty',
      'category': 'Contract',
      'year': '',
      'source': 'NPTEL',
      'desc': 'Free video course on contract formation, breach and remedies.',
      'emoji': '🎓', 'color': Color(0xFF0EA5E9),
      'url': 'https://nptel.ac.in/courses',
    },
    // ── Family ──────────────────────────────────
    {
      'title': 'Hindu Marriage Act, 1955',
      'author': 'Ministry of Law & Justice',
      'category': 'Family',
      'year': '1955',
      'source': 'India Code',
      'desc': 'Governs marriage and divorce for Hindus, Sikhs, Jains and Buddhists.',
      'emoji': '👫', 'color': Color(0xFFE91E8C),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Special Marriage Act, 1954',
      'author': 'Ministry of Law & Justice',
      'category': 'Family',
      'year': '1954',
      'source': 'India Code',
      'desc': 'Provides for civil marriage irrespective of religion.',
      'emoji': '👫', 'color': Color(0xFFE91E8C),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Hindu Succession Act, 1956',
      'author': 'Ministry of Law & Justice',
      'category': 'Family',
      'year': '1956',
      'source': 'India Code',
      'desc': 'Governs inheritance and succession among Hindus.',
      'emoji': '👨‍👩‍👧', 'color': Color(0xFFE91E8C),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Mohd. Ahmed Khan v. Shah Bano Begum',
      'author': 'Supreme Court of India',
      'category': 'Family',
      'year': '1985',
      'source': 'Indian Kanoon',
      'desc': 'Landmark maintenance case under family law and Section 125 CrPC.',
      'emoji': '⚖️', 'color': Color(0xFFE91E8C),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'Protection of Women from Domestic Violence Act, 2005',
      'author': 'Ministry of Law & Justice',
      'category': 'Family',
      'year': '2005',
      'source': 'India Code',
      'desc': 'Provides civil remedies and protection against domestic violence.',
      'emoji': '🛡️', 'color': Color(0xFFE91E8C),
      'url': 'https://www.indiacode.nic.in/',
    },
    // ── Property ────────────────────────────────
    {
      'title': 'Transfer of Property Act, 1882',
      'author': 'Ministry of Law & Justice',
      'category': 'Property',
      'year': '1882',
      'source': 'India Code',
      'desc': 'Governs the transfer of immovable property in India.',
      'emoji': '🏠', 'color': Color(0xFFD97706),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Registration Act, 1908',
      'author': 'Ministry of Law & Justice',
      'category': 'Property',
      'year': '1908',
      'source': 'India Code',
      'desc': 'Governs compulsory and optional registration of documents.',
      'emoji': '🏠', 'color': Color(0xFFD97706),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Indian Stamp Act, 1899',
      'author': 'Ministry of Law & Justice',
      'category': 'Property',
      'year': '1899',
      'source': 'India Code',
      'desc': 'Governs stamp duty payable on legal instruments.',
      'emoji': '🏠', 'color': Color(0xFFD97706),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Real Estate (Regulation and Development) Act, 2016',
      'author': 'Ministry of Law & Justice',
      'category': 'Property',
      'year': '2016',
      'source': 'India Code',
      'desc': 'Regulates the real estate sector and protects home buyers.',
      'emoji': '🏢', 'color': Color(0xFFD97706),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Property Law — Bare Acts Collection',
      'author': 'LatestLaws.com',
      'category': 'Property',
      'year': '',
      'source': 'latestlaws.com',
      'desc': 'Searchable collection of property-related central legislation.',
      'emoji': '📄', 'color': Color(0xFFD97706),
      'url': 'https://www.latestlaws.com/bare-acts/central-acts-rules/',
    },
    // ── Company ─────────────────────────────────
    {
      'title': 'Companies Act, 2013',
      'author': 'Ministry of Law & Justice',
      'category': 'Company',
      'year': '2013',
      'source': 'India Code',
      'desc': 'Governs incorporation, governance and winding up of companies in India.',
      'emoji': '🏢', 'color': Color(0xFF0EA5E9),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Limited Liability Partnership Act, 2008',
      'author': 'Ministry of Law & Justice',
      'category': 'Company',
      'year': '2008',
      'source': 'India Code',
      'desc': 'Governs the formation and regulation of LLPs.',
      'emoji': '🏢', 'color': Color(0xFF0EA5E9),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Competition Act, 2002',
      'author': 'Ministry of Law & Justice',
      'category': 'Company',
      'year': '2002',
      'source': 'India Code',
      'desc': 'Prevents anti-competitive practices in Indian markets.',
      'emoji': '🏢', 'color': Color(0xFF0EA5E9),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Company Law — Free Course',
      'author': 'UGC / SWAYAM',
      'category': 'Company',
      'year': '',
      'source': 'swayam.gov.in',
      'desc': 'Free UGC-approved course covering company law fundamentals.',
      'emoji': '🎓', 'color': Color(0xFF0288D1),
      'url': 'https://swayam.gov.in/',
    },
    {
      'title': 'Company Law — Student Articles',
      'author': 'Legal Service India',
      'category': 'Company',
      'year': '',
      'source': 'legalserviceindia.com',
      'desc': 'Free articles explaining corporate governance and company law.',
      'emoji': '📝', 'color': Color(0xFFD97706),
      'url': 'https://www.legalserviceindia.com/',
    },
    // ── Evidence ────────────────────────────────
    {
      'title': 'Indian Evidence Act, 1872',
      'author': 'Ministry of Law & Justice',
      'category': 'Evidence',
      'year': '1872',
      'source': 'India Code',
      'desc': 'Governs admissibility and appreciation of evidence in Indian courts.',
      'emoji': '🔍', 'color': Color(0xFF00897B),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': '69th Report on the Indian Evidence Act',
      'author': 'Law Commission of India',
      'category': 'Evidence',
      'year': '1977',
      'source': 'lawcommissionofindia.nic.in',
      'desc': 'Comprehensive review and reform recommendations on the Evidence Act.',
      'emoji': '📑', 'color': Color(0xFF00897B),
      'url': 'https://lawcommissionofindia.nic.in/',
    },
    {
      'title': 'State of U.P. v. Raj Narain',
      'author': 'Supreme Court of India',
      'category': 'Evidence',
      'year': '1975',
      'source': 'Indian Kanoon',
      'desc': 'Landmark case on privilege and admissibility of evidence.',
      'emoji': '⚖️', 'color': Color(0xFF00897B),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'Law of Evidence — Video Course',
      'author': 'NPTEL / IIT Faculty',
      'category': 'Evidence',
      'year': '',
      'source': 'NPTEL',
      'desc': 'Free video course on the principles of evidence law.',
      'emoji': '🎓', 'color': Color(0xFF0EA5E9),
      'url': 'https://nptel.ac.in/courses',
    },
    {
      'title': 'Law of Evidence — Study Material',
      'author': 'IGNOU',
      'category': 'Evidence',
      'year': '',
      'source': 'eGyanKosh',
      'desc': 'Free open-access study units on evidence law from IGNOU\'s law programmes.',
      'emoji': '📚', 'color': Color(0xFF7C3AED),
      'url': 'https://egyankosh.ac.in/simple-search?query=law',
    },
    // ── Judiciary ───────────────────────────────
    {
      'title': 'Judicial Training & Judgment-Writing Resources',
      'author': 'National Judicial Academy',
      'category': 'Judiciary',
      'year': '',
      'source': 'nja.gov.in',
      'desc': 'Training material and guidance for judicial exam aspirants.',
      'emoji': '🏛️', 'color': Color(0xFF1565C0),
      'url': 'https://nja.gov.in/',
    },
    {
      'title': 'Judicial Reform Reports',
      'author': 'Law Commission of India',
      'category': 'Judiciary',
      'year': '',
      'source': 'lawcommissionofindia.nic.in',
      'desc': 'Reports on judicial appointments, pendency and court reform.',
      'emoji': '📑', 'color': Color(0xFF00897B),
      'url': 'https://lawcommissionofindia.nic.in/',
    },
    {
      'title': 'Judicial Services — Eligibility & Standards',
      'author': 'Bar Council of India',
      'category': 'Judiciary',
      'year': '',
      'source': 'barcouncilofindia.org',
      'desc': 'Official guidance on eligibility and standards for judicial services.',
      'emoji': '⚖️', 'color': Color(0xFF059669),
      'url': 'https://www.barcouncilofindia.org/',
    },
    {
      'title': 'Judgment Search for Judiciary Prep',
      'author': 'Indian Kanoon',
      'category': 'Judiciary',
      'year': '',
      'source': 'Indian Kanoon',
      'desc': 'Search and read full judgments — practice material for answer writing.',
      'emoji': '🔍', 'color': Color(0xFF1565C0),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'Judicial Process — Free Course',
      'author': 'UGC / SWAYAM',
      'category': 'Judiciary',
      'year': '',
      'source': 'swayam.gov.in',
      'desc': 'Free course on the structure and functioning of the Indian judiciary.',
      'emoji': '🎓', 'color': Color(0xFF0288D1),
      'url': 'https://swayam.gov.in/',
    },
    // ── Bare Acts ───────────────────────────────
    {
      'title': 'Arbitration and Conciliation Act, 1996',
      'author': 'Ministry of Law & Justice',
      'category': 'Bare Acts',
      'year': '1996',
      'source': 'India Code',
      'desc': 'Governs arbitration and alternative dispute resolution in India.',
      'emoji': '📄', 'color': Color(0xFF059669),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Negotiable Instruments Act, 1881',
      'author': 'Ministry of Law & Justice',
      'category': 'Bare Acts',
      'year': '1881',
      'source': 'India Code',
      'desc': 'Governs cheques, promissory notes and bills of exchange.',
      'emoji': '📄', 'color': Color(0xFF059669),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Consumer Protection Act, 2019',
      'author': 'Ministry of Law & Justice',
      'category': 'Bare Acts',
      'year': '2019',
      'source': 'India Code',
      'desc': 'Protects consumer rights and provides redressal mechanisms.',
      'emoji': '📄', 'color': Color(0xFF059669),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Right to Information Act, 2005',
      'author': 'Ministry of Law & Justice',
      'category': 'Bare Acts',
      'year': '2005',
      'source': 'India Code',
      'desc': 'Provides citizens the right to access government information.',
      'emoji': '📋', 'color': Color(0xFF059669),
      'url': 'https://www.indiacode.nic.in/',
    },
    {
      'title': 'Central Acts & Rules — Full Index',
      'author': 'Legislative Department, Govt. of India',
      'category': 'Bare Acts',
      'year': '',
      'source': 'legislative.gov.in',
      'desc': 'Official index of all central legislation currently in force.',
      'emoji': '📚', 'color': Color(0xFF7C3AED),
      'url': 'https://legislative.gov.in/central-acts-and-rules/',
    },
    // ── Legal Research ──────────────────────────
    {
      'title': 'Indian Kanoon — Case Law Database',
      'author': 'Indian Kanoon',
      'category': 'Legal Research',
      'year': '',
      'source': 'indiankanoon.org',
      'desc': 'Free search engine for Supreme Court and High Court judgments.',
      'emoji': '🔍', 'color': Color(0xFF1565C0),
      'url': 'https://indiankanoon.org',
    },
    {
      'title': 'LiveLaw — Legal News & Case Analysis',
      'author': 'LiveLaw Media',
      'category': 'Legal Research',
      'year': '',
      'source': 'livelaw.in',
      'desc': 'Daily coverage and analysis of Indian court judgments.',
      'emoji': '📰', 'color': Color(0xFF7C3AED),
      'url': 'https://www.livelaw.in/supreme-court',
    },
    {
      'title': 'Bar & Bench — Legal Research & News',
      'author': 'Bar & Bench',
      'category': 'Legal Research',
      'year': '',
      'source': 'barandbench.com',
      'desc': 'In-depth legal news, interviews and case analysis.',
      'emoji': '📰', 'color': Color(0xFF0EA5E9),
      'url': 'https://www.barandbench.com',
    },
    {
      'title': 'Open Access Law Research Material',
      'author': 'IGNOU',
      'category': 'Legal Research',
      'year': '',
      'source': 'eGyanKosh',
      'desc': 'Free, open-licence research and study material across law subjects.',
      'emoji': '📚', 'color': Color(0xFF7C3AED),
      'url': 'https://egyankosh.ac.in/simple-search?query=law',
    },
    {
      'title': 'Law Commission Reports — Full Archive',
      'author': 'Law Commission of India',
      'category': 'Legal Research',
      'year': '',
      'source': 'lawcommissionofindia.nic.in',
      'desc': 'Complete archive of Law Commission reports — a key legal research resource.',
      'emoji': '📑', 'color': Color(0xFF00897B),
      'url': 'https://lawcommissionofindia.nic.in/',
    },
    // ── General ─────────────────────────────────
    {
      'title': 'Intellectual Property Law Resources',
      'author': 'World Intellectual Property Organization',
      'category': 'General',
      'year': '',
      'source': 'wipo.int',
      'desc': 'Free official resources on copyright, patents and trademark law.',
      'emoji': '💡', 'color': Color(0xFFD97706),
      'url': 'https://www.wipo.int/en/web/copyright',
    },
    {
      'title': 'Human Rights Law Resources',
      'author': 'National Human Rights Commission, India',
      'category': 'General',
      'year': '',
      'source': 'nhrc.nic.in',
      'desc': 'Reports, guidelines and case material on human rights law in India.',
      'emoji': '🕊️', 'color': Color(0xFF059669),
      'url': 'https://nhrc.nic.in/',
    },
    {
      'title': 'Rules of Professional Conduct & Ethics',
      'author': 'Bar Council of India',
      'category': 'General',
      'year': '',
      'source': 'barcouncilofindia.org',
      'desc': 'Official rules on legal ethics and professional standards for advocates.',
      'emoji': '⚖️', 'color': Color(0xFF059669),
      'url': 'https://www.barcouncilofindia.org/',
    },
    {
      'title': 'Legal Research & Writing Methodology',
      'author': 'NPTEL / IIT Faculty',
      'category': 'General',
      'year': '',
      'source': 'NPTEL',
      'desc': 'Free video course on legal research methods and academic writing.',
      'emoji': '🎓', 'color': Color(0xFF0EA5E9),
      'url': 'https://nptel.ac.in/courses',
    },
    {
      'title': 'Indian Legal System — General Knowledge Articles',
      'author': 'Legal Service India',
      'category': 'General',
      'year': '',
      'source': 'legalserviceindia.com',
      'desc': 'Wide-ranging free articles covering the basics of the Indian legal system.',
      'emoji': '📝', 'color': Color(0xFFD97706),
      'url': 'https://www.legalserviceindia.com/',
    },
  ];

  List<Map<String, dynamic>> get _filteredLibrary {
    return _library.where((r) {
      final matchesCategory =
          _libraryCategory == 'All' || r['category'] == _libraryCategory;
      final q = _librarySearch.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          (r['title'] as String).toLowerCase().contains(q) ||
          (r['author'] as String).toLowerCase().contains(q) ||
          (r['category'] as String).toLowerCase().contains(q);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  void _openResource(Map<String, dynamic> r) {
    HapticFeedback.lightImpact();
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NewsWebViewScreen(
                url: r['url'], title: r['title'], source: r['source'])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
          child: Column(children: [
        Container(
          color: _bgCard,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            const Text('Study Library',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${_library.length} resources',
                  style: const TextStyle(
                      color: _blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        Expanded(
            child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
                'Free bare acts, judgments, courses and research for LLB, judiciary and legal-practice prep.',
                style: TextStyle(color: _textMuted, fontSize: 11)),
            const SizedBox(height: 12),

            // Search
            TextField(
              onChanged: (v) => setState(() => _librarySearch = v),
              style: const TextStyle(color: _textPri, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by title, author or subject',
                hintStyle: const TextStyle(color: _textMuted, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: _textMuted, size: 20),
                filled: true,
                fillColor: _bgCard,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),

            // Category filter
            SizedBox(
              height: 34,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _libraryCategories.length,
                itemBuilder: (_, i) {
                  final cat = _libraryCategories[i];
                  final sel = _libraryCategory == cat;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _libraryCategory = cat);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? _blue : _bgCard,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: sel ? _blue : _border),
                      ),
                      child: Text(cat,
                          style: TextStyle(
                              color: sel ? Colors.white : _textMuted,
                              fontSize: 11,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text('${_filteredLibrary.length} resources • tap Open to read',
                style: const TextStyle(color: _textMuted, fontSize: 11)),
            const SizedBox(height: 12),

            if (_filteredLibrary.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: Text('No resources match your search.',
                        style: TextStyle(color: _textMuted, fontSize: 12))),
              )
            else
              ..._filteredLibrary.map((r) {
                final color = r['color'] as Color;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                            color: _blue.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ]),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Center(
                            child: Text(r['emoji'],
                                style: const TextStyle(fontSize: 20)))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(r['title'],
                              style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                              maxLines: 2),
                          const SizedBox(height: 2),
                          Text(r['author'],
                              style: const TextStyle(
                                  color: _textMuted, fontSize: 10)),
                          const SizedBox(height: 6),
                          Text(r['desc'],
                              style: const TextStyle(
                                  color: _textPri, fontSize: 11, height: 1.35),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(children: [
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(r['category'],
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700))),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    (r['year'] as String).isNotEmpty
                                        ? '${r['source']} • ${r['year']}'
                                        : r['source'],
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 9),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                          ]),
                        ])),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _openResource(r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('Open',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                );
              }),
          ],
        )),
      ])),
    );
  }
}

// ── News Tab ───────────────────────────────────────
class _NewsTab extends StatelessWidget {
  const _NewsTab();

  static const List<Map<String, dynamic>> _news = [
    {
      'title': 'Supreme Court upholds Right to Privacy as Fundamental Right',
      'source': 'Bar & Bench',
      'time': '2 hours ago',
      'cat': 'Supreme Court',
      'emoji': '🏛️',
      'color': Color(0xFF1565C0),
      'url': 'https://www.barandbench.com'
    },
    {
      'title': 'New BNS replaces IPC: Key changes every lawyer must know',
      'source': 'LiveLaw',
      'time': '4 hours ago',
      'cat': 'Criminal',
      'emoji': '⚖️',
      'color': Color(0xFFDC2626),
      'url': 'https://www.livelaw.in'
    },
    {
      'title': 'Delhi HC: Anticipatory bail cannot be refused mechanically',
      'source': 'LiveLaw',
      'time': '6 hours ago',
      'cat': 'High Court',
      'emoji': '🔍',
      'color': Color(0xFF00897B),
      'url': 'https://www.livelaw.in/high-court/delhi-high-court'
    },
    {
      'title': 'SC: Mere FIR registration not ground for denying bail',
      'source': 'Bar & Bench',
      'time': '8 hours ago',
      'cat': 'Supreme Court',
      'emoji': '⚖️',
      'color': Color(0xFF0288D1),
      'url': 'https://www.barandbench.com'
    },
    {
      'title': 'POCSO Act: SC clarifies definition of aggravated assault',
      'source': 'LawBeat',
      'time': '1 day ago',
      'cat': 'Criminal',
      'emoji': '🔒',
      'color': Color(0xFFDC2626),
      'url': 'https://lawbeat.in'
    },
    {
      'title': 'Bombay HC: Landlord cannot evict tenant without proper notice',
      'source': 'LawBeat',
      'time': '1 day ago',
      'cat': 'Property',
      'emoji': '🏠',
      'color': Color(0xFFD97706),
      'url': 'https://lawbeat.in'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
          child: Column(children: [
        Container(
          color: _bgCard,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            const Text('Live Court News',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: Colors.red, size: 8),
                SizedBox(width: 4),
                Text('LIVE',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
            const Spacer(),
            _SrcBadge('LL', _blue),
            const SizedBox(width: 4),
            _SrcBadge('B&B', _skyBlue),
            const SizedBox(width: 4),
            _SrcBadge('LB', const Color(0xFF00897B)),
          ]),
        ),
        Expanded(
            child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _news.length,
          itemBuilder: (_, i) {
            final n = _news[i];
            final color = n['color'] as Color;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                // Opens in browser via url_launcher or push webview
                context.push(
                    '/student/news-detail?url=${Uri.encodeComponent(n['url'])}&title=${Uri.encodeComponent(n['title'])}&source=${Uri.encodeComponent(n['source'])}');
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                          color: _blue.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ]),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16))),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n['emoji'],
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(n['title'],
                                  style: const TextStyle(
                                      color: _textPri,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      height: 1.3))),
                        ]),
                  ),
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(n['cat'],
                                style: TextStyle(
                                    color: color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700))),
                        const SizedBox(width: 8),
                        Text(n['source'],
                            style: const TextStyle(
                                color: _textMuted, fontSize: 11)),
                        const Spacer(),
                        Text(n['time'],
                            style: const TextStyle(
                                color: _textMuted, fontSize: 10)),
                      ])),
                ]),
              ),
            );
          },
        )),
      ])),
    );
  }
}

class _SrcBadge extends StatelessWidget {
  final String name;
  final Color color;
  const _SrcBadge(this.name, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Text(name,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      );
}

// ── Lawyers Tab ────────────────────────────────────
class _LawyersTab extends StatelessWidget {
  final List<dynamic> lawyers;
  const _LawyersTab({required this.lawyers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
          child: Column(children: [
        Container(
            color: _bgCard,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Talk to Lawyers',
                      style: TextStyle(
                          color: _textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  Text('Get expert legal guidance',
                      style: TextStyle(color: _textMuted, fontSize: 13)),
                ])),
        Expanded(
          child: lawyers.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                              color: _blue.withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.people_rounded,
                              color: _blue, size: 40)),
                      const SizedBox(height: 16),
                      const Text('No lawyers available',
                          style: TextStyle(color: _textMuted, fontSize: 16)),
                    ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lawyers.length,
                  itemBuilder: (_, i) {
                    final l = lawyers[i];
                    final name = l['name'] ?? 'Advocate';
                    final designation = l['designation'] ?? 'Advocate';
                    final firm = l['firm_name'] ?? '';
                    final initials =
                        name.isNotEmpty ? name[0].toUpperCase() : 'A';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: _bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _border, width: 0.8),
                          boxShadow: [
                            BoxShadow(
                                color: _blue.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ]),
                      child: Row(children: [
                        Container(
                            width: 50,
                            height: 50,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Color(0xFF1A237E),
                                Color(0xFF1565C0)
                              ]),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                                child: Text(initials,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20)))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(name,
                                  style: const TextStyle(
                                      color: _textPri,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              Text(designation,
                                  style: const TextStyle(
                                      color: _blue, fontSize: 12)),
                              if (firm.isNotEmpty)
                                Text(firm,
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 11)),
                            ])),
                        GestureDetector(
                          onTap: () => context.push(
                              '/student/lawyer/${l['id']}?name=${Uri.encodeComponent(name)}'),
                          child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: _blue.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _border)),
                              child: const Icon(Icons.person_rounded,
                                  color: _blue, size: 18)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.heavyImpact();
                            try {
                              final res = await DioClient.instance.post(
                                  '/chat/rooms',
                                  data: {'lawyer_id': l['id']});
                              final roomId = res.data['data']['id'];
                              if (context.mounted)
                                context.push(
                                    '/chat/$roomId?name=${Uri.encodeComponent(name)}');
                            } catch (e) {}
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFF1565C0),
                                Color(0xFF0288D1)
                              ]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_rounded,
                                      color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Chat',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                ]),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ])),
    );
  }
}

// ── Profile Tab ────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final AuthProvider auth;
  final Map<String, dynamic> progress;
  const _ProfileTab({required this.auth, required this.progress});

  @override
  Widget build(BuildContext context) {
    final name = auth.user?.name ?? '';
    final email = auth.user?.email ?? '';
    final phone = auth.user?.phone ?? 'Not added';
    final xp = progress['xp'] ?? 0;
    final level = progress['level'] ?? 1;
    final cases = progress['total_cases_completed'] ?? 0;
    final streak = progress['streak'] ?? 0;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'S';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
          child: ListView(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [
              Color(0xFF0A1628),
              Color(0xFF1A237E),
              Color(0xFF1565C0)
            ], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(children: [
            Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4), width: 2.5),
                ),
                child: Center(
                    child: Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 36)))),
            const SizedBox(height: 12),
            Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('LAW STUDENT',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _ProfStat('Level $level', 'Level', Icons.military_tech_rounded),
              _ProfStat('$xp XP', 'XP', Icons.bolt_rounded),
              _ProfStat('$cases', 'Cases', Icons.gavel_rounded),
              _ProfStat(
                  '$streak 🔥', 'Streak', Icons.local_fire_department_rounded),
            ]),
          ]),
        ),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Personal Info',
                      style: TextStyle(
                          color: _textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600))),
              const SizedBox(height: 10),
              _InfoTile(Icons.person_outline_rounded, 'Full Name', name, _blue),
              const SizedBox(height: 8),
              _InfoTile(Icons.email_outlined, 'Email', email, _skyBlue),
              const SizedBox(height: 8),
              _InfoTile(Icons.phone_outlined, 'Phone', phone,
                  const Color(0xFF00897B)),
              const SizedBox(height: 20),
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Quick Actions',
                      style: TextStyle(
                          color: _textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _ActionTile('🏆', 'Leaderboard', _gold,
                        () => context.push('/student/leaderboard'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _ActionTile('💬', 'AI Lawyer', _skyBlue,
                        () => context.push('/student/ai-lawyer'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _ActionTile('📚', 'Law Books', _blue,
                        () => context.push('/student/law-books'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _ActionTile('📖', 'Legal Notes', _skyBlue,
                        () => context.push('/student/notes'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _ActionTile('❓', 'Quiz', const Color(0xFF7C3AED),
                        () => context.push('/student/quiz'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _ActionTile(
                        '🏛️',
                        'Mock Court',
                        const Color(0xFF00897B),
                        () => context.push('/student/mock-court'))),
              ]),
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
}

class _ProfStat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _ProfStat(this.value, this.label, this.icon);
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14)),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ]);
}

Widget _InfoTile(IconData icon, String label, String value, Color color) =>
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _blue.withValues(alpha: 0.04),
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 11)),
          Text(value,
              style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );

class _ActionTile extends StatelessWidget {
  final String emoji, label;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile(this.emoji, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                    color: _blue.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}
