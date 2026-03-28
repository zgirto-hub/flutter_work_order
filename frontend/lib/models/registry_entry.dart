class RegistryEntry {
  final String id;
  final String documentName;
  final String documentNumber;
  final String date;
  final String createdBy;
  final String? createdAt;

  RegistryEntry({
    required this.id,
    required this.documentName,
    required this.documentNumber,
    required this.date,
    required this.createdBy,
    this.createdAt,
  });

  factory RegistryEntry.fromJson(Map<String, dynamic> json) {
    return RegistryEntry(
      id: json['id'].toString(),
      documentName: json['document_name'] ?? '',
      documentNumber: json['document_number'] ?? '',
      date: json['date'] ?? '',
      createdBy: json['created_by'] ?? '',
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'document_name': documentName,
    'document_number': documentNumber,
    'date': date,
    'created_by': createdBy,
  };
}
