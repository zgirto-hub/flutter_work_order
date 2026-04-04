class WorkOrderSignature {
  final String id;
  final String workOrderId;
  final String signerEmail;
  final String signerName;
  final String signerRole;
  final String? signaturePath;
  final DateTime signedAt;
  final String status;
  final String? rejectionReason;

  WorkOrderSignature({
    required this.id,
    required this.workOrderId,
    required this.signerEmail,
    this.signerName = '',
    required this.signerRole,
    this.signaturePath,
    required this.signedAt,
    required this.status,
    this.rejectionReason,
  });

  factory WorkOrderSignature.fromJson(Map<String, dynamic> json) {
    return WorkOrderSignature(
      id: json['id'] as String,
      workOrderId: json['work_order_id'] as String,
      signerEmail: json['signer_email'] as String,
      signerName: json['signer_name'] as String? ?? '',
      signerRole: json['signer_role'] as String,
      signaturePath: json['signature_path'] as String?,
      signedAt: DateTime.parse(json['signed_at'] as String),
      status: json['status'] as String,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }
}
