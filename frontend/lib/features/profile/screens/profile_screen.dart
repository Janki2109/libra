import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/screens/dashboard_screen.dart' show showLawyerMoreMenu;

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _brownLight = Color(0xFF3D2C8D);
const _gold = Color(0xFFD4AF37);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(slivers: [
          // ── HEADER ──────────────────────────
          SliverToBoxAdapter(
            child: Stack(children: [
              // Background painter
              SizedBox(
                height: 380,
                width: double.infinity,
                child: CustomPaint(painter: _ProfileBgPainter()),
              ),
              SafeArea(
                child: Column(children: [
                  // Back + Edit row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      GestureDetector(
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
                          child: const Row(children: [
                            Icon(Icons.edit_rounded,
                                color: Colors.white, size: 13),
                            SizedBox(width: 5),
                            Text('Edit Profile',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),

                  // Big profile photo
                  _ProfilePhotoWidget(user: user),
                  const SizedBox(height: 14),

                  // Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(user?.name ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),

                  // LAWYER badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.gavel_rounded, color: _brown, size: 13),
                      SizedBox(width: 6),
                      Text('LAWYER',
                          style: TextStyle(
                              color: _brown,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                    ]),
                  ),
                  const SizedBox(height: 8),

                  // Email
                  Text(user?.email ?? '',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65), fontSize: 13)),
                  const SizedBox(height: 20),

                  // Stats row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        _StatTile(
                            'Active', Icons.circle, const Color(0xFF4CAF7D)),
                        _vDivider(),
                        _StatTile(
                            user?.firmId.isNotEmpty == true ? 'Firm' : 'Solo',
                            Icons.business_rounded,
                            const Color(0xFFFFD700)),
                        _vDivider(),
                        _StatTile('Verified', Icons.verified_rounded,
                            const Color(0xFF7EA8C4)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 28),
                ]),
              ),
            ]),
          ),

          // ── BODY ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(children: [
                // Personal Info
                _SectionLabel('Personal Information'),
                const SizedBox(height: 10),
                _InfoTile(Icons.email_outlined, 'Email', user?.email ?? '',
                    const Color(0xFF4A90D9)),
                const SizedBox(height: 8),
                _InfoTile(
                    Icons.phone_outlined,
                    'Phone',
                    user?.phone.isNotEmpty == true ? user!.phone : 'Not set',
                    const Color(0xFF2E8B57)),
                const SizedBox(height: 8),
                _InfoTile(
                    Icons.work_outline_rounded,
                    'Designation',
                    user?.designation.isNotEmpty == true
                        ? user!.designation
                        : 'Not set',
                    _gold),
                const SizedBox(height: 22),

                // Settings
                _SectionLabel('Settings'),
                const SizedBox(height: 10),
                _SettingTile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change Password',
                  subtitle: 'Update your password',
                  color: const Color(0xFF4A90D9),
                  onTap: () => context.push('/settings'),
                ),
                const SizedBox(height: 8),
                _SettingTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  subtitle: 'Manage alerts & reminders',
                  color: _gold,
                  // The actual toggles ("manage alerts") this promises live in
                  // SettingsScreen's App Preferences section (push
                  // notifications + haptics, both persisted and backed by a
                  // real FCM token register/unregister) — this used to open
                  // the notification feed instead, which has nothing to
                  // "manage". The feed is still reachable from the dashboard's
                  // own bell icon, so nothing is removed by pointing this at
                  // the settings screen instead.
                  onTap: () => context.push('/settings'),
                ),
                const SizedBox(height: 22),

                // More
                _SectionLabel('More'),
                const SizedBox(height: 10),
                _SettingTile(
                  icon: Icons.apps_rounded,
                  label: 'More Tools',
                  subtitle: 'Hearings, Documents, AI Research & more',
                  color: _brownLight,
                  onTap: () => showLawyerMoreMenu(context),
                ),
                const SizedBox(height: 8),
                _SettingTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Help Center',
                  subtitle: 'Get support & guidance',
                  color: const Color(0xFF2E8B57),
                  onTap: () => _showHelpCenter(context),
                ),
                const SizedBox(height: 8),
                _SettingTile(
                  icon: Icons.info_outline_rounded,
                  label: 'About Libra',
                  subtitle: 'Version 1.0.0',
                  color: _brownLight,
                  onTap: () => _showAbout(context),
                ),

                const SizedBox(height: 24),

                // Sign Out
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmLogout(context, auth),
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    label: const Text('Sign Out',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brown,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Version
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        color: _brown, borderRadius: BorderRadius.circular(6)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset('assets/logo/app logo.png',
                          width: 20, height: 20, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Libra Law Practice v1.0.0',
                      style: TextStyle(color: _textMuted, fontSize: 11)),
                ]),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.2));

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Row(children: [
                Icon(Icons.logout_rounded, color: Color(0xFFD9534F), size: 22),
                SizedBox(width: 8),
                Text('Sign Out',
                    style: TextStyle(
                        color: _textPri, fontWeight: FontWeight.w700)),
              ]),
              content: const Text('Are you sure you want to sign out?',
                  style: TextStyle(color: _textMuted)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: _textMuted))),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    HapticFeedback.heavyImpact();
                    await auth.logout();
                    if (context.mounted) context.go('/login');
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _brown,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Sign Out',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ));
  }

  /// A real, self-contained FAQ — this used to be a completely dead button
  /// (`onTap: () {}`). No support email/phone is invented here: the app has
  /// none configured anywhere, and showing a fake one would be worse than
  /// this. Every answer below describes a feature that actually exists
  /// elsewhere in this app (Add Client, Consultations, Smart Draft, etc.).
  void _showHelpCenter(BuildContext context) {
    final faqs = <(String, String)>[
      (
        'How do I add a new client?',
        'Go to Dashboard → Quick Actions → Add Client, or Clients → the + button.',
      ),
      (
        'How do I start a chat, audio or video consultation?',
        'Open My Bookings from the Dashboard, find the accepted booking, and '
            'tap Start Chat / Start Call / Start Video Call. The client is '
            'notified and can join once you start it.',
      ),
      (
        'Where can I see my past consultations and call durations?',
        'My Bookings has a History tab showing every completed, rejected and '
            'cancelled consultation with the client\'s name, date and call '
            'duration.',
      ),
      (
        'How do I change my password?',
        'Profile → Change Password.',
      ),
      (
        'How do I turn notifications on or off?',
        'Profile → Notifications, under App Preferences.',
      ),
      (
        'How do I generate a legal draft or PDF?',
        'Profile → More Tools → Smart Draft, then use the Word/PDF export '
            'buttons once your draft is ready.',
      ),
    ];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.help_outline_rounded, color: Color(0xFF2E8B57), size: 22),
          SizedBox(width: 8),
          Text('Help Center',
              style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (question, answer) in faqs) ...[
                  Text(question,
                      style: const TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text(answer,
                      style: const TextStyle(
                          color: _textMuted, fontSize: 12.5, height: 1.4)),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: _textMuted, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: _brown, borderRadius: BorderRadius.circular(18)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/logo/app logo.png',
                        width: 64, height: 64, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Libra Law Practice',
                    style: TextStyle(
                        color: _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Version 1.0.0',
                    style: TextStyle(color: _brownLight, fontSize: 13)),
                const SizedBox(height: 10),
                const Text(
                    'Smart Legal Practice Management\nfor modern law firms.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _textMuted, height: 1.5, fontSize: 13)),
              ]),
              actions: [
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _brown,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('Close',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    )),
              ],
            ));
  }
}

