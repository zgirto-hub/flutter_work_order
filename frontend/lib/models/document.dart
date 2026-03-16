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
  final String? role; // 'owner' | 'editor' | 'viewer' | null

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
    this.role,
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
      role: json['role'] as String?,
    );
  }

  DocumentModel copyWith({
    bool? isShared,
    String? folderId,
    String? role,
  }) {
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
      role: role ?? this.role,
    );
  }
}


/// Derived capabilities from a document's role.
/// Used to gate UI actions.
class DocumentCapabilities {
  final bool canView;
  final bool canRename;
  final bool canMove;
  final bool canDelete;
  final bool canShare;
  final bool canEditType;

  const DocumentCapabilities({
    required this.canView,
    required this.canRename,
    required this.canMove,
    required this.canDelete,
    required this.canShare,
    required this.canEditType,
  });

  factory DocumentCapabilities.fromRole(String? role) {
    switch (role) {
      case 'owner':
        return const DocumentCapabilities(
          canView: true, canRename: true, canMove: true,
          canDelete: true, canShare: true, canEditType: true,
        );
      case 'editor':
        return const DocumentCapabilities(
          canView: true, canRename: true, canMove: true,
          canDelete: false, canShare: false, canEditType: true,
        );
      case 'viewer':
      default:
        return const DocumentCapabilities(
          canView: true, canRename: false, canMove: false,
          canDelete: false, canShare: false, canEditType: false,
        );
    }
  }

  /// Convenience: returns true if this user is the owner
  bool get isOwner => canDelete && canShare;
}
