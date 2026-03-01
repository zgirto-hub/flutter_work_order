class DocumentModel {
  final String id;
  final String title;
  final String documentType;
  final String? fileName;
  final String? parsedText;
  final DateTime createdAt;

  DocumentModel({
    required this.id,
    required this.title,
    required this.documentType,
    this.fileName,
    this.parsedText,
    required this.createdAt,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'],
      title: json['title'],
      documentType: json['document_type'],
      fileName: json['file_name'],
      parsedText: json['parsed_text'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}