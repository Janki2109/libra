import 'package:flutter/material.dart';

import 'admin_shell.dart';

/// A single animated shimmer bar — the base unit every skeleton loader below
/// is built from. A looping gradient sweep, not a static gray box, so a
/// loading table/card reads as "actively loading" rather than "broken/empty".
class AdminShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? radius;
  const AdminShimmerBox(
      {super.key, required this.width, required this.height, this.radius});

  @override
  State<AdminShimmerBox> createState() => _AdminShimmerBoxState();
}

class _AdminShimmerBoxState extends State<AdminShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.radius ?? BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment(-1 + _ctrl.value * 3, 0),
              end: Alignment(0 + _ctrl.value * 3, 0),
              colors: [kAdminBg, kAdminBorder.withValues(alpha: 0.7), kAdminBg],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        ),
      );
}

/// Skeleton for a data table's rows while its first load is in flight —
/// swapped in wherever a screen used to show a bare centered spinner over an
/// empty card, so the layout the table will occupy is visible immediately.
class AdminTableSkeleton extends StatelessWidget {
  final int rows;
  final int columns;
  const AdminTableSkeleton({super.key, this.rows = 6, this.columns = 5});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(
              children: List.generate(
                  columns,
                  (i) => Expanded(
                      child: Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 14),
                          child: AdminShimmerBox(
                              width: double.infinity, height: 11))))),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: List.generate(
                    columns,
                    (i) => Expanded(
                        child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: AdminShimmerBox(
                                width: double.infinity, height: 13)))),
              ),
            ),
        ]),
      );
}

/// Standard responsive column count for every admin KPI/stat grid — shared
/// so every screen's breakpoints agree with each other instead of each
/// picking its own thresholds.
int adminStatGridColumns(double maxWidth) {
  if (maxWidth > 1400) return 5;
  if (maxWidth > 1100) return 4;
  if (maxWidth > 760) return 3;
  if (maxWidth > 460) return 2;
  return 1;
}

/// The one real fix for the "BOTTOM OVERFLOWED BY N PIXELS" bug that hit
/// every stat-card grid in the admin panel: `GridView.count` with a
/// `childAspectRatio` ties each card's height to its (column-count- and
/// window-width-dependent) *width*, so the same content that fit at one
/// window size or column count overflows at another the moment a label
/// wraps to a second line. A fixed `mainAxisExtent` makes every card a
/// constant, generous height regardless of width — columns still respond to
/// window size, height never has to.
///
/// Every admin screen's stat grid should build its cards and hand them to
/// this widget rather than rolling its own `LayoutBuilder`/`GridView.count`.
class AdminStatGrid extends StatelessWidget {
  final List<Widget> cards;
  final double mainAxisExtent;
  const AdminStatGrid(
      {super.key, required this.cards, this.mainAxisExtent = 148});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: adminStatGridColumns(constraints.maxWidth),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: mainAxisExtent,
          ),
          itemCount: cards.length,
          itemBuilder: (context, i) => cards[i],
        );
      });
}

/// Skeleton for the dashboard's stat-card grid while stats are loading —
/// same `AdminStatGrid` sizing so the loading state occupies exactly the
/// space the real cards will.
class AdminStatGridSkeleton extends StatelessWidget {
  final int count;
  const AdminStatGridSkeleton({super.key, this.count = 10});

  @override
  Widget build(BuildContext context) => AdminStatGrid(
        cards: List.generate(
            count,
            (i) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: kAdminCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kAdminBorder)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdminShimmerBox(
                            width: 34,
                            height: 34,
                            radius: BorderRadius.circular(9)),
                        const SizedBox(height: 14),
                        const AdminShimmerBox(width: 60, height: 18),
                        const SizedBox(height: 8),
                        const AdminShimmerBox(width: 90, height: 10),
                      ]),
                )),
      );
}

/// A branded replacement for a bare `CircularProgressIndicator()` — same
/// role (full-section loading state), just carrying the panel's accent color
/// and a quick fade-in instead of popping in instantly.
class AdminLoader extends StatelessWidget {
  final double topPadding;
  const AdminLoader({super.key, this.topPadding = 100});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 200),
          builder: (_, v, child) => Opacity(opacity: v, child: child),
          child: const Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: kAdminAccent),
            ),
          ),
        ),
      );
}

/// A dashboard/summary stat tile — value + label + icon, optional trend sign
/// and optional tap-through to the detail screen the number represents.
///
/// A plain integer value (e.g. "128") count-up-animates from 0; a formatted
/// value (currency, or anything with non-digit characters beyond a leading
/// sign) renders as-is immediately — animating "₹1,24,500" digit-by-digit
/// would just be visual noise, not a real count.
class AdminStatCard extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;
  const AdminStatCard(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.subtitle,
      this.onTap});

  @override
  State<AdminStatCard> createState() => _AdminStatCardState();
}

