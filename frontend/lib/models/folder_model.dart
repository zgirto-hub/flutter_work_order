class FolderModel {
  final String id;
  final String name;
  final String? parentId;
  final String createdBy;
  final bool isPrivate;

  const FolderModel({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdBy,
    this.isPrivate = false,
  });

  factory FolderModel.fromJson(Map<String, dynamic> json) {
    return FolderModel(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      parentId: json['parent_id']?.toString(),
      createdBy: json['created_by'] ?? '',
      isPrivate: json['is_private'] ?? false,
    );
  }
}
