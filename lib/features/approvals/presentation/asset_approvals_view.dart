import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../support/data/asset_models.dart';
import '../../support/data/asset_providers.dart';

/// Asset request approvals — two-stage (line manager -> admin) + decline.
class AssetApprovalsView extends ConsumerStatefulWidget {
  const AssetApprovalsView({super.key});

  @override
  ConsumerState<AssetApprovalsView> createState() => _AssetApprovalsViewState();
}

class _AssetApprovalsViewState extends ConsumerState<AssetApprovalsView> {
  String _filter = 'pending'; // pending | approved | declined

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assetRequestsProvider);
    final isVp = ref.watch(authControllerProvider.select((s) => s.isVp));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(assetRequestsProvider);
        await ref.read(assetRequestsProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(children: const [
          Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Could not load.'))),
        ],),
        data: (all) {
          final pending = all.where((r) => !r.isApproved && !r.isDeclined).toList();
          final approved = all.where((r) => r.isApproved).toList();
          final declined = all.where((r) => r.isDeclined).toList();
          final list = switch (_filter) {
            'approved' => approved,
            'declined' => declined,
            _ => pending,
          };
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'pending', label: Text('Pending (${pending.length})')),
                  ButtonSegment(value: 'approved', label: Text('Approved (${approved.length})')),
                  ButtonSegment(value: 'declined', label: Text('Declined (${declined.length})')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No requests.')),
                )
              else
                for (final r in list) _AssetCard(req: r, isVp: isVp, onAction: _refresh),
            ],
          );
        },
      ),
    );
  }

  void _refresh() => ref.invalidate(assetRequestsProvider);
}

class _AssetCard extends ConsumerWidget {
  const _AssetCard({required this.req, required this.isVp, required this.onAction});
  final AssetRequest req;
  final bool isVp;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canLmApprove = req.isPendingLineManager;
    final canAdminApprove = req.isPendingAdmin && isVp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(req.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),),
                ),
                _StageChip(stage: req.approvalStage),
              ],
            ),
            Text('${req.requesterName ?? 'Employee'} · ${req.requestType}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            if (req.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(req.description, style: theme.textTheme.bodySmall),
              ),
            // Approval trail (existing reviewer/admin actions).
            if (req.lineManagerApprovedAt != null)
              _trail(theme, 'Manager approved', req.lineManagerApprovedAt!),
            if (req.adminApprovedAt != null)
              _trail(theme, 'Admin approved', req.adminApprovedAt!),
            if (req.isDeclined && req.rejectionReason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Declined: ${req.rejectionReason}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),),
              ),
            if (canLmApprove || canAdminApprove)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Decline'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),),
                      onPressed: () => _decline(context, ref),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(canAdminApprove ? 'Admin Approve' : 'Approve'),
                      onPressed: () => _approve(context, ref, canAdminApprove),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trail(ThemeData theme, String label, DateTime d) {
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 14, color: Color(0xFF16A34A)),
          const SizedBox(width: 6),
          Text('$label · $date',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref, bool admin) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(assetRepositoryProvider);
    try {
      if (admin) {
        await repo.adminApprove(req);
      } else {
        await repo.lineManagerApprove(req);
      }
      onAction();
      _toast(messenger, admin ? 'Approved.' : 'Forwarded to admin.');
    } catch (e) {
      _toast(messenger, 'Failed: $e');
    }
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline request'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await ref.read(assetRepositoryProvider).decline(req, reason.isEmpty ? null : reason);
      onAction();
      _toast(messenger, 'Declined.');
    } catch (e) {
      _toast(messenger, 'Failed: $e');
    }
  }

  void _toast(ScaffoldMessengerState messenger, String m) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.stage});
  final String stage;
  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (stage) {
      'approved' => ('approved', const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'declined' => ('declined', const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      'pending_admin' => ('pending admin', const Color(0xFFE0E7FF), const Color(0xFF4F46E5)),
      _ => ('pending manager', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),),
    );
  }
}
