class ManualSource {
  final String manualId;
  final String manualTitle;
  final int chunkIndex;
  final int? sourcePage;
  final String contentPreview;
  final int? highlightStart;
  final int? highlightEnd;
  final String? type;
  final String? documentId;
  final String? displayName;
  final String? sectionTitle;
  final int? pageNumber;
  final double? score;

  const ManualSource({
    required this.manualId,
    required this.manualTitle,
    required this.chunkIndex,
    this.sourcePage,
    required this.contentPreview,
    this.highlightStart,
    this.highlightEnd,
    this.type,
    this.documentId,
    this.displayName,
    this.sectionTitle,
    this.pageNumber,
    this.score,
  });

  factory ManualSource.fromJson(Map<String, dynamic> json) {
    return ManualSource(
      manualId: json['manual_id'] ?? json['id'] ?? '',
      manualTitle: json['manual_title'] ?? json['display_name'] ?? '',
      chunkIndex: json['chunk_index'] ?? 0,
      sourcePage: json['source_page'] ?? json['page_number'],
      contentPreview: json['content_preview'] ?? '',
      highlightStart: json['highlight_start'],
      highlightEnd: json['highlight_end'],
      type: json['type'] as String?,
      documentId: json['document_id'] as String?,
      displayName: json['display_name'] as String?,
      sectionTitle: json['section_title'] as String?,
      pageNumber: json['page_number'] as int?,
      score: (json['score'] as num?)?.toDouble(),
    );
  }
}
