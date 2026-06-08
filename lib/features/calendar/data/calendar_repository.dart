import '../../../core/supabase/supabase_client.dart';
import 'calendar_models.dart';

/// Calendar data: hardcoded company entries merged with custom DB events
/// (calendar_events). Add/delete custom events. No schema changes.
class CalendarRepository {
  String get _uid => supabase.auth.currentUser!.id;

  /// Custom events from the DB (active), mapped to CalendarEntry.
  Future<List<CalendarEntry>> customEvents() async {
    final rows = await supabase
        .from('calendar_events')
        .select('id, title, description, event_date, event_type, is_active')
        .eq('is_active', true)
        .order('event_date', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map;
      final d = DateTime.tryParse(m['event_date'] as String? ?? '') ?? DateTime.now();
      return CalendarEntry(
        id: m['id'] as String,
        date: DateTime(d.year, d.month, d.day),
        name: (m['title'] ?? '') as String,
        type: (m['event_type'] ?? 'event') as String,
        description: m['description'] as String?,
        isCustom: true,
      );
    }).toList();
  }

  /// Hardcoded + custom, sorted by date.
  Future<List<CalendarEntry>> allEntries() async {
    final custom = await customEvents();
    final all = [...kCalendarEntries, ...custom]
      ..sort((a, b) => a.date.compareTo(b.date));
    return all;
  }

  Future<void> addEvent({
    required String title,
    required DateTime date,
    required String eventType,
    String? description,
  }) async {
    String? orgId;
    try {
      final p = await supabase.from('profiles').select('org_id').eq('user_id', _uid).maybeSingle();
      orgId = p?['org_id'] as String?;
    } catch (_) {}
    await supabase.from('calendar_events').insert({
      'title': title.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      'event_date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'event_type': eventType,
      'created_by': _uid,
      if (orgId != null) 'org_id': orgId,
    });
  }

  Future<void> deleteEvent(String id) async {
    await supabase.from('calendar_events').delete().eq('id', id);
  }
}
