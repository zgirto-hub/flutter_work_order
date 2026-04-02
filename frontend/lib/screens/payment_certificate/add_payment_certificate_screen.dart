import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../models/payment_certificate.dart';
import '../../theme/app_theme.dart';
import '../../services/pdf/payment_certificate_pdf_service.dart';
import '../../services/payment_certificate_service.dart';
import 'package:printing/printing.dart';

class AddPaymentCertificateScreen extends StatefulWidget {
  final PaymentCertificate? certificate;
  final bool isCopy;

  const AddPaymentCertificateScreen({super.key, this.certificate, this.isCopy = false});

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

  // Extension fields
  final _extensionValueCtrl = TextEditingController();
  final _extensionDurationCtrl = TextEditingController();
  final _extensionPeriodLabelCtrl = TextEditingController();
  DateTime? _extension1StartDate;
  DateTime? _extension1EndDate;
  DateTime? _extension2StartDate;
  DateTime? _extension2EndDate;

  // Payment rows
  final List<_PaymentRowControllers> _paymentRows = [];


  final _service = PaymentCertificateService();
  bool _generating = false;
  bool _saving = false;

  bool get _isEditing => widget.certificate != null && !widget.isCopy;

  static const _currencies = ['دولار امريكي', 'دينار كويتي'];

  static const _fixedReasons = [
    'قيمة الاعمال المستحقة عن العقد',
    'قيمة الغرامات',
    'قيمة الاعمال المستحقة (الدفعة رقم ) بناء على شروط العقد',
  ];

  static const _fixedAttachments = [
    'صورة من العقد',
    'محضر تسليم الموقع',
    'نسخة من كتاب المقاول بطلب صرف المستحقات',
    'موافقات التعاقد',
    'شهادة الخضوع الضريبي',
  ];

  
  @override
  void initState() {
    super.initState();
    _initFixedPaymentRows();
    if (widget.certificate != null) {
      _prefill(widget.certificate!);
    }
  }

  void _initFixedPaymentRows() {
    for (final reason in _fixedReasons) {
      _paymentRows.add(_PaymentRowControllers(reason: reason));
    }
  }

