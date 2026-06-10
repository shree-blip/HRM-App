import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// IANA timezone helpers — mirror the web `timezoneUtils` (getCurrentLocalTime /
/// getTimezoneAbbr / getUTCOffsetString) using the bundled tz database.

/// The picker list, identical to the web COMMON_TIMEZONES.
const List<String> kCommonTimezones = [
  'Asia/Kathmandu',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Anchorage',
  'Pacific/Honolulu',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Asia/Kolkata',
  'Asia/Dubai',
  'Australia/Sydney',
  'Pacific/Auckland',
];

bool _initialized = false;
void _ensureInit() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

tz.TZDateTime? _now(String timezone) {
  try {
    _ensureInit();
    return tz.TZDateTime.now(tz.getLocation(timezone));
  } catch (_) {
    return null;
  }
}

/// Current local time in [timezone] as "h:mm a" (e.g. "1:05 PM"); "—" on error.
String getCurrentLocalTime(String timezone) {
  final n = _now(timezone);
  if (n == null) return '—';
  final h12 = n.hour % 12 == 0 ? 12 : n.hour % 12;
  final ampm = n.hour < 12 ? 'AM' : 'PM';
  return '$h12:${n.minute.toString().padLeft(2, '0')} $ampm';
}

/// Timezone abbreviation (e.g. "EST", "+0545"); falls back to the IANA name.
String getTimezoneAbbr(String timezone) {
  final n = _now(timezone);
  return n?.timeZoneName ?? timezone;
}

/// UTC offset string (e.g. "UTC+5:45", "UTC-4:00"); falls back to the name.
String getUtcOffsetString(String timezone) {
  final n = _now(timezone);
  if (n == null) return timezone;
  final off = n.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final h = off.inHours.abs();
  final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return 'UTC$sign$h:$m';
}
