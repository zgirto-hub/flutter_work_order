class GeneratedLetter {
  final String? id;
  final DateTime? createdAt;
  final String ishara;
  final String tarikh;
  final String alsayed;
  final String almawdoo;
  final String bodyText;
  final String alasm;
  final String? signatureBase64;
  final String? createdByEmail;
  final String? ccList;
  final List<LinkedPaymentCertificate> paymentCertificates;

  const GeneratedLetter({
    this.id,
    this.createdAt,
    required this.ishara,
    required this.tarikh,
    required this.alsayed,
    required this.almawdoo,
    required this.bodyText,
    required this.alasm,
    this.signatureBase64,
    this.createdByEmail,
    this.ccList,
    this.paymentCertificates = const [],
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null || v == '') return null;
    return DateTime.tryParse(v.toString());
  }

  factory GeneratedLetter.fromJson(Map<String, dynamic> json) {
    final rawCerts = json['payment_certificates'];
    final certs = rawCerts is List
        ? rawCerts
            .map((c) =>
                LinkedPaymentCertificate.fromJson(c as Map<String, dynamic>))
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
      alasm: json['alasm'] ?? '',
      signatureBase64: json['signature_base64'],
      createdByEmail: json['created_by_email'],
      ccList: json['cc_list'],
      paymentCertificates: certs,
    );
  }

  Map<String, dynamic> toJson() => {
        'ishara': ishara,
        'tarikh': tarikh,
        'alsayed': alsayed,
        'almawdoo': almawdoo,
        'body_text': bodyText,
        'alasm': alasm,
        'signature_base64': signatureBase64,
        'created_by_email': createdByEmail,
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
