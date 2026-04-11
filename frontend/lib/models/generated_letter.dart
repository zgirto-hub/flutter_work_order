class GeneratedLetter {
  final String? id;
  final DateTime? createdAt;
  final String ishara;
  final String tarikh;
  final String alsayed;
  final String almawdoo;
  final String bodyText;
  final String bodyPreview;
  final String signerTitle;
  final String alasm;
  final String? signatureBase64;
  final String? createdByEmail;
  final String? ccList;
  final List<LinkedPaymentCertificate> paymentCertificates;
  final double refFontSize;
  final bool refBold;
  final bool refUnderline;
  final double tarikhFontSize;
  final bool tarikhBold;
  final bool tarikhUnderline;
  final double recipientFontSize;
  final bool recipientBold;
  final bool recipientUnderline;
  final double subjectFontSize;
  final bool subjectBold;
  final bool subjectUnderline;

  const GeneratedLetter({
    this.id,
    this.createdAt,
    required this.ishara,
    required this.tarikh,
    required this.alsayed,
    required this.almawdoo,
    required this.bodyText,
    this.bodyPreview = '',
    this.signerTitle = '',
    required this.alasm,
    this.signatureBase64,
    this.createdByEmail,
    this.ccList,
    this.paymentCertificates = const [],
    this.refFontSize = 11,
    this.refBold = false,
    this.refUnderline = false,
    this.tarikhFontSize = 11,
    this.tarikhBold = false,
    this.tarikhUnderline = false,
    this.recipientFontSize = 12,
    this.recipientBold = false,
    this.recipientUnderline = false,
    this.subjectFontSize = 13,
    this.subjectBold = true,
    this.subjectUnderline = true,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null || v == '') return null;
    return DateTime.tryParse(v.toString());
  }

  factory GeneratedLetter.fromJson(Map<String, dynamic> json) {
    final rawCerts = json['payment_certificates'];
    final certs = rawCerts is List
        ? rawCerts
              .map(
                (c) => LinkedPaymentCertificate.fromJson(
                  c as Map<String, dynamic>,
                ),
              )
              .toList()
        : <LinkedPaymentCertificate>[];

    return GeneratedLetter(
      id: json['id'],
      createdAt: _parseDate(json['created_at']),
      ishara: json['ishara'] ?? '',
      tarikh: json['tarikh'] ?? '',
      alsayed: json['alsayed'] ?? '',
      almawdoo: json['almawdoo'] ?? '',
      bodyText: json['body_text'] ?? '',
      bodyPreview: json['body_preview'] ?? '',
      signerTitle: json['signer_title'] ?? '',
      alasm: json['alasm'] ?? '',
      signatureBase64: json['signature_base64'],
      createdByEmail: json['created_by_email'],
      ccList: json['cc_list'],
      paymentCertificates: certs,
      refFontSize: (json['ref_font_size'] as num?)?.toDouble() ?? 11,
      refBold: json['ref_bold'] as bool? ?? false,
      refUnderline: json['ref_underline'] as bool? ?? false,
      tarikhFontSize: (json['tarikh_font_size'] as num?)?.toDouble() ?? 11,
      tarikhBold: json['tarikh_bold'] as bool? ?? false,
      tarikhUnderline: json['tarikh_underline'] as bool? ?? false,
      recipientFontSize:
          (json['recipient_font_size'] as num?)?.toDouble() ?? 12,
      recipientBold: json['recipient_bold'] as bool? ?? false,
      recipientUnderline: json['recipient_underline'] as bool? ?? false,
      subjectFontSize: (json['subject_font_size'] as num?)?.toDouble() ?? 13,
      subjectBold: json['subject_bold'] as bool? ?? true,
      subjectUnderline: json['subject_underline'] as bool? ?? true,
    );
  }

  /// Return a copy suitable for creating a new letter (no id, no timestamps,
  /// no linked payment certificates).
  GeneratedLetter asCopy() => GeneratedLetter(
        ishara: ishara,
        tarikh: tarikh,
        alsayed: alsayed,
        almawdoo: almawdoo,
        bodyText: bodyText,
        signerTitle: signerTitle,
        alasm: alasm,
        signatureBase64: signatureBase64,
        ccList: ccList,
        refFontSize: refFontSize,
        refBold: refBold,
        refUnderline: refUnderline,
        tarikhFontSize: tarikhFontSize,
        tarikhBold: tarikhBold,
        tarikhUnderline: tarikhUnderline,
        recipientFontSize: recipientFontSize,
        recipientBold: recipientBold,
        recipientUnderline: recipientUnderline,
        subjectFontSize: subjectFontSize,
        subjectBold: subjectBold,
        subjectUnderline: subjectUnderline,
      );

  Map<String, dynamic> toJson() => {
    'ishara': ishara,
    'tarikh': tarikh,
    'alsayed': alsayed,
    'almawdoo': almawdoo,
    'body_text': bodyText,
    'signer_title': signerTitle,
    'alasm': alasm,
    'signature_base64': signatureBase64,
    'created_by_email': createdByEmail,
    'cc_list': ccList,
    'ref_font_size': refFontSize,
    'ref_bold': refBold,
    'ref_underline': refUnderline,
    'tarikh_font_size': tarikhFontSize,
    'tarikh_bold': tarikhBold,
    'tarikh_underline': tarikhUnderline,
    'recipient_font_size': recipientFontSize,
    'recipient_bold': recipientBold,
    'recipient_underline': recipientUnderline,
    'subject_font_size': subjectFontSize,
    'subject_bold': subjectBold,
    'subject_underline': subjectUnderline,
  };
}

class LinkedPaymentCertificate {
  final String id;
  final String certificateNumber;
  final String subject;
  final int letterLinkOrder;

  const LinkedPaymentCertificate({
    required this.id,
    required this.certificateNumber,
    required this.subject,
    required this.letterLinkOrder,
  });

  factory LinkedPaymentCertificate.fromJson(Map<String, dynamic> json) {
    return LinkedPaymentCertificate(
      id: json['id'] ?? '',
      certificateNumber: json['certificate_number'] ?? '',
      subject: json['subject'] ?? '',
      letterLinkOrder: json['letter_link_order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'certificate_number': certificateNumber,
    'subject': subject,
    'letter_link_order': letterLinkOrder,
  };
}
