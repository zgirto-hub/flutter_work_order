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
  final List<Map<String, dynamic>> paymentCertificates;

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
    this.paymentCertificates = const [],
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null || v == '') return null;
    return DateTime.tryParse(v.toString());
  }

  factory GeneratedLetter.fromJson(Map<String, dynamic> json) {
    final rawCerts = json['payment_certificates'];
    final certs = rawCerts is List
        ? rawCerts.cast<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

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
