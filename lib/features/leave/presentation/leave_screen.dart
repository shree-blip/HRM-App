import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../data/leave_csv.dart';
import '../data/leave_providers.dart';
import 'apply_leave_screen.dart';
import 'widgets/leave_balance_cards.dart';
import 'widgets/leave_request_tile.dart';

/// Leave Management: personal leave only (balances + history + apply) — the
/// web Leave page has no approvals tab; approvals live on the Approvals page.
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave'),
        actions: [
          IconButton(
            tooltip: 'Export my leave history (CSV)',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final list = await ref.read(myLeaveRequestsProvider.future);
              if (list.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('No leave history to export.')),
                );
                return;
              }
              await shareCsv('leave-history', leaveHistoryCsv(list));
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/leave'),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Request Leave'),
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const ApplyLeaveScreen()),
          );
          if (ok == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Leave request submitted.')),
            );
          }
        },
      ),
      body: const _MyLeaveTab(),
    );
  }
}

class _MyLeaveTab extends ConsumerWidget {
  const _MyLeaveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final requestsAsync = ref.watch(myLeaveRequestsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myLeaveRequestsProvider);
        ref.invalidate(leaveBalancesProvider);
        await ref.read(myLeaveRequestsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const LeaveBalanceCards(),
          const SizedBox(height: 20),
          Text('My Leave History',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),),
          const SizedBox(height: 8),
          requestsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Could not load leave history.'),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No leave requests yet.')),
                );
              }
              return Column(
                children: [for (final r in list) LeaveRequestTile(req: r)],
              );
            },
          ),
        ],
      ),
    );
  }
}
