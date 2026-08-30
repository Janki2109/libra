import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/client_provider.dart';

// ── Premium Navy/Gold Theme (matches LibraTheme) ────
const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});
  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientProvider>().loadClients();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClientProvider>();
    final filtered = provider.clients.where((c) {
      final name = (c['name'] ?? '').toLowerCase();
      final email = (c['email'] ?? '').toLowerCase();
      final phone = (c['phone'] ?? '').toLowerCase();
      return name.contains(_search) ||
          email.contains(_search) ||
          phone.contains(_search);
    }).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          Column(children: [
            // Brown header
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
                          child: Text('Clients',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                        icon: const Icon(Icons.person_add_rounded,
                            color: Color(0xFFFFD700)),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/clients/add').then((_) =>
                              context.read<ClientProvider>().loadClients());
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
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search clients...',
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
                Text('${filtered.length} clients',
                    style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ]),
            ),

            // List
            Expanded(
              child: provider.loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _brown))
                  : filtered.isEmpty
                      ? _EmptyState()
                      : RefreshIndicator(
                          color: _brown,
                          backgroundColor: _bgCard,
                          onRefresh: () =>
                              context.read<ClientProvider>().loadClients(),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) =>
                                _ClientCard(client: filtered[i]),
                          ),
                        ),
            ),
          ]),
        ]),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            context
                .push('/clients/add')
                .then((_) => context.read<ClientProvider>().loadClients());
          },
          backgroundColor: _brown,
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    );
  }
}


class _ClientCard extends StatelessWidget {
  final dynamic client;
  const _ClientCard({required this.client});

  @override
  Widget build(BuildContext context) {
    final name = client['name'] ?? '';
    final email = client['email'] ?? '';
    final phone = client['phone'] ?? '';
    final city = client['city'] ?? '';
    final isActive = client['is_active'] ?? true;
    final initials = name.isNotEmpty
        ? name
            .trim()
            .split(' ')
            .map((p) => p.isNotEmpty ? p[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : 'C';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/clients/${client['id']}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
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
        child: Row(children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_brown, _brownLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Center(
                child: Text(initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16))),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const SizedBox(height: 2),
                if (email.isNotEmpty)
                  Text(email,
                      style: const TextStyle(color: _textMuted, fontSize: 12)),
                if (phone.isNotEmpty)
                  Text(phone,
                      style: const TextStyle(
                          color: _brownLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                if (city.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        color: _textMuted, size: 11),
                    const SizedBox(width: 2),
                    Text(city,
                        style:
                            const TextStyle(color: _textMuted, fontSize: 11)),
                  ]),
              ])),

          // Status + arrow
          Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF2E8B57).withValues(alpha: 0.1)
                    : const Color(0xFFD9534F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isActive
                        ? const Color(0xFF2E8B57).withValues(alpha: 0.3)
                        : const Color(0xFFD9534F).withValues(alpha: 0.3)),
              ),
              child: Text(isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                      color: isActive
                          ? const Color(0xFF2E8B57)
                          : const Color(0xFFD9534F),
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            const Icon(Icons.chevron_right_rounded,
                color: _brownLight, size: 20),
          ]),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
            color: _brown.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: _border)),
        child: const Icon(Icons.people_outline_rounded,
            color: _brownLight, size: 38),
      ),
      const SizedBox(height: 16),
      const Text('No clients yet',
          style: TextStyle(
              color: _textPri, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Add your first client to get started',
          style: TextStyle(color: _textMuted, fontSize: 13)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => context.push('/clients/add'),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Client',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
            backgroundColor: _brown,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
      ),
    ]));
  }
}