class _AdminStatCardState extends State<AdminStatCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final plainInt = int.tryParse(widget.value);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kAdminCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: _hovering && widget.onTap != null
                ? widget.color.withValues(alpha: 0.4)
                : kAdminBorder),
        boxShadow: _hovering && widget.onTap != null
            ? [
                BoxShadow(
                    color: widget.color.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ]
            : const [],
      ),
      transform: _hovering && widget.onTap != null
          ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
          : Matrix4.identity(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(widget.icon, color: widget.color, size: 17)),
          if (widget.onTap != null) ...[
            const Spacer(),
            Icon(Icons.arrow_outward_rounded,
                size: 14, color: kAdminTextMuted.withValues(alpha: 0.5)),
          ],
        ]),
        const SizedBox(height: 12),
        plainInt != null
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: plainInt.toDouble()),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text('${v.round()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: kAdminTextPri,
                        fontSize: 21,
                        fontWeight: FontWeight.w800)),
              )
            : Text(widget.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: kAdminTextPri,
                    fontSize: 21,
                    fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(widget.label,
            style: const TextStyle(
                color: kAdminTextMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(widget.subtitle!,
              style: TextStyle(
                  color: widget.color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
        ],
      ]),
    );

    if (widget.onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}

/// A titled card wrapping any content — the base unit of every admin screen
/// section (a chart, a table, a filter bar).
class AdminSectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AdminSectionCard(
      {super.key,
      this.title,
      required this.child,
      this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: kAdminCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kAdminBorder),
          boxShadow: [
            BoxShadow(
                color: kAdminTextPri.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Padding(
          padding: padding,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) ...[
              Row(children: [
                Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                        color: kAdminAccent,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text(title!,
                    style: const TextStyle(
                        color: kAdminTextPri,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 14),
            ],
            child,
          ]),
        ),
      );
}

/// A pill-shaped selectable filter chip, styled for the admin palette —
/// animates smoothly between selected/unselected/hovered instead of
/// snapping, and shows a hand cursor on desktop/web.
class AdminFilterChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const AdminFilterChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  State<AdminFilterChip> createState() => _AdminFilterChipState();
}

class _AdminFilterChipState extends State<AdminFilterChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: widget.selected
                  ? kAdminAccent
                  : (_hovering
                      ? kAdminAccent.withValues(alpha: 0.06)
                      : kAdminBg),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: widget.selected
                      ? kAdminAccent
                      : (_hovering
                          ? kAdminAccent.withValues(alpha: 0.4)
                          : kAdminBorder)),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                  color: widget.selected ? Colors.white : kAdminTextPri,
                  fontSize: 12.5,
                  fontWeight:
                      widget.selected ? FontWeight.w700 : FontWeight.w500),
              child: Text(widget.label),
            ),
          ),
        ),
      );
}

/// A colored status/role badge — "PAID", "ACTIVE", "PENDING", etc. A soft
/// fill + matching border + a small solid dot reads as more "designed"
/// than a flat fill alone, and the dot gives the status a second, non-color
/// signal (useful at a glance / for anyone color-deficient).
class AdminBadge extends StatelessWidget {
  final String text;
  final Color color;
  const AdminBadge(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(text.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3)),
        ]),
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
/// The border animates to the accent color on focus instead of staying a
/// flat borderless fill, so it's obvious the field is active.
class AdminSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const AdminSearchField(
      {super.key, required this.hint, required this.onChanged});

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode
        .addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 280,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _focused ? kAdminAccent : Colors.transparent, width: 1.4),
        ),
        child: TextField(
          focusNode: _focusNode,
          onChanged: widget.onChanged,
          style: const TextStyle(fontSize: 13, color: kAdminTextPri),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(fontSize: 12, color: kAdminTextMuted),
            prefixIcon: Icon(Icons.search_rounded,
                size: 18, color: _focused ? kAdminAccent : kAdminTextMuted),
            filled: true,
            fillColor: kAdminBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
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
      {super.key,
      required this.page,
      required this.hasMore,
      required this.loading,
      required this.onPageChange});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('Page $page',
              style: const TextStyle(
                  color: kAdminTextPri,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed:
                page > 1 && !loading ? () => onPageChange(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 17),
            label: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed:
                hasMore && !loading ? () => onPageChange(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 17),
            label: const Text('Next'),
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
            Icon(Icons.inbox_rounded,
                color: kAdminTextMuted.withValues(alpha: 0.4), size: 40),
            const SizedBox(height: 10),
            Text(message,
                style: const TextStyle(color: kAdminTextMuted, fontSize: 13)),
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
