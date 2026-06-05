/// A row from `attendance_adjustment_requests` (employee-submitted correction).
class AdjustmentRequest {
  AdjustmentRequest({
    required this.id,
    required this.attendanceLogId,
    required this.status,
    required this.reason,
    this.proposedClockIn,
    this.proposedClockOut,
    this.proposedBreakMinutes,
    this.proposedPauseMinutes,
    this.reviewerComment,
    this.overrideStatus,
    this.createdAt,
  });

  final String id;
  final String? attendanceLogId;
  final String status; // pending | approved | rejected
  final String reason;
  final DateTime? proposedClockIn;
  final DateTime? proposedClockOut;
  final int? proposedBreakMinutes;
  final int? proposedPauseMinutes;
  final String? reviewerComment;
  final String? overrideStatus;
  final DateTime? createdAt;

  /// Effective status: an override decision supersedes the manager decision.
  String get effectiveStatus => overrideStatus ?? status;

  static DateTime? _dt(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toUtc() : null;

  factory AdjustmentRequest.fromMap(Map<String, dynamic> m) => AdjustmentRequest(
        id: m['id'] as String,
        attendanceLogId: m['attendance_log_id'] as String?,
        status: (m['status'] ?? 'pending') as String,
        reason: (m['reason'] ?? '') as String,
        proposedClockIn: _dt(m['proposed_clock_in']),
        proposedClockOut: _dt(m['proposed_clock_out']),
        proposedBreakMinutes: (m['proposed_break_minutes'] as num?)?.toInt(),
        proposedPauseMinutes: (m['proposed_pause_minutes'] as num?)?.toInt(),
        reviewerComment: m['reviewer_comment'] as String?,
        overrideStatus: m['override_status'] as String?,
        createdAt: _dt(m['created_at']),
      );
}
