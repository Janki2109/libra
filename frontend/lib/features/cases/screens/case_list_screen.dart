import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

// ── Premium Navy/Gold Theme (matches LibraTheme) ────
const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _gold = Color(0xFFD4AF37);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);

class CaseListScreen extends StatefulWidget {
  const CaseListScreen({super.key});
  @override
  State<CaseListScreen> createState() => _CaseListScreenState();
}

class _CaseListScreenState extends State<CaseListScreen> {
  final _searchCtrl = TextEditingController();
  List<dynamic> _cases = [];
  List<dynamic> _filtered = [];
  bool _loading = true;
  String _selectedFilter = 'All';

  final List<String> _filters = [
    'All',
    'Active',
    'Pending',
    'Closed',
    'Won',
    'Lost'
  ];

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/cases');
      final data = res.data['data'] ?? [];
      setState(() {
        _cases = data;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _cases.where((c) {
        final title = (c['case_title'] ?? '').toLowerCase();
        final number = (c['case_number'] ?? '').toLowerCase();
        final client = (c['client_name'] ?? '').toLowerCase();
        final status = (c['status'] ?? '').toLowerCase();
        final matchSearch = title.contains(query) ||
            number.contains(query) ||
            client.contains(query);
        final matchFilter =
            _selectedFilter == 'All' || status == _selectedFilter.toLowerCase();
        return matchSearch && matchFilter;
      }).toList();
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'won':
        return const Color(0xFF2E8B57);
      case 'lost':
        return const Color(0xFFD9534F);
      case 'pending':
        return _gold;
      case 'closed':
        return _brownLight;
      default:
        return _brown;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return const Color(0xFFD9534F);
      case 'high':
        return _gold;
      case 'low':
        return _brownLight;
      default:
        return _brown;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          Column(children: [
            // Navy/purple header
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0B0726), Color(0xFF150E3D), Color(0xFF3D2C8D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
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
                        onPressed: () => context.pop(),
                      ),
                      const Expanded(
                          child: Text('Cases',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                        icon: const Icon(Icons.add_rounded,
                            color: Color(0xFFFFD700), size: 26),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/cases/add').then((_) => _loadCases());
                        },
                      ),
                    ]),
                  )),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: _textPri, fontSize: 14),
                onChanged: (_) => _applyFilter(),
                decoration: InputDecoration(
                  hintText: 'Search cases...',
                  hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: _brownLight, size: 20),
                  filled: true,
                  fillColor: _bgCard,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _border, width: 0.8)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _brown, width: 1.5)),
                ),
              ),
            ),

            // Filter chips
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = _filters[i];
                  final selected = _selectedFilter == f;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedFilter = f);
                      _applyFilter();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? _brown : _bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected ? _brown : _border,
                            width: selected ? 0 : 0.8),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                    color: _brown.withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ]
                            : [],
                      ),
                      child: Text(f,
                          style: TextStyle(
                              color: selected ? Colors.white : _textMuted,
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // Count
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Row(children: [
                Container(
                    width: 3,
                    height: 12,
                    decoration: BoxDecoration(
                        color: _brown, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text('${_filtered.length} cases found',
                    style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ]),
            ),

            // List
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _brown))
                  : _filtered.isEmpty
                      ? _EmptyState(onAdded: _loadCases)
                      : RefreshIndicator(
                          color: _brown,
                          backgroundColor: _bgCard,
                          onRefresh: _loadCases,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _CaseCard(
                              caseData: _filtered[i],
                              statusColor:
                                  _statusColor(_filtered[i]['status'] ?? ''),
                              priorityColor: _priorityColor(
                                  _filtered[i]['priority'] ?? ''),
                              onReturn: _loadCases,
                            ),
                          ),
                        ),
            ),
          ]),
        ]),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            context.push('/cases/add').then((_) => _loadCases());
          },
          backgroundColor: _brown,
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

// ── Case Card ──────────────────────────────────────
class _CaseCard extends StatelessWidget {
  final dynamic caseData;
  final Color statusColor;
  final Color priorityColor;
  final VoidCallback onReturn;
  const _CaseCard(
      {required this.caseData,
      required this.statusColor,
      required this.priorityColor,
      required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final title = caseData['case_title'] ?? 'Untitled';
    final caseNumber = caseData['case_number'] ?? '';
    final clientName = caseData['client_name'] ?? '';
    final courtName = caseData['court_name'] ?? '';
    final status = caseData['status'] ?? 'active';
    final priority = caseData['priority'] ?? 'normal';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        // Status/priority changes made on the details screen never
        // reflected back on this list's chips without this reload — the
        // card kept showing whatever status it had when the list first
        // loaded until the user left and reopened the whole screen.
        context.push('/cases/${caseData['id']}').then((_) => onReturn());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.07),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(children: [
          // Top row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.gavel_rounded, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              // Title & number
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (caseNumber.isNotEmpty)
                      Text('Case No: $caseNumber',
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                  ])),
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
            ]),
          ),

          // Divider
          Divider(color: _border, height: 1, thickness: 0.6),

          // Bottom info row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(children: [
              // Client
              if (clientName.isNotEmpty) ...[
                Icon(Icons.person_outline_rounded, color: _textMuted, size: 14),
                const SizedBox(width: 4),
                Text(clientName,
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
                const SizedBox(width: 12),
              ],
              // Court
              if (courtName.isNotEmpty) ...[
                Icon(Icons.account_balance_outlined,
                    color: _textMuted, size: 14),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(courtName,
                        style: const TextStyle(color: _textMuted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ] else
                const Spacer(),
              // Priority badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(priority,
                    style: TextStyle(
                        color: priorityColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Empty State ────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdded;
  const _EmptyState({required this.onAdded});

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
          child: const Icon(Icons.gavel_rounded, color: _brownLight, size: 38),
        ),
        const SizedBox(height: 16),
        const Text('No cases found',
            style: TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('Add your first case to get started',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => context.push('/cases/add').then((_) => onAdded()),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Add Case',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
}
