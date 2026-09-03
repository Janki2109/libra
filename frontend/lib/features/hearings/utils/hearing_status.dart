import 'package:flutter/material.dart';

/// Human-facing status for a hearing, derived from its stored `status`
/// (scheduled/completed/adjourned/cancelled) plus its date and whether a
/// follow-up hearing was scheduled — this is the single source of truth for
/// the label/color shown on the list, the case's Hearings tab, and the
/// details screen, so the three don't drift into different vocabularies.
class HearingStatusInfo {
  final String label;
  final Color color;
  const HearingStatusInfo(this.label, this.color);
}

const _completedColor = Color(0xFF2E8B57);
const _adjournedColor = Color(0xFFD4A017);
const _cancelledColor = Color(0xFFD9534F);
const _todayColor = Color(0xFFE0692C);
const _upcomingColor = Color(0xFF4A90D9);
const _nextScheduledColor = Color(0xFF6B4EFF);

String _todayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

String _shortDate(dynamic v) {
  final s = (v ?? '').toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// hearing is the raw map returned by the hearings API — works with every
/// endpoint's shape as long as `status`/`hearing_date` are present;
/// `next_date` is optional and only affects the "Next Hearing Scheduled"
/// label on an already-completed hearing.
HearingStatusInfo hearingStatusInfo(dynamic hearing) {
  final status = (hearing['status'] ?? 'scheduled').toString();
  final nextDate = _shortDate(hearing['next_date']);

  switch (status) {
    case 'cancelled':
      return const HearingStatusInfo('Cancelled', _cancelledColor);
    case 'adjourned':
      return const HearingStatusInfo('Adjourned', _adjournedColor);
    case 'completed':
      if (nextDate.isNotEmpty) {
        return const HearingStatusInfo(
            'Next Hearing Scheduled', _nextScheduledColor);
      }
      return const HearingStatusInfo('Completed', _completedColor);
    default:
      final hearingDate = _shortDate(hearing['hearing_date']);
      final today = _todayIso();
      if (hearingDate == today) {
        return const HearingStatusInfo('Today', _todayColor);
      }
      if (hearingDate.isNotEmpty && hearingDate.compareTo(today) > 0) {
        return const HearingStatusInfo('Upcoming', _upcomingColor);
      }
      return const HearingStatusInfo('Scheduled', _upcomingColor);
  }
}

/// True once a hearing is in a terminal, historical state — used to sort a
/// case/lawyer's hearings into a Past/History bucket vs. Today/Upcoming.
bool isPastHearing(dynamic hearing) {
  final status = (hearing['status'] ?? 'scheduled').toString();
  if (status == 'completed' || status == 'cancelled' || status == 'adjourned') {
    return true;
  }
  final hearingDate = _shortDate(hearing['hearing_date']);
  return hearingDate.isNotEmpty && hearingDate.compareTo(_todayIso()) < 0;
}