  void _prefill(PaymentCertificate c) {
    _certNumberCtrl.text = c.certificateNumber;
    _subjectCtrl.text = c.subject;
    _contractNumberCtrl.text = c.contractNumber;
    _invoiceNumberCtrl.text = c.invoiceNumber;
    _invoiceAmountCtrl.text = c.invoiceAmount > 0 ? c.invoiceAmount.toString() : '';
    _currency = c.currency.isNotEmpty ? c.currency : 'دولار امريكي';
    _periodFrom = c.periodFrom;
    _periodTo = c.periodTo;
    _executingEntityCtrl.text = c.executingEntity;
    _supervisingEntityCtrl.text = c.supervisingEntity;
    _originalValueUsdCtrl.text = c.originalValueUsd > 0 ? c.originalValueUsd.toString() : '';
    _originalValueKwdCtrl.text = c.originalValueKwd > 0 ? c.originalValueKwd.toString() : '';
    _additionalWorksCtrl.text = c.additionalWorks;
    _contractSigningDate = c.contractSigningDate;
    _contractDurationCtrl.text = c.contractDuration;
    _contractStartDate = c.contractStartDate;
    _contractEndDate = c.contractEndDate;
    _workCommencementDate = c.workCommencementDate;
    _renewalInfoCtrl.text = c.renewalInfo;
    _renewalExpiryDate = c.renewalExpiryDate;
    _extensionValueCtrl.text = c.extensionValue > 0 ? c.extensionValue.toString() : '';
    _extensionDurationCtrl.text = c.extensionDuration;
    _extensionPeriodLabelCtrl.text = c.extensionPeriodLabel;
    _extension1StartDate = c.extension1StartDate;
    _extension1EndDate = c.extension1EndDate;
    _extension2StartDate = c.extension2StartDate;
    _extension2EndDate = c.extension2EndDate;
    // Match saved payment rows to fixed reason rows by reason text
    for (final r in c.paymentRows) {
      final idx = _paymentRows.indexWhere((p) => p.reason == r.reason);
      if (idx == -1) continue;
      final ctrl = _paymentRows[idx];
      ctrl.duePaymentDinarCtrl.text = r.duePaymentDinar > 0 ? r.duePaymentDinar.toString() : '';
      ctrl.duePaymentFilsCtrl.text = r.duePaymentFils > 0 ? r.duePaymentFils.toString() : '';
      ctrl.dinarCtrl.text = r.deductionDinar > 0 ? r.deductionDinar.toString() : '';
      ctrl.filsCtrl.text = r.deductionFils > 0 ? r.deductionFils.toString() : '';
      ctrl.netDinarCtrl.text = r.netDinar > 0 ? r.netDinar.toString() : '';
      ctrl.netFilsCtrl.text = r.netFils > 0 ? r.netFils.toString() : '';
    }
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
    _extensionValueCtrl.dispose();
    _extensionDurationCtrl.dispose();
    _extensionPeriodLabelCtrl.dispose();
    for (final r in _paymentRows) {
      r.dispose();
    }
    super.dispose();
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
      extensionValue: double.tryParse(_extensionValueCtrl.text.trim()) ?? 0,
      extensionDuration: _extensionDurationCtrl.text.trim(),
      extension1StartDate: _extension1StartDate,
      extension1EndDate: _extension1EndDate,
      extension2StartDate: _extension2StartDate,
      extension2EndDate: _extension2EndDate,
      extensionPeriodLabel: _extensionPeriodLabelCtrl.text.trim(),
      paymentRows: _paymentRows.map((r) => r.toModel()).toList(),
      attachmentChecklist: {for (final a in _fixedAttachments) a: false},
      
    );
  }

  Future<void> _generatePdf() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _generating = true);
    try {
      final model = _buildModel();
      final bytes = await PaymentCertificatePdfService.build(model);
      if (!mounted) return;
      if (kIsWeb) {
        // On web (including iOS PWA), sharePdf triggers a file download
        // via blob URL which works reliably, unlike layoutPdf which uses
        // window.print() and is silently blocked in iOS PWA standalone mode.
        final fileName =
            'شهادة_دفع_${model.certificateNumber.replaceAll(' ', '_')}.pdf';
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await Printing.layoutPdf(onLayout: (_) => bytes);
      }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final model = _buildModel();
      if (_isEditing) {
        await _service.update(widget.certificate!.id, model);
      } else {
        await _service.create(model);
      }
      if (mounted) Navigator.pop(context, 'saved');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل الحفظ: $e'),
          backgroundColor: AppColors.dangerText,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _saving = false);
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
                            _field(_extensionValueCtrl,
                                'قيمة التمديد (د.ك)',
                                keyboard: TextInputType.number),
                            _field(_extensionDurationCtrl, 'مدة تمديد العقد'),
                            _field(_extensionPeriodLabelCtrl,
                                'وصف فترة التمديد (مثال: التمديد الثاني)'),
                            _dateRow('بداية التمديد', _extension1StartDate,
                                (d) => setState(() => _extension1StartDate = d)),
                            _dateRow('نهاية التمديد', _extension1EndDate,
                                (d) => setState(() => _extension1EndDate = d)),
                            _dateRow('بداية التمديد الثاني', _extension2StartDate,
                                (d) => setState(() => _extension2StartDate = d)),
                            _dateRow('نهاية التمديد الثاني', _extension2EndDate,
                                (d) => setState(() => _extension2EndDate = d)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildPaymentTable(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Save button
            FloatingActionButton.extended(
              heroTag: 'save',
              onPressed: _saving ? null : _save,
              backgroundColor: AppColors.accent,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: Text(
                _saving ? 'جاري الحفظ...' : 'حفظ',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            // PDF button
            FloatingActionButton(
              heroTag: 'pdf',
              onPressed: _generating ? null : _generatePdf,
              backgroundColor: AppColors.bgSurface,
              child: _generating
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent))
                  : Icon(Icons.picture_as_pdf, color: AppColors.accent),
            ),
          ],
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
              _isEditing ? 'تعديل شهادة الدفع' : widget.isCopy ? 'نسخ شهادة الدفع' : 'شهادة دفع جديدة',
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
          Text(r.reason,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _miniField(r.duePaymentDinarCtrl, 'دينار (مستحق)')),
              const SizedBox(width: 8),
              Expanded(
                  child: _miniField(r.duePaymentFilsCtrl, 'فلس (مستحق)')),
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
        ],
      ),
    );
  }

  Widget _buildTotalRow() {
    double totalDueDinar = 0;
    double totalDueFils = 0;
    double totalDinar = 0;
    double totalFils = 0;
    double totalNetDinar = 0;
    double totalNetFils = 0;
    for (final r in _paymentRows) {
      totalDueDinar += double.tryParse(r.duePaymentDinarCtrl.text) ?? 0;
      totalDueFils += double.tryParse(r.duePaymentFilsCtrl.text) ?? 0;
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
              '${_fmt(totalDueDinar)} دينار  /  ${_fmt(totalDueFils)} فلس'),
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

}

// ── Payment row controllers ──────────────────────────────────────────────

class _PaymentRowControllers {
  final String reason;
  final duePaymentDinarCtrl = TextEditingController();
  final duePaymentFilsCtrl = TextEditingController();
  final dinarCtrl = TextEditingController();
  final filsCtrl = TextEditingController();
  final netDinarCtrl = TextEditingController();
  final netFilsCtrl = TextEditingController();

  _PaymentRowControllers({required this.reason});

  PaymentRow toModel() => PaymentRow(
        duePaymentDinar: double.tryParse(duePaymentDinarCtrl.text) ?? 0,
        duePaymentFils: double.tryParse(duePaymentFilsCtrl.text) ?? 0,
        deductionDinar: double.tryParse(dinarCtrl.text) ?? 0,
        deductionFils: double.tryParse(filsCtrl.text) ?? 0,
        netDinar: double.tryParse(netDinarCtrl.text) ?? 0,
        netFils: double.tryParse(netFilsCtrl.text) ?? 0,
        reason: reason,
      );

  void dispose() {
    duePaymentDinarCtrl.dispose();
    duePaymentFilsCtrl.dispose();
    dinarCtrl.dispose();
    filsCtrl.dispose();
    netDinarCtrl.dispose();
    netFilsCtrl.dispose();
  }
}
