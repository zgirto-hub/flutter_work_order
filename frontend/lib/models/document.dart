class DocumentModel {
  final String id;
  final String title;
  final String documentType;
  final String? fileName;
  final String? filePath;
  final String? parsedText;

  final bool isPrivate;
  final String? uploadedBy;
  final bool isShared;

  DocumentModel({
    required this.id,
    required this.title,
    required this.documentType,
    this.fileName,
    this.filePath,
    this.parsedText,
    required this.isPrivate,
    this.uploadedBy,
    this.isShared = false,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      documentType: json['document_type'] ?? '',
      fileName: json['file_name'],
      filePath: json['file_path'],
      parsedText: json['parsed_text'],
      isPrivate: json['is_private'] ?? false,
      uploadedBy: json['uploaded_by'],
    );
  }

  DocumentModel copyWith({bool? isShared}) {
    return DocumentModel(
      id: id,
      title: title,
      documentType: documentType,
      fileName: fileName,
      filePath: filePath,
      parsedText: parsedText,
      isPrivate: isPrivate,
      uploadedBy: uploadedBy,
      isShared: isShared ?? this.isShared,
    );
  }
}