import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFFFF0F5);
const _bgCard = Color(0xFFFFFFFF);
const _pink = Color(0xFFE91E8C);
const _border = Color(0xFFFFD6EB);
const _textPri = Color(0xFF1A1A2E);
const _textMuted = Color(0xFF6B6B8A);

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> _entries = [];
  bool _loading = true;
  Map<String, dynamic> _myProgress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DioClient.instance.get('/student/leaderboard'),
        DioClient.instance.get('/student/progress'),
      ]);
      setState(() {
        _entries = results[0].data['data'] ?? [];
        _myProgress = results[1].data['data']?['progress'] ?? {};
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myXP = _myProgress['xp'] ?? 0;
    final myLevel = _myProgress['level'] ?? 1;
    final myCases = _myProgress['total_cases_completed'] ?? 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _pink,
        title: const Text('🏆 Leaderboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _load)
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _pink))
          : RefreshIndicator(
              color: _pink,
              backgroundColor: _bgCard,
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // My Stats
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFFB5166E),
                      Color(0xFFE91E8C),
                      Color(0xFFFF6BB3)
                    ]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: _pink.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: Column(children: [
                    const Text('My Stats',
                        style: TextStyle(
                            color: const Color(0xFF546E7A), fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MyStat('Level $myLevel', 'Level',
                              Icons.military_tech_rounded),
                          _MyStat('$myXP XP', 'Total XP', Icons.bolt_rounded),
                          _MyStat(
                              '$myCases', 'Cases Done', Icons.gavel_rounded),
                        ]),
                  ]),
                ),
                const SizedBox(height: 20),

                // Top 3 Podium
                if (_entries.length >= 3) ...[
                  const Text('Top Champions',
                      style: TextStyle(
                          color: _textPri,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                        child: _PodiumCard(
                            _entries[1], 2, const Color(0xFF94A3B8))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _PodiumCard(
                            _entries[0], 1, const Color(0xFFD97706))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _PodiumCard(
                            _entries[2], 3, const Color(0xFFCD7F32))),
                  ]),
                  const SizedBox(height: 20),
                ],

                const Text('All Rankings',
                    style: TextStyle(
                        color: _textPri,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                if (_entries.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                        color: _bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border, width: 0.8)),
                    child: const Column(children: [
                      Text('🏆', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('No scores yet!',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      Text('Play a challenge to appear here',
                          style: TextStyle(color: _textMuted)),
                    ]),
                  )
                else
                  ..._entries.asMap().entries.map((e) {
                    final rank = e.key + 1;
                    final entry = e.value;
                    final xp = (entry['xp'] ?? 0) as int;
                    final level = (entry['level'] ?? 1) as int;
                    final casesWon = (entry['cases_won'] ?? 0) as int;

                    Color rankColor = _textMuted;
                    String rankLabel = '#$rank';
                    if (rank == 1) {
                      rankColor = const Color(0xFFD97706);
                      rankLabel = '🥇';
                    }
                    if (rank == 2) {
                      rankColor = const Color(0xFF94A3B8);
                      rankLabel = '🥈';
                    }
                    if (rank == 3) {
                      rankColor = const Color(0xFFCD7F32);
                      rankLabel = '🥉';
                    }

                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 200 + (e.key * 60)),
                      builder: (_, v, child) => Opacity(
                          opacity: v.clamp(0.0, 1.0),
                          child: Transform.translate(
                              offset: Offset(30 * (1 - v), 0), child: child)),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: rank <= 3
                                    ? rankColor.withValues(alpha: 0.3)
                                    : _border,
                                width: 0.8),
                            boxShadow: [
                              BoxShadow(
                                  color: _pink.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]),
                        child: Row(children: [
                          Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: rankColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle),
                              child: Center(
                                  child: Text(rankLabel,
                                      style: TextStyle(
                                          color: rankColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: rank <= 3 ? 18 : 13)))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(entry['name'] ?? 'Student',
                                    style: const TextStyle(
                                        color: _textPri,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                Text('Level $level  •  $casesWon cases won',
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 11)),
                              ])),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$xp',
                                    style: TextStyle(
                                        color: rankColor,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 20)),
                                const Text('XP',
                                    style: TextStyle(
                                        color: _textMuted, fontSize: 10)),
                              ]),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 80),
              ]),
            ),
    );
  }
}

class _MyStat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _MyStat(this.value, this.label, this.icon);
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ]);
}

class _PodiumCard extends StatelessWidget {
  final dynamic entry;
  final int rank;
  final Color color;
  const _PodiumCard(this.entry, this.rank, this.color);
  @override
  Widget build(BuildContext context) {
    final medals = ['🥇', '🥈', '🥉'];
    final xp = (entry['xp'] ?? 0) as int;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(children: [
        Text(medals[rank - 1], style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 6),
        Text(entry['name'] ?? 'Student',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 4),
        Text('$xp XP',
            style: const TextStyle(
                color: _textPri, fontWeight: FontWeight.w800, fontSize: 14)),
        Text('Lv.${entry['level'] ?? 1}',
            style: const TextStyle(color: _textMuted, fontSize: 10)),
      ]),
    );
  }
}
