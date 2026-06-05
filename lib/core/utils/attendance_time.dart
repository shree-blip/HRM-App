/// Time helpers for the attendance module.
///
/// All attendance timestamps are stored in UTC. The company timezone is
/// Nepal (NPT = UTC+5:45); displays and "today" grouping use NPT so every
/// viewer sees the same day, matching the web app.
class NptTime {
  const NptTime._();

  static const Duration offset = Duration(hours: 5, minutes: 45);

  static DateTime nowNpt() => DateTime.now().toUtc().add(offset);

  static DateTime toNpt(DateTime utc) => utc.toUtc().add(offset);

  /// YYYY-MM-DD in NPT for the given UTC instant.
  static String nptDateKey(DateTime utc) {
    final d = toNpt(utc);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String todayKey() => nptDateKey(DateTime.now().toUtc());

  /// "9:05 AM" in NPT.
  static String formatTime(DateTime utc) {
    final d = toNpt(utc);
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  /// "Mon, Jun 9" in NPT.
  static String formatDateShort(DateTime utc) {
    final d = toNpt(utc);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  /// UTC instant for the start of "today" in NPT (used for day-range queries).
  static DateTime nptTodayStartUtc() {
    final n = nowNpt();
    final startNpt = DateTime.utc(n.year, n.month, n.day);
    return startNpt.subtract(offset);
  }

  static DateTime nptMonthStartUtc() {
    final n = nowNpt();
    final startNpt = DateTime.utc(n.year, n.month, 1);
    return startNpt.subtract(offset);
  }

  /// Monday 00:00 of the current NPT week, as a UTC instant.
  static DateTime nptWeekStartUtc() {
    final n = nowNpt();
    final monday = DateTime.utc(n.year, n.month, n.day)
        .subtract(Duration(days: n.weekday - 1));
    return monday.subtract(offset);
  }
}

/// "2h 30m" / "45m" / "3h" / "0m"
String formatDurationMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

/// "just now" / "5m ago" / "2h ago" / "3d ago" (web formatDistanceToNow-ish).
String relativeFromNow(DateTime utc) {
  final diff = DateTime.now().toUtc().difference(utc);
  final s = diff.inSeconds;
  if (s < 0) return 'just now';
  if (s < 45) return 'just now';
  if (s < 3600) return '${(s / 60).round()}m ago';
  if (s < 86400) return '${(s / 3600).round()}h ago';
  return '${(s / 86400).round()}d ago';
}

/// "Jun 9 • 2:30:45 PM" in NPT.
String formatDateTimeLong(DateTime utc) {
  final d = NptTime.toNpt(utc);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  var h = d.hour % 12;
  if (h == 0) h = 12;
  final m = d.minute.toString().padLeft(2, '0');
  final sec = d.second.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${months[d.month - 1]} ${d.day} • $h:$m:$sec $ap';
}

/// "01:23:45" elapsed clock.
String formatHms(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final hh = (s ~/ 3600).toString().padLeft(2, '0');
  final mm = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}
