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
  final String? folderId;
  final int? fileSize;

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
    this.folderId,
    this.fileSize,
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
      folderId: json['folder_id']?.toString(),
      fileSize: (json['file_size'] as num?)?.toInt(),
    );
  }

  DocumentModel copyWith({bool? isShared, String? folderId}) {
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
      folderId: folderId ?? this.folderId,
      fileSize: fileSize,
    );
  }
}