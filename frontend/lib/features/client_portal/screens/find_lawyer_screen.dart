import 'dart:convert';
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

class FindLawyerScreen extends StatefulWidget {
  const FindLawyerScreen({super.key});
  @override
  State<FindLawyerScreen> createState() => _FindLawyerScreenState();
}

class _FindLawyerScreenState extends State<FindLawyerScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _lawyers = [];
  List<dynamic> _filtered = [];
  bool _loading = true;
  // Chat is a premium feature: unlocked with a lawyer only once the client
  // has a paid consultation with them. Populated alongside the lawyer list.
  Set<String> _paidLawyerIds = {};
  String _selectedCategory = 'All';
  String _selectedCity = 'All';

  final List<Map<String, dynamic>> _categories = [
    {'name': 'All', 'icon': '⚖️'},
    {'name': 'Criminal', 'icon': '🔍'},
    {'name': 'Property', 'icon': '🏠'},
    {'name': 'Family', 'icon': '👨‍👩‍👧'},
    {'name': 'Corporate', 'icon': '🏢'},
    {'name': 'Tax', 'icon': '💰'},
    {'name': 'Labour', 'icon': '👷'},
    {'name': 'Consumer', 'icon': '🛒'},
    {'name': 'Civil', 'icon': '📋'},
  ];

  @override
  void initState() {
    super.initState();
    _loadLawyers();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLawyers() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/student/lawyers');
      final paidIds = await _loadPaidLawyerIds();
      setState(() {
        _lawyers = res.data['data'] ?? [];
        _filtered = _lawyers;
        _paidLawyerIds = paidIds;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// Lawyers this client has at least one paid consultation with — chat is
  /// gated on that, not on a general subscription, since a client's only
  /// paid relationship in this app is per-lawyer consultation.
  Future<Set<String>> _loadPaidLawyerIds() async {
    try {
      final res = await DioClient.instance.get('/portal/my-consultations');
      final list = res.data['data'] as List<dynamic>? ?? [];
      return list
          .where((c) => c['payment_status'] == 'paid')
          .map((c) => c['lawyer_id'] as String)
          .toSet();
    } catch (e) {
      return {};
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _lawyers.where((l) {
        final name = (l['name'] ?? '').toLowerCase();
        final designation = (l['designation'] ?? '').toLowerCase();
        final city = (l['city'] ?? '').toLowerCase();
        final speciality = (l['speciality'] ?? '').toLowerCase();
        final firmName = (l['firm_name'] ?? '').toLowerCase();

        final matchQuery = query.isEmpty ||
            name.contains(query) ||
            designation.contains(query) ||
            city.contains(query) ||
            speciality.contains(query) ||
            firmName.contains(query);

        // The lawyer's actual specialization — GetAllLawyers now returns it
        // as practice_areas, a comma-separated list of the case_type values
        // on that lawyer's own cases (there is no separate specialization
        // field; designation/speciality above are a job title and an
        // always-empty field respectively, which is why this never matched
        // anything before). Compared as trimmed, lower-cased tokens so
        // "Tax"/"tax "/"TAX" all match regardless of how it was typed on a
        // case.
        final practiceAreas = (l['practice_areas'] ?? '')
            .toString()
            .toLowerCase()
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();

        final matchCategory = _selectedCategory == 'All' ||
            practiceAreas.contains(_selectedCategory.toLowerCase());

        final matchCity = _selectedCity == 'All' ||
            city.contains(_selectedCity.toLowerCase());

        return matchQuery && matchCategory && matchCity;
      }).toList();
    });
  }

  void _selectCategory(String cat) {
    setState(() => _selectedCategory = cat);
    _applyFilter();
  }

  List<String> get _cities {
    final cities = <String>{'All'};
    for (final l in _lawyers) {
      final city = (l['city'] ?? '').toString().trim();
      if (city.isNotEmpty) cities.add(city);
    }
    return cities.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // ── Header ──────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Text('Find a Lawyer',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                    const SizedBox(width: 48),
                  ]),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12)
                        ]),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: _textPri, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by name, city, speciality...',
                        hintStyle:
                            const TextStyle(color: _textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: _green, size: 22),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded,
                                    color: _textMuted, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _applyFilter();
                                })
                            : null,
                        border: InputBorder.none,
                        filled: false,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),

                // Category chips
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: _categories.length,
                    itemBuilder: (_, i) {
                      final cat = _categories[i];
                      final sel = _selectedCategory == cat['name'];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _selectCategory(cat['name']);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(cat['icon'],
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(cat['name'],
                                style: TextStyle(
                                    color: sel ? _green : Colors.white,
                                    fontSize: 11,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w400)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ])),
        ),

        // ── Results header ───────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            Text('${_filtered.length} lawyers found',
                style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            // City filter
            GestureDetector(
              onTap: () => _showCityFilter(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border, width: 0.8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_on_rounded,
                      color: _green, size: 14),
                  const SizedBox(width: 4),
                  Text(_selectedCity,
                      style: const TextStyle(
                          color: _green,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: _green, size: 16),
                ]),
              ),
            ),
          ]),
        ),

        // ── Lawyers list ─────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _green))
              : _filtered.isEmpty
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
                              child: Icon(Icons.search_off_rounded,
                                  color: _green.withValues(alpha: 0.5), size: 40)),
                          const SizedBox(height: 16),
                          const Text('No lawyers found',
                              style: TextStyle(
                                  color: _textPri,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text('Try a different search or category',
                              style:
                                  TextStyle(color: _textMuted, fontSize: 13)),
                        ]))
                  : RefreshIndicator(
                      color: _green,
                      backgroundColor: _bgCard,
                      onRefresh: _loadLawyers,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final l = _filtered[i];
                          return TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(milliseconds: 200 + (i * 50)),
                            builder: (_, v, child) => Opacity(
                                opacity: v.clamp(0.0, 1.0),
                                child: Transform.translate(
                                    offset: Offset(0, 20 * (1 - v)),
                                    child: child)),
                            child: _LawyerCard(
                              lawyer: l,
                              index: i,
                              chatUnlocked:
                                  _paidLawyerIds.contains(l['id']),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  void _showCityFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Filter by City',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        ..._cities.map((city) => ListTile(
              leading: Icon(Icons.location_on_rounded,
                  color: city == _selectedCity ? _green : _textMuted, size: 20),
              title: Text(city,
                  style: TextStyle(
                      color: city == _selectedCity ? _green : _textPri,
                      fontWeight: city == _selectedCity
                          ? FontWeight.w700
                          : FontWeight.w400)),
              trailing: city == _selectedCity
                  ? const Icon(Icons.check_rounded, color: _green, size: 18)
                  : null,
              onTap: () {
                setState(() => _selectedCity = city);
                _applyFilter();
                Navigator.pop(context);
              },
            )),
        const SizedBox(height: 20),
      ]),
    );
  }
}

