class PaymentRow {
  final double duePaymentDollars;
  final double duePaymentCents;
  final double deductionDinar;
  final double deductionFils;
  final double netDinar;
  final double netFils;
  final String reason;

  const PaymentRow({
    this.duePaymentDollars = 0,
    this.duePaymentCents = 0,
    this.deductionDinar = 0,
    this.deductionFils = 0,
    this.netDinar = 0,
    this.netFils = 0,
    this.reason = '',
  });
}

class PaymentCertificate {
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
  final List<PaymentRow> paymentRows;
  final Map<String, bool> attachmentChecklist;
  final String deptHead;
  final String controller;
  final String director;
  final String auditor;

  const PaymentCertificate({
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
    this.paymentRows = const [],
    this.attachmentChecklist = const {},
    this.deptHead = '',
    this.controller = '',
    this.director = '',
    this.auditor = '',
  });

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
