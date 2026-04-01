class PaymentRow {
  final double duePaymentDinar;
  final double duePaymentFils;
  final double deductionDinar;
  final double deductionFils;
  final double netDinar;
  final double netFils;
  final String reason;

  const PaymentRow({
    this.duePaymentDinar = 0,
    this.duePaymentFils = 0,
    this.deductionDinar = 0,
    this.deductionFils = 0,
    this.netDinar = 0,
    this.netFils = 0,
    this.reason = '',
  });

  factory PaymentRow.fromJson(Map<String, dynamic> json) => PaymentRow(
        duePaymentDinar: (json['duePaymentDinar'] ?? json['duePaymentDollars'] ?? 0).toDouble(),
        duePaymentFils: (json['duePaymentFils'] ?? json['duePaymentCents'] ?? 0).toDouble(),
        deductionDinar: (json['deductionDinar'] ?? 0).toDouble(),
        deductionFils: (json['deductionFils'] ?? 0).toDouble(),
        netDinar: (json['netDinar'] ?? 0).toDouble(),
        netFils: (json['netFils'] ?? 0).toDouble(),
        reason: json['reason'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'duePaymentDinar': duePaymentDinar,
        'duePaymentFils': duePaymentFils,
        'deductionDinar': deductionDinar,
        'deductionFils': deductionFils,
        'netDinar': netDinar,
        'netFils': netFils,
        'reason': reason,
      };
}

class PaymentCertificate {
  final String id;
  final String certificateNumber;
  final String subject;
  final String contractNumber;
  final String invoiceNumber;
  final double invoiceAmount;
  final String currency;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final String executingEntity;
  final String supervisingEntity;
  final double originalValueUsd;
  final double originalValueKwd;
  final String additionalWorks;
  final DateTime? contractSigningDate;
  final String contractDuration;
  final DateTime? contractStartDate;
  final DateTime? contractEndDate;
  final DateTime? workCommencementDate;
  final String renewalInfo;
  final DateTime? renewalExpiryDate;
  final double extensionValue;
  final String extensionDuration;
  final DateTime? extension1StartDate;
  final DateTime? extension1EndDate;
  final DateTime? extension2StartDate;
  final DateTime? extension2EndDate;
  final String extensionPeriodLabel;
  final List<PaymentRow> paymentRows;
  final Map<String, bool> attachmentChecklist;
  final String deptHead;
  final String controller;
  final String director;
  final String auditor;
  final String createdBy;
  final String createdByEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PaymentCertificate({
    this.id = '',
    this.certificateNumber = '',
    this.subject = '',
    this.contractNumber = '',
    this.invoiceNumber = '',
    this.invoiceAmount = 0,
    this.currency = 'USD',
    this.periodFrom,
    this.periodTo,
    this.executingEntity = '',
    this.supervisingEntity = '',
    this.originalValueUsd = 0,
    this.originalValueKwd = 0,
    this.additionalWorks = '',
    this.contractSigningDate,
    this.contractDuration = '',
    this.contractStartDate,
    this.contractEndDate,
    this.workCommencementDate,
    this.renewalInfo = '',
    this.renewalExpiryDate,
    this.extensionValue = 0,
    this.extensionDuration = '',
    this.extension1StartDate,
    this.extension1EndDate,
    this.extension2StartDate,
    this.extension2EndDate,
    this.extensionPeriodLabel = '',
    this.paymentRows = const [],
    this.attachmentChecklist = const {},
    this.deptHead = '',
    this.controller = '',
    this.director = '',
    this.auditor = '',
    this.createdBy = '',
    this.createdByEmail = '',
    this.createdAt,
    this.updatedAt,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null || v == '') return null;
    return DateTime.tryParse(v.toString());
  }

  factory PaymentCertificate.fromJson(Map<String, dynamic> j) {
    final rawRows = j['payment_rows'];
    final rows = rawRows is List
        ? rawRows.map((r) => PaymentRow.fromJson(r as Map<String, dynamic>)).toList()
        : <PaymentRow>[];

    final rawChecklist = j['attachment_checklist'];
    final checklist = rawChecklist is Map
        ? rawChecklist.map((k, v) => MapEntry(k.toString(), v == true))
        : PaymentCertificate.defaultChecklist();

    return PaymentCertificate(
      id: j['id'] ?? '',
      certificateNumber: j['certificate_number'] ?? '',
      subject: j['subject'] ?? '',
      contractNumber: j['contract_number'] ?? '',
      invoiceNumber: j['invoice_number'] ?? '',
      invoiceAmount: (j['invoice_amount'] ?? 0).toDouble(),
      currency: j['currency'] ?? 'USD',
      periodFrom: _parseDate(j['period_from']),
      periodTo: _parseDate(j['period_to']),
      executingEntity: j['executing_entity'] ?? '',
      supervisingEntity: j['supervising_entity'] ?? '',
      originalValueUsd: (j['original_value_usd'] ?? 0).toDouble(),
      originalValueKwd: (j['original_value_kwd'] ?? 0).toDouble(),
      additionalWorks: j['additional_works'] ?? '',
      contractSigningDate: _parseDate(j['contract_signing_date']),
      contractDuration: j['contract_duration'] ?? '',
      contractStartDate: _parseDate(j['contract_start_date']),
      contractEndDate: _parseDate(j['contract_end_date']),
      workCommencementDate: _parseDate(j['work_commencement_date']),
      renewalInfo: j['renewal_info'] ?? '',
      renewalExpiryDate: _parseDate(j['renewal_expiry_date']),
      extensionValue: (j['extension_value'] ?? 0).toDouble(),
      extensionDuration: j['extension_duration'] ?? '',
      extension1StartDate: _parseDate(j['extension_1_start_date']),
      extension1EndDate: _parseDate(j['extension_1_end_date']),
      extension2StartDate: _parseDate(j['extension_2_start_date']),
      extension2EndDate: _parseDate(j['extension_2_end_date']),
      extensionPeriodLabel: j['extension_period_label'] ?? '',
      paymentRows: rows,
      attachmentChecklist: checklist,
      deptHead: j['dept_head'] ?? '',
      controller: j['controller'] ?? '',
      director: j['director'] ?? '',
      auditor: j['auditor'] ?? '',
      createdBy: j['created_by'] ?? '',
      createdByEmail: j['created_by_email'] ?? '',
      createdAt: _parseDate(j['created_at']),
      updatedAt: _parseDate(j['updated_at']),
    );
  }

  static String? _fmtDate(DateTime? d) => d?.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() => {
        'certificate_number': certificateNumber,
        'subject': subject,
        'contract_number': contractNumber,
        'invoice_number': invoiceNumber,
        'invoice_amount': invoiceAmount,
        'currency': currency,
        'period_from': _fmtDate(periodFrom),
        'period_to': _fmtDate(periodTo),
        'executing_entity': executingEntity,
        'supervising_entity': supervisingEntity,
        'original_value_usd': originalValueUsd,
        'original_value_kwd': originalValueKwd,
        'additional_works': additionalWorks,
        'contract_signing_date': _fmtDate(contractSigningDate),
        'contract_duration': contractDuration,
        'contract_start_date': _fmtDate(contractStartDate),
        'contract_end_date': _fmtDate(contractEndDate),
        'work_commencement_date': _fmtDate(workCommencementDate),
        'renewal_info': renewalInfo,
        'renewal_expiry_date': _fmtDate(renewalExpiryDate),
        'extension_value': extensionValue,
        'extension_duration': extensionDuration,
        'extension_1_start_date': _fmtDate(extension1StartDate),
        'extension_1_end_date': _fmtDate(extension1EndDate),
        'extension_2_start_date': _fmtDate(extension2StartDate),
        'extension_2_end_date': _fmtDate(extension2EndDate),
        'extension_period_label': extensionPeriodLabel,
        'payment_rows': paymentRows.map((r) => r.toJson()).toList(),
        'attachment_checklist': attachmentChecklist,
        'dept_head': deptHead,
        'controller': controller,
        'director': director,
        'auditor': auditor,
        'created_by': createdBy,
        'created_by_email': createdByEmail,
      };

  static const List<String> defaultAttachments = [
    'صورة من العقد',
    'محضر تسليم الموقع',
    'نسخة من كتاب المقاول بطلب صرف المستحقات',
    'موافقات التعاقد',
    'شهادة الخضوع الضريبي',
  ];

  static Map<String, bool> defaultChecklist() =>
      {for (final a in defaultAttachments) a: false};
}
