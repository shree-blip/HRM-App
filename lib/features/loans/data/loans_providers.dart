import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'loan_models.dart';
import 'loans_repository.dart';

final loansRepositoryProvider = Provider<LoansRepository>((_) => LoansRepository());

final myLoansProvider = FutureProvider.autoDispose<List<LoanRequest>>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(loansRepositoryProvider).myLoans();
});

final managerPendingLoansProvider = FutureProvider.autoDispose<List<LoanRequest>>(
  (ref) => ref.read(loansRepositoryProvider).managerPending(),
);
final managerLoanHistoryProvider = FutureProvider.autoDispose<List<LoanRequest>>(
  (ref) => ref.read(loansRepositoryProvider).managerHistory(),
);

final vpPendingLoansProvider = FutureProvider.autoDispose<List<LoanRequest>>(
  (ref) => ref.read(loansRepositoryProvider).vpPending(),
);
final vpDisbursedLoansProvider = FutureProvider.autoDispose<List<LoanRequest>>(
  (ref) => ref.read(loansRepositoryProvider).vpDisbursed(),
);
final vpLoanHistoryProvider = FutureProvider.autoDispose<List<LoanRequest>>(
  (ref) => ref.read(loansRepositoryProvider).vpHistory(),
);

final loanRepaymentsProvider =
    FutureProvider.autoDispose.family<List<LoanRepayment>, String>(
  (ref, loanId) => ref.read(loansRepositoryProvider).repayments(loanId),
);
