import 'package:flutter/material.dart';
import '../../models/payment_certificate.dart';
import '../../theme/app_theme.dart';
import '../../services/pdf/payment_certificate_pdf_service.dart';
import 'package:printing/printing.dart';

class AddPaymentCertificateScreen extends StatefulWidget {
  const AddPaymentCertificateScreen({super.key});

  @override
  State<AddPaymentCertificateScreen> createState() =>
      _AddPaymentCertificateScreenState();
}

class _AddPaymentCertificateScreenState
    extends State<AddPaymentCertificateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // Header
  final _certNumberCtrl = TextEditingController();

  // Subject & Contract
  final _subjectCtrl = TextEditingController();
  final _contractNumberCtrl = TextEditingController();

  // Invoice
  final _invoiceNumberCtrl = TextEditingController();
  final _invoiceAmountCtrl = TextEditingController();
  String _currency = 'دولار امريكي';
  DateTime? _periodFrom;
  DateTime? _periodTo;

  // Contract info
  final _executingEntityCtrl = TextEditingController();
  final _supervisingEntityCtrl = TextEditingController();
  final _originalValueUsdCtrl = TextEditingController();
  final _originalValueKwdCtrl = TextEditingController();
  final _additionalWorksCtrl = TextEditingController();
  DateTime? _contractSigningDate;
  final _contractDurationCtrl = TextEditingController();
  DateTime? _contractStartDate;
  DateTime? _contractEndDate;
  DateTime? _workCommencementDate;
  final _renewalInfoCtrl = TextEditingController();
  DateTime? _renewalExpiryDate;

  // Payment rows
  final List<_PaymentRowControllers> _paymentRows = [];

  // Attachments checklist
  late Map<String, bool> _checklist;

  // Approvers
  final _deptHeadCtrl = TextEditingController();
  final _controllerCtrl = TextEditingController();
  final _directorCtrl = TextEditingController();
  final _auditorCtrl = TextEditingController();

  bool _generating = false;

  static const _currencies = ['دولار امريكي', 'دينار كويتي'];

  @override
  void initState() {
    super.initState();
    _checklist = PaymentCertificate.defaultChecklist();
    _addPaymentRow(); // start with one row
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _certNumberCtrl.dispose();
    _subjectCtrl.dispose();
    _contractNumberCtrl.dispose();
    _invoiceNumberCtrl.dispose();
    _invoiceAmountCtrl.dispose();
    _executingEntityCtrl.dispose();
    _supervisingEntityCtrl.dispose();
    _originalValueUsdCtrl.dispose();
    _originalValueKwdCtrl.dispose();
    _additionalWorksCtrl.dispose();
    _contractDurationCtrl.dispose();
    _renewalInfoCtrl.dispose();
    _deptHeadCtrl.dispose();
    _controllerCtrl.dispose();
    _directorCtrl.dispose();
    _auditorCtrl.dispose();
    for (final r in _paymentRows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addPaymentRow() {
    setState(() {
      _paymentRows.add(_PaymentRowControllers());
    });
  }

  void _removePaymentRow(int index) {
    if (_paymentRows.length <= 1) return;
    setState(() {
      _paymentRows[index].dispose();
      _paymentRows.removeAt(index);
    });
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.accent,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) onPicked(picked);
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  PaymentCertificate _buildModel() {
    return PaymentCertificate(
      certificateNumber: _certNumberCtrl.text.trim(),
      subject: _subjectCtrl.text.trim(),
      contractNumber: _contractNumberCtrl.text.trim(),
      invoiceNumber: _invoiceNumberCtrl.text.trim(),
      invoiceAmount: double.tryParse(_invoiceAmountCtrl.text.trim()) ?? 0,
      currency: _currency,
      periodFrom: _periodFrom,
      periodTo: _periodTo,
      executingEntity: _executingEntityCtrl.text.trim(),
      supervisingEntity: _supervisingEntityCtrl.text.trim(),
      originalValueUsd: double.tryParse(_originalValueUsdCtrl.text.trim()) ?? 0,
      originalValueKwd: double.tryParse(_originalValueKwdCtrl.text.trim()) ?? 0,
      additionalWorks: _additionalWorksCtrl.text.trim(),
      contractSigningDate: _contractSigningDate,
      contractDuration: _contractDurationCtrl.text.trim(),
      contractStartDate: _contractStartDate,
      contractEndDate: _contractEndDate,
      workCommencementDate: _workCommencementDate,
      renewalInfo: _renewalInfoCtrl.text.trim(),
      renewalExpiryDate: _renewalExpiryDate,
      paymentRows: _paymentRows.map((r) => r.toModel()).toList(),
      attachmentChecklist: Map.from(_checklist),
      deptHead: _deptHeadCtrl.text.trim(),
      controller: _controllerCtrl.text.trim(),
      director: _directorCtrl.text.trim(),
      auditor: _auditorCtrl.text.trim(),
    );
  }

  Future<void> _generatePdf() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _generating = true);
    try {
      final model = _buildModel();
      final bytes = await PaymentCertificatePdfService.build(model);
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF generation failed: $e'),
          backgroundColor: AppColors.dangerText,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _generating = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Divider(height: 0, thickness: 0.5, color: AppColors.border),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionCard(
                          'شهادة الدفع',
                          Icons.receipt_long_outlined,
                          [_buildCertNumberField()],
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          'الموضوع والعقد',
                          Icons.description_outlined,
                          [
                            _field(_subjectCtrl, 'الموضوع', maxLines: 2),
                            _field(_contractNumberCtrl, 'رقم العقد'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          'بيانات الفاتورة',
                          Icons.request_quote_outlined,
                          [
                            _field(_invoiceNumberCtrl, 'رقم الفاتورة',
                                validator: _required),
                            _field(_invoiceAmountCtrl, 'مبلغ الفاتورة',
                                keyboard: TextInputType.number,
                                validator: _required),
                            _currencyDropdown(),
                            _dateRow('فترة الفاتورة - من', _periodFrom,
                                (d) => setState(() => _periodFrom = d)),
                            _dateRow('فترة الفاتورة - إلى', _periodTo,
                                (d) => setState(() => _periodTo = d)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          'بيانات العقد',
                          Icons.assignment_outlined,
                          [
                            _field(_executingEntityCtrl, 'الجهة المنفذة'),
                            _field(_supervisingEntityCtrl, 'الجهة المشرفة'),
                            _field(_originalValueUsdCtrl,
                                'قيمة العقد الأصلي (دولار)',
                                keyboard: TextInputType.number),
                            _field(_originalValueKwdCtrl,
                                'قيمة العقد الأصلي (د.ك)',
                                keyboard: TextInputType.number),
                            _field(_additionalWorksCtrl,
                                'قيمة الاعمال الإضافية'),
                            _dateRow('تاريخ توقيع العقد', _contractSigningDate,
                                (d) => setState(() => _contractSigningDate = d)),
                            _field(_contractDurationCtrl, 'مدة العقد'),
                            _dateRow('تاريخ بداية العقد', _contractStartDate,
                                (d) => setState(() => _contractStartDate = d)),
                            _dateRow('تاريخ نهاية العقد', _contractEndDate,
                                (d) => setState(() => _contractEndDate = d)),
                            _dateRow('تاريخ مباشرة الاعمال',
                                _workCommencementDate,
                                (d) => setState(() => _workCommencementDate = d)),
                            _field(_renewalInfoCtrl, 'تجديد العقد'),
                            _dateRow('تاريخ انتهاء التجديد', _renewalExpiryDate,
                                (d) => setState(() => _renewalExpiryDate = d)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildPaymentTable(),
                        const SizedBox(height: 12),
                        _buildAttachmentsChecklist(),
                        const SizedBox(height: 12),
                        _buildApprovers(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _generating ? null : _generatePdf,
          backgroundColor: AppColors.accent,
          icon: _generating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf, color: Colors.white),
          label: Text(
            _generating ? 'جاري التصدير...' : 'تصدير PDF',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.border2, width: 0.5),
              ),
              child: Icon(Icons.arrow_back_rounded,
                  size: 16, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'شهادة دفع جديدة',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card ─────────────────────────────────────────────────────

  Widget _sectionCard(String title, IconData icon, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  // ── Reusable field ───────────────────────────────────────────────────

  Widget _field(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.bgSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border2, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border2, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.accent, width: 2),
          ),
        ),
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null;

  // ── Certificate number ───────────────────────────────────────────────

  Widget _buildCertNumberField() {
    return _field(_certNumberCtrl, 'رقم شهادة الدفع', validator: _required);
  }

  // ── Currency dropdown ────────────────────────────────────────────────

  Widget _currencyDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: _currency,
        items: _currencies
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: (v) => setState(() => _currency = v!),
        decoration: InputDecoration(
          labelText: 'العملة',
          filled: true,
          fillColor: AppColors.bgSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border2, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border2, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.accent, width: 2),
          ),
        ),
      ),
    );
  }

  // ── Date row ─────────────────────────────────────────────────────────

  Widget _dateRow(String label, DateTime? value, ValueChanged<DateTime> onPicked) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _pickDate(value, onPicked),
        child: AbsorbPointer(
          child: TextFormField(
            controller: TextEditingController(text: _fmtDate(value)),
            decoration: InputDecoration(
              labelText: label,
              suffixIcon:
                  Icon(Icons.calendar_today, size: 16, color: AppColors.accent),
              filled: true,
              fillColor: AppColors.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border2, width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border2, width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Payment table ────────────────────────────────────────────────────

  Widget _buildPaymentTable() {
    return _sectionCard(
      'جدول الدفعات',
      Icons.table_chart_outlined,
      [
        for (int i = 0; i < _paymentRows.length; i++) ...[
          _buildPaymentRowCard(i),
          if (i < _paymentRows.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        _buildTotalRow(),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addPaymentRow,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('إضافة صف'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRowCard(int i) {
    final r = _paymentRows[i];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('صف ${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const Spacer(),
              if (_paymentRows.length > 1)
                GestureDetector(
                  onTap: () => _removePaymentRow(i),
                  child: Icon(Icons.close, size: 16, color: AppColors.dangerText),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _miniField(r.dollarCtrl, 'دولار')),
              const SizedBox(width: 8),
              Expanded(
                  child: _miniField(r.centCtrl, 'سنت')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _miniField(r.dinarCtrl, 'دينار (خصم)')),
              const SizedBox(width: 8),
              Expanded(
                  child: _miniField(r.filsCtrl, 'فلس (خصم)')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _miniField(r.netDinarCtrl, 'دينار (صافي)')),
              const SizedBox(width: 8),
              Expanded(
                  child: _miniField(r.netFilsCtrl, 'فلس (صافي)')),
            ],
          ),
          const SizedBox(height: 8),
          _miniField(r.reasonCtrl, 'السبب'),
        ],
      ),
    );
  }

  Widget _buildTotalRow() {
    double totalDollars = 0;
    double totalCents = 0;
    double totalDinar = 0;
    double totalFils = 0;
    double totalNetDinar = 0;
    double totalNetFils = 0;
    for (final r in _paymentRows) {
      totalDollars += double.tryParse(r.dollarCtrl.text) ?? 0;
      totalCents += double.tryParse(r.centCtrl.text) ?? 0;
      totalDinar += double.tryParse(r.dinarCtrl.text) ?? 0;
      totalFils += double.tryParse(r.filsCtrl.text) ?? 0;
      totalNetDinar += double.tryParse(r.netDinarCtrl.text) ?? 0;
      totalNetFils += double.tryParse(r.netFilsCtrl.text) ?? 0;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الاجمالي',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent)),
          const SizedBox(height: 6),
          _totalLine('الدفعة المستحقة',
              '${_fmt(totalDollars)} دولار  /  ${_fmt(totalCents)} سنت'),
          _totalLine('الخصم',
              '${_fmt(totalDinar)} دينار  /  ${_fmt(totalFils)} فلس'),
          _totalLine('الصافي',
              '${_fmt(totalNetDinar)} دينار  /  ${_fmt(totalNetFils)} فلس'),
        ],
      ),
    );
  }

  String _fmt(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2);

  Widget _totalLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _miniField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(fontSize: 12),
      keyboardType: label == 'السبب'
          ? TextInputType.text
          : TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: AppColors.bgSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border2, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border2, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      onChanged: (_) => setState(() {}), // refresh totals
    );
  }

  // ── Attachments checklist ────────────────────────────────────────────

  Widget _buildAttachmentsChecklist() {
    return _sectionCard(
      'المرفقات',
      Icons.attach_file_outlined,
      [
        for (final entry in _checklist.entries)
          CheckboxListTile(
            title: Text(entry.key,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textPrimary)),
            value: entry.value,
            onChanged: (v) =>
                setState(() => _checklist[entry.key] = v ?? false),
            activeColor: AppColors.accent,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
      ],
    );
  }

  // ── Approvers ────────────────────────────────────────────────────────

  Widget _buildApprovers() {
    return _sectionCard(
      'التوقيعات',
      Icons.people_outline,
      [
        _field(_deptHeadCtrl, 'رئيس القسم المختص'),
        _field(_controllerCtrl, 'المراقب المختص'),
        _field(_directorCtrl, 'المدير المختص'),
        _field(_auditorCtrl, 'المدقق / المحاسب'),
      ],
    );
  }
}

// ── Payment row controllers ──────────────────────────────────────────────

class _PaymentRowControllers {
  final dollarCtrl = TextEditingController();
  final centCtrl = TextEditingController();
  final dinarCtrl = TextEditingController();
  final filsCtrl = TextEditingController();
  final netDinarCtrl = TextEditingController();
  final netFilsCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();

  PaymentRow toModel() => PaymentRow(
        duePaymentDollars: double.tryParse(dollarCtrl.text) ?? 0,
        duePaymentCents: double.tryParse(centCtrl.text) ?? 0,
        deductionDinar: double.tryParse(dinarCtrl.text) ?? 0,
        deductionFils: double.tryParse(filsCtrl.text) ?? 0,
        netDinar: double.tryParse(netDinarCtrl.text) ?? 0,
        netFils: double.tryParse(netFilsCtrl.text) ?? 0,
        reason: reasonCtrl.text.trim(),
      );

  void dispose() {
    dollarCtrl.dispose();
    centCtrl.dispose();
    dinarCtrl.dispose();
    filsCtrl.dispose();
    netDinarCtrl.dispose();
    netFilsCtrl.dispose();
    reasonCtrl.dispose();
  }
}
