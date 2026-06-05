/// A row from `asset_requests`. Two-stage approval: pending_line_manager ->
/// pending_admin -> approved (or declined at any stage).
class AssetRequest {
  AssetRequest({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.requestType,
    required this.approvalStage,
    this.status,
    this.rejectionReason,
    this.lineManagerApprovedAt,
    this.adminApprovedAt,
    this.createdAt,
    this.requesterName,
  });

  final String id;
  final String userId;
  final String title;
  final String description;
  final String requestType; // asset | it_support (free text)
  final String approvalStage; // pending_line_manager | pending_admin | approved | declined
  final String? status;
  final String? rejectionReason;
  final DateTime? lineManagerApprovedAt;
  final DateTime? adminApprovedAt;
  final DateTime? createdAt;
  final String? requesterName;

  bool get isPendingLineManager => approvalStage == 'pending_line_manager';
  bool get isPendingAdmin => approvalStage == 'pending_admin';
  bool get isApproved => approvalStage == 'approved';
  bool get isDeclined => approvalStage == 'declined';

  AssetRequest withRequester(String? name) => AssetRequest(
        id: id,
        userId: userId,
        title: title,
        description: description,
        requestType: requestType,
        approvalStage: approvalStage,
        status: status,
        rejectionReason: rejectionReason,
        lineManagerApprovedAt: lineManagerApprovedAt,
        adminApprovedAt: adminApprovedAt,
        createdAt: createdAt,
        requesterName: name,
      );

  static DateTime? _dt(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toUtc() : null;

  factory AssetRequest.fromMap(Map<String, dynamic> m) => AssetRequest(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        requestType: (m['request_type'] ?? 'asset') as String,
        approvalStage: (m['approval_stage'] ?? 'pending_line_manager') as String,
        status: m['status'] as String?,
        rejectionReason: m['rejection_reason'] as String?,
        lineManagerApprovedAt: _dt(m['line_manager_approved_at']),
        adminApprovedAt: _dt(m['admin_approved_at']),
        createdAt: _dt(m['created_at']),
      );
}
