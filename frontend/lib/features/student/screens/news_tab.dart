import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/news_service.dart';
import 'news_webview_screen.dart';

// ── Blue/White Theme ──────────────────────────────
const _bg = Color(0xFFF0F4FF);
const _bgCard = Color(0xFFFFFFFF);
const _blue = Color(0xFF1565C0);
const _skyBlue = Color(0xFF0288D1);
const _border = Color(0xFFBBDEFB);
const _textPri = Color(0xFF0A1628);
const _textMuted = Color(0xFF546E7A);

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  int _selectedCategory = 0;
  bool _loading = true;
  String? _error;

  final List<String> _categories = [
    'All',
    'Supreme Court',
    'High Court',
    'Constitutional',
    'Criminal',
    'Family',
    'Property'
  ];

  // Live from LiveLaw's RSS feed (see NewsService) — never hardcoded.
  List<Map<String, dynamic>> _news = [];

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await NewsService.fetchAllNews();
      if (!mounted) return;
      setState(() {
        _news = items
            .map((n) => {
                  ...n,
                  // NewsService's field names -> the ones this screen's
                  // existing cards/webview already expect.
                  'url': n['link'],
                  'color': Color(int.parse(
                      (n['color'] as String? ?? '0xFF1565C0'))),
                })
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load live news. Check your connection.';
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_selectedCategory == 0) return _news;
    return _news
        .where((n) => n['category'] == _categories[_selectedCategory])
        .toList();
  }

  void _openArticle(BuildContext context, Map<String, dynamic> n) {
    HapticFeedback.lightImpact();
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewsWebViewScreen(
              url: n['url'], title: n['title'], source: n['source']),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
          child: Column(children: [
        // Header
        Container(
          color: _bgCard,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Live Court News',
                  style: TextStyle(
                      color: _textPri,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              _BlinkingLive(),
              const Spacer(),
              _SrcBadge('LL', _blue),
              const SizedBox(width: 4),
              _SrcBadge('B&B', _skyBlue),
              const SizedBox(width: 4),
              _SrcBadge('LB', const Color(0xFF00897B)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (_, i) {
                    final sel = _selectedCategory == i;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedCategory = i);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? _blue : _bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? _blue : _border),
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                      color: _blue.withValues(alpha: 0.3),
                                      blurRadius: 8)
                                ]
                              : [],
                        ),
                        child: Text(_categories[i],
                            style: TextStyle(
                                color: sel ? Colors.white : _textMuted,
                                fontSize: 12,
                                fontWeight:
                                    sel ? FontWeight.w700 : FontWeight.w400)),
                      ),
                    );
                  },
                )),
            const SizedBox(height: 6),
            Text('${_filtered.length} stories • tap to read',
                style: const TextStyle(color: _textMuted, fontSize: 11)),
          ]),
        ),

        // News list
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _blue))
                : _error != null
                    ? _buildError()
                    : RefreshIndicator(
                        color: _blue,
                        onRefresh: _loadNews,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final n = _filtered[i];
                            final color = n['color'] as Color;
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration:
                                  Duration(milliseconds: 200 + (i * 60)),
                              curve: Curves.easeOut,
                              builder: (_, v, child) => Opacity(
                                opacity: v.clamp(0.0, 1.0),
                                child: Transform.translate(
                                    offset: Offset(0, 20 * (1 - v)),
                                    child: child),
                              ),
                              child: _NewsCard(
                                  news: n,
                                  color: color,
                                  onTap: () => _openArticle(context, n)),
                            );
                          },
                        ),
                      )),
      ])),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: _textMuted),
            const SizedBox(height: 16),
            Text(_error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textPri, fontSize: 14)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadNews,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text('Retry',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ]),
        ),
      );
}

class _NewsCard extends StatefulWidget {
  final Map<String, dynamic> news;
  final Color color;
  final VoidCallback onTap;
  const _NewsCard(
      {required this.news, required this.color, required this.onTap});
  @override
  State<_NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<_NewsCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 100), vsync: this);
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.news;
    final color = widget.color;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n['emoji'], style: const TextStyle(fontSize: 22)),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(n['category'],
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text(n['source'],
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
                  const Spacer(),
                  Text(n['timeAgo'],
                      style: const TextStyle(color: _textMuted, fontSize: 10)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Icon(Icons.article_rounded, color: color, size: 12),
                  ),
                ])),
          ]),
        ),
      ),
    );
  }
}

class _BlinkingLive extends StatefulWidget {
  @override
  State<_BlinkingLive> createState() => _BlinkingLiveState();
}

class _BlinkingLiveState extends State<_BlinkingLive>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withValues(alpha: 0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FadeTransition(
              opacity: _ctrl,
              child: const Icon(Icons.circle, color: Colors.red, size: 8)),
          const SizedBox(width: 4),
          const Text('LIVE',
              style: TextStyle(
                  color: Colors.red,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ]),
      );
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
