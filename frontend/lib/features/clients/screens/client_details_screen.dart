import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _gold = Color(0xFFB8860B);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class ClientDetailsScreen extends StatefulWidget {
  final String clientId;
  const ClientDetailsScreen({super.key, required this.clientId});
  @override
  State<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends State<ClientDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _client;
  List<dynamic> _cases = [];
  List<dynamic> _documents = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadClient();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadClient() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await DioClient.instance.get('/clients/${widget.clientId}');
      if (res.data['success'] == true) {
        setState(() {
          _client = res.data['data'];
          _loading = false;
        });
      } else {
        setState(() {
          _error = res.data['message'] ?? 'Failed to load';
          _loading = false;
        });
      }
      try {
        final casesRes = await DioClient.instance.get('/cases');
        final allCases = casesRes.data['data'] as List;
        setState(() {
          _cases = allCases
              .where((c) => c['client_name'] == _client?['name'])
              .toList();
        });
      } catch (e) {
        debugPrint('Cases error: $e');
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load client details';
        _loading = false;
      });
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'C';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _brown)),
      );
    }

    if (_error != null || _client == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _brown,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title: const Text('Client Details',
              style: TextStyle(color: Colors.white)),
        ),
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFD9534F), size: 60),
          const SizedBox(height: 16),
          Text(_error ?? 'Client not found',
              style: const TextStyle(color: _textMuted, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadClient,
            style: ElevatedButton.styleFrom(backgroundColor: _brown),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ])),
      );
    }

    final isActive = _client!['is_active'] ?? true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(slivers: [
          // ── Header ──
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            backgroundColor: _brown,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Color(0xFFFFD700)),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF150E3D), Color(0xFF0B0726)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
                  child: Row(children: [
                    // Initials circle
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5), width: 2),
                      ),
                      child: Center(
                        child: Text(_getInitials(_client!['name'] ?? ''),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_client!['name'] ?? '',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        if ((_client!['email'] ?? '').isNotEmpty)
                          Text(_client!['email'],
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12)),
                        if ((_client!['phone'] ?? '').isNotEmpty)
                          Text(_client!['phone'],
                              style: const TextStyle(
                                  color: Color(0xFFFFD700), fontSize: 13)),
                      ],
                    )),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isActive
                                ? Colors.white.withValues(alpha: 0.5)
                                : Colors.red),
                      ),
                      child: Text(isActive ? 'Active' : 'Inactive',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFFD700),
              indicatorWeight: 2.5,
              labelColor: const Color(0xFFFFD700),
              unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
              tabs: const [
                Tab(text: 'Details'),
                Tab(text: 'Cases'),
                Tab(text: 'Documents'),
              ],
            ),
          ),

          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DetailsTab(client: _client!),
                _CasesTab(cases: _cases),
                _DocumentsTab(documents: _documents),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Details Tab ────────────────────────────────────
class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> client;
  const _DetailsTab({required this.client});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
              title: 'Contact Information',
              icon: Icons.contact_phone_outlined,
              items: [
                _InfoItem(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: client['email'] ?? '-'),
                _InfoItem(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: client['phone'] ?? '-'),
                _InfoItem(
                    icon: Icons.phone_outlined,
                    label: 'Alt Phone',
                    value: client['alternate_phone'] ?? '-'),
              ]),
          const SizedBox(height: 14),
          _InfoCard(title: 'Address', icon: Icons.location_on_outlined, items: [
            _InfoItem(
                icon: Icons.home_outlined,
                label: 'Address',
                value: client['address'] ?? '-'),
            _InfoItem(
                icon: Icons.location_city_outlined,
                label: 'City',
                value: client['city'] ?? '-'),
            _InfoItem(
                icon: Icons.map_outlined,
                label: 'State',
                value: client['state'] ?? '-'),
            _InfoItem(
                icon: Icons.pin_outlined,
                label: 'Pincode',
                value: client['pincode'] ?? '-'),
          ]),
          if ((client['notes'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _InfoCard(title: 'Notes', icon: Icons.note_outlined, items: [
              _InfoItem(
                  icon: Icons.note_outlined,
                  label: 'Notes',
                  value: client['notes']),
            ]),
          ],
          const SizedBox(height: 80),
        ],
      );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_InfoItem> items;
  const _InfoCard(
      {required this.title, required this.icon, required this.items});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: _brown, borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, color: Colors.white, size: 13)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: _brown, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Divider(color: _border, height: 20, thickness: 0.6),
          ...items,
        ]),
      );
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, color: _brownLight, size: 15),
          const SizedBox(width: 10),
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPri,
                      fontSize: 13,
                      fontWeight: FontWeight.w500))),
        ]),
      );
}

// ── Cases Tab ──────────────────────────────────────
class _CasesTab extends StatelessWidget {
  final List<dynamic> cases;
  const _CasesTab({required this.cases});

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.gavel_rounded,
            color: _brownLight.withValues(alpha: 0.4), size: 52),
        const SizedBox(height: 12),
        const Text('No cases yet',
            style: TextStyle(color: _textMuted, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => context.push('/cases/add'),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Add Case', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cases.length,
      itemBuilder: (_, i) {
        final c = cases[i];
        return GestureDetector(
          onTap: () => context.push('/cases/${c['id']}'),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: _brown.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child:
                      const Icon(Icons.gavel_rounded, color: _brown, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(c['case_title'] ?? '',
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text(c['court_name'] ?? '',
                        style:
                            const TextStyle(color: _textMuted, fontSize: 12)),
                  ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFF2E8B57).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(c['status'] ?? 'active',
                    style: const TextStyle(
                        color: Color(0xFF2E8B57),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ── Documents Tab ──────────────────────────────────
class _DocumentsTab extends StatelessWidget {
  final List<dynamic> documents;
  const _DocumentsTab({required this.documents});

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.folder_open_rounded,
            color: _brownLight.withValues(alpha: 0.4), size: 52),
        const SizedBox(height: 12),
        const Text('No documents yet',
            style: TextStyle(color: _textMuted, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => context.push('/documents'),
          icon: const Icon(Icons.upload_rounded, color: Colors.white),
          label: const Text('Upload Document',
              style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (_, i) {
        final d = documents[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description_rounded,
                    color: Color(0xFF4A90D9), size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(d['file_name'] ?? '',
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w600,
                        fontSize: 14))),
            IconButton(
              icon: const Icon(Icons.download_rounded, color: _gold, size: 20),
              onPressed: () => HapticFeedback.lightImpact(),
            ),
          ]),
        );
      },
    );
  }
}
