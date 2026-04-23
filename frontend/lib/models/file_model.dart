class FileModel {
  final String id;
  final String title;
  final String fileType;
  final String? fileName;
  final String? filePath;
  final String? parsedText;
  final bool isPrivate;
  final String? uploadedBy;
  final bool isShared;
  final String? folderId;
  final int? fileSize;
  final String? role; // 'owner' | 'editor' | 'viewer' | null
  final DateTime? expirationDate;
  final String? departmentId;
  final String? departmentName;

  FileModel({
    required this.id,
    required this.title,
    required this.fileType,
    this.fileName,
    this.filePath,
    this.parsedText,
    required this.isPrivate,
    this.uploadedBy,
    this.isShared = false,
    this.folderId,
    this.fileSize,
    this.role,
    this.expirationDate,
    this.departmentId,
    this.departmentName,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      fileType: json['file_type'] ?? '',
      fileName: json['file_name'],
      filePath: json['file_path'],
      parsedText: json['parsed_text'],
      isPrivate: json['is_private'] ?? false,
      uploadedBy: json['uploaded_by'],
      folderId: json['folder_id']?.toString(),
      fileSize: (json['file_size'] as num?)?.toInt(),
      role: json['role'] as String?,
      expirationDate: json['expiration_date'] != null
          ? DateTime.tryParse(json['expiration_date'])
          : null,
      departmentId: json['department_id']?.toString(),
      departmentName: json['department_name'] as String?,
    );
  }

  /// Whether this document has passed its expiration date.
  bool get isExpired =>
      expirationDate != null && expirationDate!.isBefore(DateTime.now());

  /// Whether the document expires within the next 7 days.
  bool get isExpiringSoon =>
      expirationDate != null &&
      !isExpired &&
      expirationDate!.isBefore(DateTime.now().add(const Duration(days: 7)));

  FileModel copyWith({
    bool? isShared,
    String? folderId,
    String? role,
    DateTime? expirationDate,
    bool clearExpiration = false,
    String? departmentId,
    String? departmentName,
  }) {
    return FileModel(
      id: id,
      title: title,
      fileType: fileType,
      fileName: fileName,
      filePath: filePath,
      parsedText: parsedText,
      isPrivate: isPrivate,
      uploadedBy: uploadedBy,
      isShared: isShared ?? this.isShared,
      folderId: folderId ?? this.folderId,
      fileSize: fileSize,
      role: role ?? this.role,
      expirationDate: clearExpiration ? null : (expirationDate ?? this.expirationDate),
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
    );
  }
}


/// Derived capabilities from a document's role.
/// Used to gate UI actions.
class FileCapabilities {
  final bool canView;
  final bool canRename;
  final bool canMove;
  final bool canDelete;
  final bool canShare;
  final bool canEditType;

  const FileCapabilities({
    required this.canView,
    required this.canRename,
    required this.canMove,
    required this.canDelete,
    required this.canShare,
    required this.canEditType,
  });

  factory FileCapabilities.fromRole(String? role) {
    switch (role) {
      case 'owner':
        return const FileCapabilities(
          canView: true, canRename: true, canMove: true,
          canDelete: true, canShare: true, canEditType: true,
        );
      case 'editor':
        return const FileCapabilities(
          canView: true, canRename: true, canMove: true,
          canDelete: false, canShare: false, canEditType: true,
        );
      case 'viewer':
      default:
        return const FileCapabilities(
          canView: true, canRename: false, canMove: false,
          canDelete: false, canShare: false, canEditType: false,
        );
    }
  }

  /// Convenience: returns true if this user is the owner
  bool get isOwner => canDelete && canShare;
}
