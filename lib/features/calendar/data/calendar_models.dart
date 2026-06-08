import 'package:flutter/material.dart';

/// A calendar entry — either a hardcoded holiday/deadline/optional (ported from
/// the web `calendarEntries`) or a custom DB event (calendar_events).
class CalendarEntry {
  const CalendarEntry({
    required this.date,
    required this.name,
    required this.type,
    this.id,
    this.description,
    this.isCustom = false,
  });

  final DateTime date; // local date (y, m, d)
  final String name;
  final String type; // holiday | deadline | optional | event
  final String? id; // calendar_events id (custom only)
  final String? description;
  final bool isCustom;

  String get dateKey =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Custom-event types selectable in the Add dialog (web event_type enum).
const kCalendarEventTypes = <(String, String)>[
  ('event', '📅 Event'),
  ('holiday', '⭐ Holiday'),
  ('deadline', '⏰ Deadline'),
];

String calendarTypeLabel(String type) => switch (type) {
      'holiday' => 'Day Off',
      'deadline' => 'Deadline',
      'optional' => 'Optional',
      _ => 'Event',
    };

(Color bg, Color fg) calendarTypeColors(String type) => switch (type) {
      'holiday' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'deadline' => (const Color(0xFFFFEDD5), const Color(0xFFEA580C)),
      'optional' => (const Color(0xFFEDE9FE), const Color(0xFF7C3AED)),
      _ => (const Color(0xFFDBEAFE), const Color(0xFF2563EB)), // event
    };

IconData calendarTypeIcon(String type) => switch (type) {
      'deadline' => Icons.alarm,
      'event' => Icons.event,
      _ => Icons.star, // holiday / optional
    };

/// Hardcoded company entries (ported verbatim from the web calendarEntries;
/// JS months are 0-indexed there, so +1 here).
final List<CalendarEntry> kCalendarEntries = [
  // 2025
  CalendarEntry(date: DateTime(2025, 1, 1), name: "New Year's Day", type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 1, 15), name: 'Maghe Sankranti', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 2, 14), name: "Valentine's Day", type: 'optional'),
  CalendarEntry(date: DateTime(2025, 3, 8), name: 'Maha Shivaratri', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 3, 14), name: 'Holi', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 4, 14), name: 'Nepali New Year', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 5, 1), name: 'May Day', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 5, 29), name: 'Republic Day', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 7, 4), name: 'Independence Day (US)', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 10, 23), name: 'Dashain', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 11, 1), name: 'Tihar', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 11, 27), name: 'Thanksgiving (US)', type: 'holiday'),
  CalendarEntry(date: DateTime(2025, 12, 25), name: 'Christmas Day', type: 'holiday'),
  // Jan 2026
  CalendarEntry(date: DateTime(2026, 1, 1), name: "New Year's Day", type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 1, 11), name: 'Prithvi Jayanti', type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 1, 14), name: 'Maghe Sankranti', type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 1, 30), name: "Martyrs' Day", type: 'holiday'),
  // Feb 2026
  CalendarEntry(date: DateTime(2026, 2, 2), name: 'Q4 Sales Tax Filing', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 6), name: 'Deadline: Month-end Books Closure', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 9), name: 'Check Payroll Automation', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 13), name: 'Deadline: Monthly Books Review', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 14), name: "Valentine's Day", type: 'optional'),
  CalendarEntry(date: DateTime(2026, 2, 15), name: 'Maha Shivaratri', type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 2, 20), name: 'Texas Sales Tax Filing', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 20), name: 'Deadline: Upload Monthly Financials', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 24), name: 'Q1 1st Pre-Payment (CDTFA)', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 27), name: 'Delaware Annual Report due', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 2, 28), name: 'Venture23 Pay', type: 'deadline'),
  // Mar 2026
  CalendarEntry(date: DateTime(2026, 3, 2), name: 'Holi', type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 3, 3), name: 'File Extension for 1120S & 1065', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 5), name: 'File Extension for 1120S & 1065', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 8), name: "Women's Day", type: 'optional'),
  CalendarEntry(date: DateTime(2026, 3, 9), name: 'Check Payroll Automation', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 9), name: 'Deadline: Month-end Books Closure', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 11), name: 'File Extension for 1120S & 1065', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 16), name: 'S Corp & 1065 Deadline', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 16), name: 'Deadline: Monthly Books Review', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 20), name: 'Texas Sales Tax Filing', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 24), name: 'Q1 2nd Pre-Payment (CDTFA)', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 28), name: 'Company Holiday', type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 3, 29), name: 'Deadline: Upload Monthly Financials', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 3, 30), name: 'Venture23 Payroll Day', type: 'deadline'),
  // Apr 2026
  CalendarEntry(date: DateTime(2026, 4, 3), name: 'File Extension for 1120C & 1040', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 6), name: 'File Extension for 1120C & 1040', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 7), name: 'Deadline: Month-end Books Closure', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 8), name: 'Check Payroll Automation', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 9), name: 'File Extension for 1120C & 1040', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 12), name: 'File Extension for 1120C & 1040', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 14), name: 'Nepali New Year', type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 4, 15), name: 'Tax Day', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 15), name: 'Deadline: Monthly Books Review', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 19), name: 'Texas Sales Tax Filing', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 22), name: 'Deadline: Upload Monthly Financials', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 30), name: 'Q1 Sales Tax Filing (CDTFA)', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 4, 30), name: 'Venture23 Payroll Day', type: 'deadline'),
  // May 2026
  CalendarEntry(date: DateTime(2026, 5, 1), name: 'Labor Day', type: 'holiday'),
  CalendarEntry(date: DateTime(2026, 5, 8), name: 'Check Payroll Automation', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 5, 8), name: 'Deadline: Month-end Books Closure', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 5, 15), name: 'Texas FTB PIF Filing Deadline', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 5, 15), name: 'Deadline: Monthly Books Review', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 5, 20), name: 'Texas Sales Tax Filing', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 5, 22), name: 'Deadline: Upload Monthly Financials', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 5, 25), name: 'Q2 1st Pre-Payment (CDTFA)', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 5, 30), name: 'Venture23 Payroll Day', type: 'deadline'),
  // Jun 2026
  CalendarEntry(date: DateTime(2026, 6, 5), name: 'Deadline: Month-end Books Closure', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 6, 8), name: 'Check Payroll Automation', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 6, 12), name: 'Deadline: Monthly Books Review', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 6, 19), name: 'Deadline: Upload Monthly Financials', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 6, 22), name: 'Texas Sales Tax Filing', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 6, 24), name: 'Q2 2nd Pre-Payment (CDTFA)', type: 'deadline'),
  CalendarEntry(date: DateTime(2026, 6, 30), name: 'Venture23 Payroll Day', type: 'deadline'),
];
