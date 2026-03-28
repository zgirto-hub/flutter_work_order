class RegistryEntry {
  final String id;
  final String documentName;
  final String documentNumber;
  final String date;
  final bool replied;
  final String? fileName;
  final String? fileUrl;
  final String createdBy;
  final String? createdAt;

  RegistryEntry({
    required this.id,
    required this.documentName,
    required this.documentNumber,
    required this.date,
    this.replied = false,
    this.fileName,
    this.fileUrl,
    required this.createdBy,
    this.createdAt,
  });

  bool get hasAttachment => fileUrl != null && fileUrl!.isNotEmpty;

  factory RegistryEntry.fromJson(Map<String, dynamic> json) {
    return RegistryEntry(
      id: json['id'].toString(),
      documentName: json['document_name'] ?? '',
      documentNumber: json['document_number'] ?? '',
      date: json['date'] ?? '',
      replied: json['replied'] ?? false,
      fileName: json['file_name'],
      fileUrl: json['file_url'],
      createdBy: json['created_by'] ?? '',
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'document_name': documentName,
    'document_number': documentNumber,
    'date': date,
    'replied': replied,
    'created_by': createdBy,
  };
}
