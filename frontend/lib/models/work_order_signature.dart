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
      id: (json['id'] ?? '').toString(),
      workOrderId: (json['work_order_id'] ?? '').toString(),
      signerEmail: (json['signer_email'] ?? '').toString(),
      signerName: (json['signer_name'] ?? '').toString(),
      signerRole: (json['signer_role'] ?? '').toString(),
      signaturePath: json['signature_path']?.toString(),
      signedAt: DateTime.tryParse(json['signed_at']?.toString() ?? '') ??
          DateTime.now(),
      status: (json['status'] ?? '').toString(),
      rejectionReason: json['rejection_reason']?.toString(),
    );
  }
}
