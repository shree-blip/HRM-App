import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/invoice_models.dart';

/// Builds an A4 PDF that reproduces the web InvoicePreview layout and hands it
/// to the platform print/share sheet (mobile-safe replacement for the web's
/// jsPDF "Download PDF"). Printing.sharePdf lets the user save or print.
Future<void> exportInvoicePdf(Invoice inv) async {
  final doc = await _buildInvoicePdf(inv);
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: '${inv.invoiceNumber?.trim().isNotEmpty == true ? inv.invoiceNumber!.trim() : 'invoice'}.pdf',
  );
}

String _money(num amount, String currency) =>
    '${NumberFormat('#,##0.00', 'en_US').format(amount)} $currency';

String _fmtDate(String? d) {
  if (d == null || d.isEmpty) return '';
  final parsed = DateTime.tryParse(d);
  if (parsed == null) return d;
  return DateFormat('MMM dd, yyyy').format(parsed);
}

const _grey = PdfColor.fromInt(0xFF6B7280);
const _greyLight = PdfColor.fromInt(0xFF9CA3AF);
const _dark = PdfColor.fromInt(0xFF111827);

Future<pw.Document> _buildInvoicePdf(Invoice inv) async {
  final doc = pw.Document();

  pw.Widget label(String t) => pw.Text(t,
      style: const pw.TextStyle(fontSize: 8, color: _greyLight, letterSpacing: 1),);

  final hasPayment = (inv.paymentAccountName?.isNotEmpty ?? false) ||
      (inv.paymentBankName?.isNotEmpty ?? false) ||
      (inv.paymentAccountNumber?.isNotEmpty ?? false) ||
      (inv.paymentSwiftCode?.isNotEmpty ?? false);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('INVOICE',
                    style: pw.TextStyle(
                        fontSize: 28, fontWeight: pw.FontWeight.bold, color: _dark,),),
                pw.SizedBox(height: 2),
                pw.Text(inv.invoiceNumber?.isNotEmpty == true ? inv.invoiceNumber! : 'INV-XXX',
                    style: const pw.TextStyle(fontSize: 10, color: _grey),),
              ],),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('Date: ${_fmtDate(inv.invoiceDate).isEmpty ? '—' : _fmtDate(inv.invoiceDate)}',
                    style: const pw.TextStyle(fontSize: 10, color: _grey),),
                if (inv.dueDate?.isNotEmpty ?? false)
                  pw.Text('Due: ${_fmtDate(inv.dueDate)}',
                      style: const pw.TextStyle(fontSize: 10, color: _grey),),
              ],),
            ],
          ),
          pw.SizedBox(height: 28),
          // From / Bill To
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  label('FROM'),
                  pw.SizedBox(height: 2),
                  pw.Text(inv.senderName?.isNotEmpty == true ? inv.senderName! : 'Your Name',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),),
                  if (inv.senderAddress?.isNotEmpty ?? false)
                    pw.Text(inv.senderAddress!, style: const pw.TextStyle(fontSize: 10, color: _grey)),
                  if (inv.senderEmail?.isNotEmpty ?? false)
                    pw.Text(inv.senderEmail!, style: const pw.TextStyle(fontSize: 10, color: _grey)),
                ],),
              ),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  label('BILL TO'),
                  pw.SizedBox(height: 2),
                  pw.Text(inv.billToName?.isNotEmpty == true ? inv.billToName! : 'Client Name',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),),
                  if (inv.billToAddress?.isNotEmpty ?? false)
                    pw.Text(inv.billToAddress!, style: const pw.TextStyle(fontSize: 10, color: _grey)),
                ],),
              ),
            ],
          ),
          pw.SizedBox(height: 28),
          // Service table
          pw.Table(
            border: const pw.TableBorder(
              bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE5E7EB)),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _dark, width: 2)),
                ),
                children: [
                  _th('DESCRIPTION', pw.TextAlign.left),
                  _th('PERIOD', pw.TextAlign.center),
                  _th('AMOUNT', pw.TextAlign.right),
                ],
              ),
              pw.TableRow(children: [
                _td(inv.serviceDescription?.isNotEmpty == true ? inv.serviceDescription! : 'Service description', pw.TextAlign.left),
                _td(inv.monthOfService?.isNotEmpty == true ? inv.monthOfService! : '—', pw.TextAlign.center),
                _td(_money(inv.amount, inv.currency), pw.TextAlign.right),
              ],),
            ],
          ),
          pw.SizedBox(height: 20),
          // Totals
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 200,
                child: pw.Column(children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 10, color: _grey)),
                      pw.Text(_money(inv.amount, inv.currency), style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 6),
                    padding: const pw.EdgeInsets.only(top: 6),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: _dark, width: 2)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Due',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),),
                        pw.Text(_money(inv.amount, inv.currency),
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),),
                      ],
                    ),
                  ),
                ],),
              ),
            ],
          ),
          if (hasPayment) ...[
            pw.SizedBox(height: 24),
            pw.Divider(color: const PdfColor.fromInt(0xFFE5E7EB)),
            pw.SizedBox(height: 8),
            label('PAYMENT INSTRUCTIONS'),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 24,
              runSpacing: 4,
              children: [
                if (inv.paymentAccountName?.isNotEmpty ?? false)
                  _pay('Account Name:', inv.paymentAccountName!),
                if (inv.paymentBankName?.isNotEmpty ?? false)
                  _pay('Bank Name:', inv.paymentBankName!),
                if (inv.paymentAccountNumber?.isNotEmpty ?? false)
                  _pay('Account / IBAN:', inv.paymentAccountNumber!),
                if (inv.paymentSwiftCode?.isNotEmpty ?? false)
                  _pay('SWIFT / BIC:', inv.paymentSwiftCode!),
              ],
            ),
          ],
          pw.Spacer(),
          pw.Center(
            child: pw.Text('Thank you for your business.',
                style: pw.TextStyle(
                    fontSize: 10, color: _greyLight, fontStyle: pw.FontStyle.italic,),),
          ),
        ],
      ),
    ),
  );
  return doc;
}

pw.Widget _th(String t, pw.TextAlign align) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(t,
          textAlign: align,
          style: const pw.TextStyle(
              fontSize: 8, color: PdfColor.fromInt(0xFF6B7280), letterSpacing: 1,),),
    );

pw.Widget _td(String t, pw.TextAlign align) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Text(t, textAlign: align, style: const pw.TextStyle(fontSize: 10)),
    );

pw.Widget _pay(String k, String v) => pw.RichText(
      text: pw.TextSpan(children: [
        pw.TextSpan(
            text: '$k ',
            style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF9CA3AF)),),
        pw.TextSpan(text: v, style: const pw.TextStyle(fontSize: 10)),
      ],),
    );
