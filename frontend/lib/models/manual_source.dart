class ManualSource {
  final String manualId;
  final String manualTitle;
  final int chunkIndex;
  final int? sourcePage;
  final String contentPreview;
  final int? highlightStart;
  final int? highlightEnd;

  const ManualSource({
    required this.manualId,
    required this.manualTitle,
    required this.chunkIndex,
    this.sourcePage,
    required this.contentPreview,
    this.highlightStart,
    this.highlightEnd,
  });

  factory ManualSource.fromJson(Map<String, dynamic> json) {
    return ManualSource(
      manualId: json['manual_id'] ?? '',
      manualTitle: json['manual_title'] ?? '',
      chunkIndex: json['chunk_index'] ?? 0,
      sourcePage: json['source_page'],
      contentPreview: json['content_preview'] ?? '',
      highlightStart: json['highlight_start'],
      highlightEnd: json['highlight_end'],
    );
  }
}
