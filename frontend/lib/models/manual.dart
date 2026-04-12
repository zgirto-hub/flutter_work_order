class Manual {
  final String id;
  final String title;
  final String fileName;
  final String fileExtension;
  final int fileSizeBytes;
  final String? uploadedBy;
  final String? uploadedByName;
  final int chunkCount;
  final DateTime createdAt;

  const Manual({
    required this.id,
    required this.title,
    required this.fileName,
    required this.fileExtension,
    required this.fileSizeBytes,
    this.uploadedBy,
    this.uploadedByName,
    required this.chunkCount,
    required this.createdAt,
  });

  factory Manual.fromJson(Map<String, dynamic> json) {
    return Manual(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      fileName: json['file_name'] ?? '',
      fileExtension: json['file_extension'] ?? '',
      fileSizeBytes: json['file_size_bytes'] ?? 0,
      uploadedBy: json['uploaded_by'],
      uploadedByName: json['uploaded_by_name'],
      chunkCount: json['chunk_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'file_name': fileName,
      'file_extension': fileExtension,
      'file_size_bytes': fileSizeBytes,
      'uploaded_by': uploadedBy,
      'uploaded_by_name': uploadedByName,
      'chunk_count': chunkCount,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class CorpusStats {
  final int totalBytes;
  final int manualCount;
  final int ceilingBytes;

  const CorpusStats({
    required this.totalBytes,
    required this.manualCount,
    required this.ceilingBytes,
  });

  factory CorpusStats.fromJson(Map<String, dynamic> json) {
    return CorpusStats(
      totalBytes: json['total_bytes'] ?? 0,
      manualCount: json['manual_count'] ?? 0,
      ceilingBytes: json['ceiling_bytes'] ?? 0,
    );
  }
}
