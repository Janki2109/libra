import 'package:flutter/material.dart';

import 'admin_shell.dart';

/// A dashboard/summary stat tile — value + label + icon, optional trend sign.
class AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  const AdminStatCard(
      {super.key, required this.label, required this.value, required this.icon, required this.color, this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kAdminCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kAdminBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: color, size: 17)),
          ]),
          const SizedBox(height: 12),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kAdminTextPri, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: kAdminTextMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ]),
      );
}

/// A titled card wrapping any content — the base unit of every admin screen
/// section (a chart, a table, a filter bar).
class AdminSectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AdminSectionCard({super.key, this.title, required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
            color: kAdminCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kAdminBorder)),
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(color: kAdminTextPri, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
            ],
            child,
          ]),
        ),
      );
}

/// A pill-shaped selectable filter chip, styled for the admin palette.
class AdminFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const AdminFilterChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? kAdminAccent : kAdminBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? kAdminAccent : kAdminBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : kAdminTextMuted,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
}

/// A colored status/role badge — "PAID", "ACTIVE", "PENDING", etc.
class AdminBadge extends StatelessWidget {
  final String text;
  final Color color;
  const AdminBadge(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      );

  /// Maps common status strings used across consultations/payments/users to
  /// a consistent color, so every screen's badges agree with each other.
  static Color colorFor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'active':
      case 'confirmed':
      case 'completed':
      case 'verified':
      case 'success':
        return kAdminGreen;
      case 'pending':
      case 'created':
      case 'processing':
        return kAdminAmber;
      case 'failed':
      case 'rejected':
      case 'cancelled':
      case 'suspended':
        return kAdminRed;
      case 'refunded':
      case 'partially_refunded':
        return kAdminAccent;
      default:
        return kAdminTextMuted;
    }
  }
}

/// A search box styled for the admin content area (distinct from the top
/// bar's global search — this filters within the current screen/table).
class AdminSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const AdminSearchField({super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        height: 38,
        child: TextField(
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: kAdminTextMuted),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: kAdminTextMuted),
            filled: true,
            fillColor: kAdminBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );
}

/// Prev/Next pagination footer shared by every paginated admin list.
class AdminPager extends StatelessWidget {
  final int page;
  final bool hasMore;
  final bool loading;
  final ValueChanged<int> onPageChange;
  const AdminPager(
      {super.key, required this.page, required this.hasMore, required this.loading, required this.onPageChange});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('Page $page', style: const TextStyle(color: kAdminTextMuted, fontSize: 12)),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: page > 1 && !loading ? () => onPageChange(page - 1) : null,
            child: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: hasMore && !loading ? () => onPageChange(page + 1) : null,
            child: const Text('Next'),
          ),
        ]),
      );
}

/// Empty-state placeholder — every list screen shows this instead of an
/// empty table when there is genuinely no data, per the "no dummy data"
/// requirement: nothing is ever synthesized to fill the gap.
class AdminEmptyState extends StatelessWidget {
  final String message;
  const AdminEmptyState({super.key, this.message = 'No records found'});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(children: [
            Icon(Icons.inbox_rounded, color: kAdminTextMuted.withValues(alpha: 0.4), size: 40),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: kAdminTextMuted, fontSize: 13)),
          ]),
        ),
      );
}

String fmtDate(String? raw) {
  if (raw == null || raw.length < 10) return '—';
  return raw.substring(0, 10);
}

String fmtRupees(num? v) {
  final n = (v ?? 0).toDouble();
  return '₹${n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2)}';
}