class _LawyerCard extends StatelessWidget {
  final dynamic lawyer;
  final int index;
  final bool chatUnlocked;
  const _LawyerCard(
      {required this.lawyer, required this.index, required this.chatUnlocked});

  @override
  Widget build(BuildContext context) {
    final name = lawyer['name'] ?? 'Advocate';
    final designation = lawyer['designation'] ?? 'Advocate';
    final city = lawyer['city'] ?? '';
    final state = lawyer['state'] ?? '';
    final speciality = lawyer['speciality'] ?? '';
    final firmName = lawyer['firm_name'] ?? '';
    final experience = lawyer['experience_years'] ?? 0;
    final totalCases = lawyer['total_cases'] ?? 0;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'A';
    final location = [city, state].where((s) => s.isNotEmpty).join(', ');
    final avatarUrl = (lawyer['avatar_url'] ?? '') as String;

    final colors = [
      const Color(0xFF0D6E4F),
      const Color(0xFF1565C0),
      const Color(0xFF7C3AED),
      const Color(0xFF00897B),
      const Color(0xFFD4A017),
    ];
    final color = colors[index % colors.length];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push(
            '/portal/lawyer/${lawyer['id']}?name=${Uri.encodeComponent(name)}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _green.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Avatar
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10)
                ],
              ),
              child: avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.memory(
                        base64Decode(
                            avatarUrl.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '')),
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22))),
                      ),
                    )
                  : Center(
                      child: Text(initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22))),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(designation,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  if (firmName.isNotEmpty)
                    Text(firmName,
                        style:
                            const TextStyle(color: _textMuted, fontSize: 11)),
                  if (location.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: _textMuted, size: 12),
                      const SizedBox(width: 2),
                      Text(location,
                          style:
                              const TextStyle(color: _textMuted, fontSize: 11)),
                    ]),
                ])),
            // Verified badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_rounded, color: _green, size: 12),
                SizedBox(width: 3),
                Text('Verified',
                    style: TextStyle(
                        color: _green,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          if (speciality.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(color: _border, thickness: 0.6, height: 1),
            const SizedBox(height: 10),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: speciality
                    .split(',')
                    .take(3)
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border:
                                  Border.all(color: color.withValues(alpha: 0.2))),
                          child: Text(s.trim(),
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList()),
          ],
          const SizedBox(height: 12),
          Row(children: [
            _StatBadge(Icons.gavel_rounded, '$totalCases Cases', _textMuted),
            const SizedBox(width: 12),
            _StatBadge(Icons.workspace_premium_rounded, '$experience Yrs Exp',
                _textMuted),
            const Spacer(),
            // Book & Chat buttons
            GestureDetector(
              onTap: () => context.push(
                  '/portal/book-consultation/${lawyer['id']}?name=${Uri.encodeComponent(name)}'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: _green, borderRadius: BorderRadius.circular(10)),
                child: const Text('Book',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                if (!chatUnlocked) {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text(
                          'Chat unlocks once you book a paid consultation with this lawyer.'),
                      backgroundColor: const Color(0xFFD4A017),
                      action: SnackBarAction(
                          label: 'Book',
                          textColor: Colors.white,
                          onPressed: () => context.push(
                              '/portal/book-consultation/${lawyer['id']}?name=${Uri.encodeComponent(name)}'))));
                  return;
                }
                HapticFeedback.heavyImpact();
                try {
                  final res = await DioClient.instance
                      .post('/chat/rooms', data: {'lawyer_id': lawyer['id']});
                  final roomId = res.data['data']['id'];
                  if (context.mounted)
                    context.push(
                        '/chat/$roomId?name=${Uri.encodeComponent(name)}');
                } catch (e) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not start chat'),
                        backgroundColor: Color(0xFFD9534F)));
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: chatUnlocked ? _bgCard : _bgCard.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: chatUnlocked ? _green : _textMuted,
                        width: 1.2)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!chatUnlocked) ...[
                    const Icon(Icons.lock_outline_rounded,
                        size: 12, color: _textMuted),
                    const SizedBox(width: 4),
                  ],
                  Text('Chat',
                      style: TextStyle(
                          color: chatUnlocked ? _green : _textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatBadge(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ]);
}
