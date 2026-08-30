import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFFFF0F5);
const _bgCard = Color(0xFFFFFFFF);
const _pink = Color(0xFFE91E8C);
const _border = Color(0xFFFFD6EB);
const _textPri = Color(0xFF1A1A2E);
const _textMuted = Color(0xFF6B6B8A);

class LawyerProfileScreen extends StatefulWidget {
  final String lawyerId, lawyerName;
  const LawyerProfileScreen(
      {super.key, required this.lawyerId, required this.lawyerName});
  @override
  State<LawyerProfileScreen> createState() => _LawyerProfileScreenState();
}

class _LawyerProfileScreenState extends State<LawyerProfileScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic> _profile = {};
  List<dynamic> _wonCases = [];
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
    _loadProfile();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final res =
          await DioClient.instance.get('/student/lawyer/${widget.lawyerId}');
      setState(() {
        _profile = res.data['data']?['lawyer'] ?? {};
        _wonCases = res.data['data']?['won_cases'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _profile = {'name': widget.lawyerName};
        _loading = false;
      });
    }
  }

  Future<void> _startChat() async {
    HapticFeedback.heavyImpact();
    try {
      final res = await DioClient.instance
          .post('/chat/rooms', data: {'lawyer_id': widget.lawyerId});
      final roomId = res.data['data']['id'];
      if (mounted) context.push('/chat/$roomId?name=${widget.lawyerName}');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not start chat. Try again!'),
            backgroundColor: Color(0xFFD9534F)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile['name'] ?? widget.lawyerName;
    final designation = _profile['designation'] ?? 'Advocate';
    final firmName = _profile['firm_name'] ?? '';
    final speciality = _profile['speciality'] ?? '';
    final city = _profile['city'] ?? '';
    final state = _profile['state'] ?? '';
    final totalCases = _profile['total_cases'] ?? 0;
    final wonCasesCount = _profile['won_cases_count'] ?? _wonCases.length;
    final experience = _profile['experience_years'] ?? 0;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'L';
    final location = [city, state].where((s) => s.isNotEmpty).join(', ');

    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _pink))
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(
                    child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Color(0xFFB5166E),
                      Color(0xFFE91E8C),
                      Color(0xFFFF6BB3)
                    ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: SafeArea(
                      child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                        child: Row(children: [
                          IconButton(
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: Colors.white),
                              onPressed: () => context.pop()),
                          const Spacer(),
                        ])),
                    Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF546E7A), width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 16)
                            ]),
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
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.gavel_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(designation,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    if (firmName.isNotEmpty)
                      Text(firmName,
                          style: const TextStyle(
                              color: const Color(0xFF546E7A), fontSize: 13)),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_on_rounded,
                                color: const Color(0xFF546E7A), size: 14),
                            const SizedBox(width: 4),
                            Text(location,
                                style: const TextStyle(
                                    color: const Color(0xFF546E7A),
                                    fontSize: 12)),
                          ]),
                    ],
                    const SizedBox(height: 20),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(children: [
                          _StatCard('$totalCases', 'Total Cases',
                              Icons.gavel_rounded, Colors.white),
                          const SizedBox(width: 10),
                          _StatCard(
                              '$wonCasesCount',
                              'Cases Won',
                              Icons.emoji_events_rounded,
                              const Color(0xFFFFD700)),
                          const SizedBox(width: 10),
                          _StatCard(
                              '$experience',
                              'Yrs Exp',
                              Icons.workspace_premium_rounded,
                              const Color(0xFF546E7A)),
                        ])),
                    const SizedBox(height: 20),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _startChat,
                            icon: const Icon(Icons.chat_rounded,
                                color: _pink, size: 18),
                            label: const Text('Start Conversation',
                                style: TextStyle(
                                    color: _pink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                          ),
                        )),
                    const SizedBox(height: 20),
                  ])),
                )),
                SliverToBoxAdapter(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (speciality.isNotEmpty) ...[
                          const Text('⚖️ Specialisation',
                              style: TextStyle(
                                  color: _textPri,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: _bgCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: _pink.withValues(alpha: 0.2)),
                                  boxShadow: [
                                    BoxShadow(
                                        color: _pink.withValues(alpha: 0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2))
                                  ]),
                              child: Row(children: [
                                Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                        color: _pink.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: const Icon(
                                        Icons.workspace_premium_rounded,
                                        color: _pink,
                                        size: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(speciality,
                                        style: const TextStyle(
                                            color: _textPri,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14))),
                              ])),
                          const SizedBox(height: 20),
                        ],
                        const Text('📋 Practice Areas',
                            style: TextStyle(
                                color: _textPri,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              'Criminal Law',
                              'Civil Law',
                              'Family Law',
                              'Constitutional Law',
                              'Property Law',
                              'Corporate Law'
                            ]
                                .map((area) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: _pink.withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: _pink.withValues(alpha: 0.25))),
                                      child: Text(area,
                                          style: const TextStyle(
                                              color: _pink,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList()),
                        const SizedBox(height: 20),
                        const Text('✨ Why Choose This Lawyer?',
                            style: TextStyle(
                                color: _textPri,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        ...[
                          {
                            'icon': '⚡',
                            'title': 'Fast Response',
                            'desc': 'Responds within 24 hours'
                          },
                          {
                            'icon': '🔒',
                            'title': 'Confidential',
                            'desc': 'Your case stays private'
                          },
                          {
                            'icon': '💡',
                            'title': 'Expert Advice',
                            'desc': 'Years of legal experience'
                          },
                          {
                            'icon': '📞',
                            'title': 'Always Available',
                            'desc': 'Chat anytime, anywhere'
                          },
                        ].map((item) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: _bgCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: _border, width: 0.8),
                                  boxShadow: [
                                    BoxShadow(
                                        color: _pink.withValues(alpha: 0.04),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2))
                                  ]),
                              child: Row(children: [
                                Text(item['icon']!,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(item['title']!,
                                          style: const TextStyle(
                                              color: _textPri,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13)),
                                      Text(item['desc']!,
                                          style: const TextStyle(
                                              color: _textMuted, fontSize: 11)),
                                    ])),
                              ]),
                            )),
                        const SizedBox(height: 80),
                      ]),
                )),
              ]),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
            color: _bgCard,
            border: Border(top: BorderSide(color: _border, width: 0.8)),
            boxShadow: [
              BoxShadow(
                  color: _pink.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -2))
            ]),
        child: SafeArea(
            child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _startChat,
            icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 18),
            label: Text('Chat with $name',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        )),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatCard(this.value, this.label, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label,
              style:
                  const TextStyle(color: const Color(0xFF546E7A), fontSize: 9),
              textAlign: TextAlign.center),
        ]),
      ));
}