// ── Background Painter ─────────────────────────────
class _ProfileBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Brown gradient bg
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF150E3D), Color(0xFF0B0726)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Subtle glow
    final glowPaint = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.75, size.height * 0.25),
          radius: size.width * 0.5));
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.25),
        size.width * 0.5, glowPaint);

    // Scales watermark
    final wp = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cx = size.width * 0.8;
    final cy = size.height * 0.55;
    final s = size.width * 0.13;
    canvas.drawLine(Offset(cx, cy - s * 0.9), Offset(cx, cy + s * 0.2), wp);
    canvas.drawLine(Offset(cx - s, cy), Offset(cx + s, cy), wp);
    canvas.drawLine(Offset(cx - s, cy), Offset(cx - s * 1.3, cy + s * 0.8), wp);
    canvas.drawLine(Offset(cx - s, cy), Offset(cx - s * 0.7, cy + s * 0.8), wp);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx - s, cy + s * 0.8),
            width: s * 0.6,
            height: s * 0.2),
        math.pi,
        math.pi,
        false,
        wp);
    canvas.drawLine(Offset(cx + s, cy), Offset(cx + s * 1.3, cy + s * 0.7), wp);
    canvas.drawLine(Offset(cx + s, cy), Offset(cx + s * 0.7, cy + s * 0.7), wp);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx + s, cy + s * 0.7),
            width: s * 0.6,
            height: s * 0.2),
        math.pi,
        math.pi,
        false,
        wp);

    // Curve at bottom blending into cream
    final curvePaint = Paint()..color = const Color(0xFFF6F5FB);
    final path = Path();
    path.moveTo(0, size.height - 16);
    path.quadraticBezierTo(
        size.width / 2, size.height + 20, size.width, size.height - 16);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

