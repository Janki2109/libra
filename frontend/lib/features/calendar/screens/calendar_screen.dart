import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../hearings/providers/hearing_provider.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HearingProvider>().loadHearings();
    });
  }

  List<dynamic> _hearingsForDay(List<dynamic> hearings, DateTime day) {
    return hearings.where((h) {
      try {
        final s = (h['hearing_date'] ?? '').toString();
        if (s.length < 10) return false;
        final d = DateTime.parse(s.substring(0, 10));
        return d.year == day.year && d.month == day.month && d.day == day.day;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HearingProvider>();
    final hearings = provider.hearings;
    final selected = _selectedDay;
    final selectedHearings =
        selected != null ? _hearingsForDay(hearings, selected) : <dynamic>[];

    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDow =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Hearing Calendar',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: AppColors.gold),
                    onPressed: () => setState(() {
                      _focusedMonth = DateTime(
                          _focusedMonth.year, _focusedMonth.month - 1);
                    }),
                  ),
                  Text(
                    '${_monthName(_focusedMonth.month)} ${_focusedMonth.year}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.gold),
                    onPressed: () => setState(() {
                      _focusedMonth = DateTime(
                          _focusedMonth.year, _focusedMonth.month + 1);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: dayNames
                    .map((d) => Expanded(
                          child: Center(
                            child: Text(d,
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7, mainAxisSpacing: 4),
                itemCount: firstDow + daysInMonth,
                itemBuilder: (_, index) {
                  if (index < firstDow) return const SizedBox();
                  final day = index - firstDow + 1;
                  final date =
                      DateTime(_focusedMonth.year, _focusedMonth.month, day);
                  final hasHearing =
                      _hearingsForDay(hearings, date).isNotEmpty;
                  final isSelected = _selectedDay != null &&
                      _selectedDay!.year == date.year &&
                      _selectedDay!.month == date.month &&
                      _selectedDay!.day == date.day;
                  final now = DateTime.now();
                  final isToday = now.year == date.year &&
                      now.month == date.month &&
                      now.day == date.day;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDay = date),
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        gradient:
                            isSelected ? AppColors.goldGradient : null,
                        color: isToday && !isSelected
                            ? AppColors.info.withValues(alpha: 0.2)
                            : null,
                        shape: BoxShape.circle,
                      ),
                      child: Stack(children: [
                        Center(
                          child: Text('$day',
                              style: TextStyle(
                                  color: isSelected
                                      ? AppColors.primary
                                      : isToday
                                          ? AppColors.info
                                          : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400)),
                        ),
                        if (hasHearing)
                          Positioned(
                            bottom: 2,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.gold,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  );
                },
              ),
            ]),
          ),
          const SizedBox(height: 20),
          if (selected != null) ...[
            Row(children: [
              Text(
                '${selected.day} ${_monthName(selected.month)} ${selected.year}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${selectedHearings.length} hearing(s)',
                    style: const TextStyle(
                        color: AppColors.gold, fontSize: 11)),
              ),
            ]),
            const SizedBox(height: 12),
            if (selectedHearings.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: Text('No hearings on this day',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                ),
              )
            else
              ...selectedHearings.map((h) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            gradient: AppColors.infoGradient,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.event_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h['case_title'] ?? 'Hearing',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(h['court_name'] ?? '',
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                            (h['status'] ?? 'scheduled').toString().toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.info,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  )),
          ],
        ]),
      ),
    );
  }

  String _monthName(int m) => const [
        '',
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ][m];
}
