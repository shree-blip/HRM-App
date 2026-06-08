import 'package:flutter/material.dart';

/// A row from `invoices` (single-line invoices; no line-item child table).
class Invoice {
  const Invoice({
    required this.id,
    required this.userId,
    this.invoiceNumber,
    this.invoiceDate,
    this.dueDate,
    this.monthOfService,
    this.senderName,
    this.senderAddress,
    this.senderEmail,
    this.billToName,
    this.billToAddress,
    this.serviceDescription,
    this.amount = 0,
    this.currency = 'NPR',
    this.paymentAccountName,
    this.paymentBankName,
    this.paymentAccountNumber,
    this.paymentSwiftCode,
    this.status = 'draft',
    this.submittedAt,
    this.reviewedAt,
    this.createdAt,
    this.submitterName,
  });

  final String id;
  final String userId;
  final String? invoiceNumber;
  final String? invoiceDate; // YYYY-MM-DD
  final String? dueDate;
  final String? monthOfService;
  final String? senderName;
  final String? senderAddress;
  final String? senderEmail;
  final String? billToName;
  final String? billToAddress;
  final String? serviceDescription;
  final num amount;
  final String currency;
  final String? paymentAccountName;
  final String? paymentBankName;
  final String? paymentAccountNumber;
  final String? paymentSwiftCode;
  final String status; // draft | submitted | approved | rejected
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final String? submitterName;

  Invoice withSubmitter(String? name) => _copy(submitterName: name);

  Invoice _copy({String? submitterName}) => Invoice(
        id: id, userId: userId, invoiceNumber: invoiceNumber, invoiceDate: invoiceDate,
        dueDate: dueDate, monthOfService: monthOfService, senderName: senderName,
        senderAddress: senderAddress, senderEmail: senderEmail, billToName: billToName,
        billToAddress: billToAddress, serviceDescription: serviceDescription, amount: amount,
        currency: currency, paymentAccountName: paymentAccountName, paymentBankName: paymentBankName,
        paymentAccountNumber: paymentAccountNumber, paymentSwiftCode: paymentSwiftCode,
        status: status, submittedAt: submittedAt, reviewedAt: reviewedAt, createdAt: createdAt,
        submitterName: submitterName ?? this.submitterName,
      );

  String get amountDisplay => '$currency ${amount.toStringAsFixed(2)}';

  factory Invoice.fromMap(Map<String, dynamic> m) {
    final emp = m['employees'] as Map?;
    return Invoice(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      invoiceNumber: m['invoice_number'] as String?,
      invoiceDate: m['invoice_date'] as String?,
      dueDate: m['due_date'] as String?,
      monthOfService: m['month_of_service'] as String?,
      senderName: m['sender_name'] as String?,
      senderAddress: m['sender_address'] as String?,
      senderEmail: m['sender_email'] as String?,
      billToName: m['bill_to_name'] as String?,
      billToAddress: m['bill_to_address'] as String?,
      serviceDescription: m['service_description'] as String?,
      amount: (m['amount'] ?? 0) as num,
      currency: (m['currency'] ?? 'NPR') as String,
      paymentAccountName: m['payment_account_name'] as String?,
      paymentBankName: m['payment_bank_name'] as String?,
      paymentAccountNumber: m['payment_account_number'] as String?,
      paymentSwiftCode: m['payment_swift_code'] as String?,
      status: (m['status'] ?? 'draft') as String,
      submittedAt: m['submitted_at'] != null ? DateTime.tryParse(m['submitted_at'] as String)?.toUtc() : null,
      reviewedAt: m['reviewed_at'] != null ? DateTime.tryParse(m['reviewed_at'] as String)?.toUtc() : null,
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'] as String)?.toUtc() : null,
      submitterName: emp != null ? '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim() : null,
    );
  }
}

const kInvoiceStatuses = ['draft', 'submitted', 'approved', 'rejected'];

(Color, Color) invoiceStatusColors(String s) => switch (s) {
      'submitted' => (const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
      'approved' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'rejected' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };

const kInvoiceCurrencies = ['NPR', 'USD'];
const kInvoiceMonths = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];
const kServiceDescription = 'IT and Software Service Contract';

/// Due-date presets (label -> days from invoice date).
const kDueDateOptions = <(String, int)>[
  ('Due on receipt', 0),
  ('Net 3', 3),
  ('Net 7', 7),
  ('Net 15', 15),
  ('Net 30', 30),
];

/// Bill-to clients (hardcoded list + addresses, mirroring the web).
const kInvoiceClients = <(String, String)>[
  ('Focus Your Finance Inc', 'Focus Your Finance Inc, USA'),
  ('Focus Data Analysis LLC', 'Focus Data Analysis LLC, USA'),
  ('Gain Consult LLC', 'Gain Consult LLC, USA'),
];