// ── Profile Photo ──────────────────────────────────
class _ProfilePhotoWidget extends StatelessWidget {
  final dynamic user;
  const _ProfilePhotoWidget({required this.user});

  Future<void> _removePhoto(BuildContext context) async {
    final synced = await context.read<AuthProvider>().updateProfilePhoto('');
    if (!synced && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Photo removed on this device, but could not sync yet.'),
          backgroundColor: Color(0xFFD4A017)));
    }
  }

  Future<void> _handleTap(BuildContext context, bool hasPhoto) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(sheetContext, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(sheetContext, 'gallery'),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Remove Profile Photo',
                  style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'remove') {
      await _removePhoto(context);
      return;
    }

    final source = action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: source, imageQuality: 70, maxWidth: 600);
    if (picked == null || !context.mounted) return;
    final bytes = await picked.readAsBytes();
    final base64Photo = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    final synced =
        await context.read<AuthProvider>().updateProfilePhoto(base64Photo);
    if (!synced && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Photo updated on this device, but could not sync — clients may not see it yet.'),
          backgroundColor: Color(0xFFD4A017)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (user?.profilePhoto ?? '').isNotEmpty;
    final initials = user?.initials ?? 'U';

    return GestureDetector(
      onTap: () => _handleTap(context, hasPhoto),
      child: Stack(alignment: Alignment.center, children: [
        // Photo container — a true circle, so the photo is cropped to fit it
        // exactly rather than sitting in a rounded-rectangle badge.
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2.5),
            color: Colors.white.withValues(alpha: 0.15),
            boxShadow: [
              BoxShadow(
                  color: _brownDark.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2)
            ],
          ),
          child: ClipOval(
            child: hasPhoto
                ? Image.memory(
                    base64Decode((user!.profilePhoto as String)
                        .replaceFirst('data:image/jpeg;base64,', '')),
                    fit: BoxFit.cover,
                    width: 132,
                    height: 132,
                    errorBuilder: (_, __, ___) => _initials(initials),
                  )
                : _initials(initials),
          ),
        ),
        // Camera button
        Positioned(
            bottom: 4,
            right: 4,
            child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_rounded,
                    color: _brown, size: 16))),
        // Online dot
        Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: const Color(0xFF4CAF7D),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
            )),
      ]),
    );
  }

  Widget _initials(String i) => Center(
      child: Text(i,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 42)));
}

// ── Stat Tile ──────────────────────────────────────
class _StatTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatTile(this.label, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]));
}

// ── Section Label ──────────────────────────────────
Widget _SectionLabel(String title) => Align(
      alignment: Alignment.centerLeft,
      child: Row(children: [
        Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
                color: _brown, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3)),
      ]),
    );

// ── Info Tile ──────────────────────────────────────
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
                color: _brown.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
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
                        color: _textPri,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ])),
        ]),
      );
}

// ── Setting Tile ───────────────────────────────────
class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool showBadge;
  const _SettingTile(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.color,
      required this.onTap}) : showBadge = false;

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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
                ])),
            if (showBadge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('ADMIN',
                    style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: _textMuted, size: 14),
          ]),
        ),
      );
}
