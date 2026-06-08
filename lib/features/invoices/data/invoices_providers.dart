import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../../support/data/comment_models.dart';
import 'invoice_models.dart';
import 'invoices_repository.dart';

final invoicesRepositoryProvider = Provider<InvoicesRepository>((_) => InvoicesRepository());

final myInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(invoicesRepositoryProvider).myInvoices();
});

final allInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(invoicesRepositoryProvider).allInvoices();
});

final invoiceCommentsProvider =
    FutureProvider.autoDispose.family<List<CommentItem>, String>(
  (ref, id) => ref.read(invoicesRepositoryProvider).comments(id),
);

/// VP/Admin (or manage_invoices) reviewers see the Submissions tab + approve.
bool canReviewInvoices(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return auth.isAdmin ||
      auth.isVp ||
      ref.read(permissionsControllerProvider).has(Permission.manageInvoices);
}
