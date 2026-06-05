/// A row from `leave_requests`.
class LeaveRequest {
  LeaveRequest({
    required this.id,
    required this.userId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.status,
    this.reason,
    this.rejectionReason,
    this.isHalfDay = false,
    this.halfDayPeriod,
    this.createdAt,
    this.employeeName,
  });

  final String id;
  final String userId;
  final String leaveType;
  final String startDate; // YYYY-MM-DD
  final String endDate;
  final num days;
  final String status; // pending | approved | rejected | cancelled
  final String? reason;
  final String? rejectionReason;
  final bool isHalfDay;
  final String? halfDayPeriod; // first_half | second_half
  final DateTime? createdAt;
  final String? employeeName; // populated for manager views

  /// Strips the "[Payroll] " / "[Paid Leave] " deduction prefix for display.
  String get cleanReason {
    final r = reason ?? '';
    final m = RegExp(r'^\[(Payroll|Paid Leave)\]\s*').firstMatch(r);
    return m == null ? r : r.substring(m.end);
  }

  String? get deductionType {
    final m = RegExp(r'^\[(Payroll|Paid Leave)\]').firstMatch(reason ?? '');
    return m?.group(1);
  }

  LeaveRequest copyWith({String? employeeName}) => LeaveRequest(
        id: id,
        userId: userId,
        leaveType: leaveType,
        startDate: startDate,
        endDate: endDate,
        days: days,
        status: status,
        reason: reason,
        rejectionReason: rejectionReason,
        isHalfDay: isHalfDay,
        halfDayPeriod: halfDayPeriod,
        createdAt: createdAt,
        employeeName: employeeName ?? this.employeeName,
      );

  factory LeaveRequest.fromMap(Map<String, dynamic> m) => LeaveRequest(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        leaveType: (m['leave_type'] ?? '') as String,
        startDate: (m['start_date'] ?? '') as String,
        endDate: (m['end_date'] ?? '') as String,
        days: (m['days'] ?? 0) as num,
        status: (m['status'] ?? 'pending') as String,
        reason: m['reason'] as String?,
        rejectionReason: m['rejection_reason'] as String?,
        isHalfDay: m['is_half_day'] == true,
        halfDayPeriod: m['half_day_period'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)
            : null,
      );
}

/// A row from `leave_balances`.
class LeaveBalance {
  const LeaveBalance({
    required this.leaveType,
    required this.totalDays,
    required this.usedDays,
  });

  final String leaveType;
  final num totalDays;
  final num usedDays;

  num get remaining => totalDays - usedDays;

  factory LeaveBalance.fromMap(Map<String, dynamic> m) => LeaveBalance(
        leaveType: (m['leave_type'] ?? '') as String,
        totalDays: (m['total_days'] ?? 0) as num,
        usedDays: (m['used_days'] ?? 0) as num,
      );
}
