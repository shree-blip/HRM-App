import 'dart:math' as math;

import 'package:flutter/material.dart';

const kLoanAnnualRate = 5.0; // fixed 5% (web FIXED_ANNUAL_RATE)
const kLoanReasonTypes = ['medical', 'education', 'emergency', 'general'];

/// EMI (reducing balance): P·r(1+r)^n / ((1+r)^n − 1), r = annual/100/12.
double loanEmi(num principal, int termMonths, {double annualRate = kLoanAnnualRate}) {
  if (termMonths <= 0 || principal <= 0) return 0;
  final r = annualRate / 100 / 12;
  if (r == 0) return principal / termMonths;
  final pow = math.pow(1 + r, termMonths);
  return principal * r * pow / (pow - 1);
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// One row of the reducing-balance amortization schedule.
class AmortizationRow {
  const AmortizationRow({
    required this.month,
    required this.openingBalance,
    required this.emi,
    required this.principal,
    required this.interest,
    required this.closingBalance,
  });
  final int month;
  final double openingBalance;
  final double emi;
  final double principal;
  final double interest;
  final double closingBalance;
}

/// Exact port of the web generateAmortizationSchedule (loanCalculations.ts):
/// per-month 2dp rounding; the final month settles the remaining balance.
List<AmortizationRow> amortizationSchedule(
  num principal,
  int termMonths, {
  double annualRate = kLoanAnnualRate,
}) {
  if (termMonths <= 0 || principal <= 0) return const [];
  final monthlyRate = annualRate / 100 / 12;
  final emi = _r2(loanEmi(principal, termMonths, annualRate: annualRate));
  final rows = <AmortizationRow>[];
  var balance = principal.toDouble();
  for (var i = 1; i <= termMonths; i++) {
    final interest = _r2(balance * monthlyRate);
    final principalPart = i == termMonths ? balance : _r2(emi - interest);
    final closing = math.max(0.0, _r2(balance - principalPart));
    rows.add(AmortizationRow(
      month: i,
      openingBalance: _r2(balance),
      emi: i == termMonths ? _r2(principalPart + interest) : emi,
      principal: principalPart,
      interest: interest,
      closingBalance: closing,
    ),);
    balance = closing;
  }
  return rows;
}

double amortizationTotalInterest(List<AmortizationRow> s) =>
    _r2(s.fold(0.0, (a, r) => a + r.interest));
double amortizationTotalPayment(List<AmortizationRow> s) =>
    _r2(s.fold(0.0, (a, r) => a + r.emi));

/// Ordered status steps for the timeline (web SIMPLIFIED_STATUSES).
const kLoanStatusSteps = [
  'draft', 'pending_manager', 'pending_vp', 'approved', 'rejected',
  'disbursed', 'closed',
];

/// Web SIMPLIFIED_STATUS_LABELS.
const Map<String, String> kLoanStepLabels = {
  'draft': 'Draft',
  'pending_manager': 'Pending Manager',
  'pending_vp': 'Pending VP',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'disbursed': 'Disbursed',
  'closed': 'Closed',
};

class LoanRequest {
  const LoanRequest({
    required this.id,
    required this.userId,
    required this.amount,
    required this.termMonths,
    this.reasonType,
    this.status = 'draft',
    this.interestRate = kLoanAnnualRate,
    this.estimatedMonthlyInstallment,
    this.remainingBalance,
    this.managerComment,
    this.createdAt,
    this.submittedAt,
    this.applicantName,
  });

  final String id;
  final String userId;
  final num amount;
  final int termMonths;
  final String? reasonType;
  final String status; // draft|pending_manager|pending_vp|approved|rejected|disbursed|closed
  final double interestRate;
  final num? estimatedMonthlyInstallment;
  final num? remainingBalance;
  final String? managerComment;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final String? applicantName;

  num get emi => estimatedMonthlyInstallment ?? loanEmi(amount, termMonths);

  LoanRequest withApplicant(String? name) => LoanRequest(
        id: id, userId: userId, amount: amount, termMonths: termMonths,
        reasonType: reasonType, status: status, interestRate: interestRate,
        estimatedMonthlyInstallment: estimatedMonthlyInstallment,
        remainingBalance: remainingBalance, managerComment: managerComment,
        createdAt: createdAt, submittedAt: submittedAt, applicantName: name,
      );

  factory LoanRequest.fromMap(Map<String, dynamic> m) {
    final emp = m['employees'] as Map?;
    return LoanRequest(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      amount: (m['amount'] ?? 0) as num,
      termMonths: ((m['term_months'] ?? 0) as num).toInt(),
      reasonType: m['reason_type'] as String?,
      status: (m['status'] ?? 'draft') as String,
      interestRate: ((m['interest_rate'] ?? kLoanAnnualRate) as num).toDouble(),
      estimatedMonthlyInstallment: m['estimated_monthly_installment'] as num?,
      remainingBalance: m['remaining_balance'] as num?,
      managerComment: m['manager_comment'] as String?,
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'] as String)?.toUtc() : null,
      submittedAt: m['submitted_at'] != null ? DateTime.tryParse(m['submitted_at'] as String)?.toUtc() : null,
      applicantName: emp != null ? '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim() : null,
    );
  }
}

class LoanRepayment {
  const LoanRepayment({
    required this.id,
    this.monthNumber,
    this.totalAmount,
    this.principalAmount,
    this.interestAmount,
    this.remainingBalance,
    this.dueDate,
    this.createdAt,
  });
  final String id;
  final int? monthNumber;
  final num? totalAmount;
  final num? principalAmount;
  final num? interestAmount;
  final num? remainingBalance;
  final String? dueDate;
  final DateTime? createdAt;

  factory LoanRepayment.fromMap(Map<String, dynamic> m) => LoanRepayment(
        id: m['id'] as String,
        monthNumber: (m['month_number'] as num?)?.toInt(),
        totalAmount: m['total_amount'] as num?,
        principalAmount: m['principal_amount'] as num?,
        interestAmount: m['interest_amount'] as num?,
        remainingBalance: m['remaining_balance'] as num?,
        dueDate: m['due_date'] as String?,
        createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'] as String)?.toUtc() : null,
      );
}

String loanStatusLabel(String s) => switch (s) {
      'pending_manager' => 'Pending Manager',
      'pending_vp' => 'Pending VP',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'disbursed' => 'Disbursed',
      'closed' => 'Closed',
      'draft' => 'Draft',
      _ => s,
    };

(Color, Color) loanStatusColors(String s) => switch (s) {
      'approved' || 'disbursed' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'closed' => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
      'rejected' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      _ => (const Color(0xFFFEF3C7), const Color(0xFFD97706)), // pending_*
    };
