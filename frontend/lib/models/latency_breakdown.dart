class LatencyBreakdown {
  final int? embedMs;
  final int? hydeMs;
  final int? rewriteMs;
  final int? retrievalMs;
  final int? rerankMs;
  final int? generatorMs;
  final int totalMs;

  const LatencyBreakdown({
    this.embedMs,
    this.hydeMs,
    this.rewriteMs,
    this.retrievalMs,
    this.rerankMs,
    this.generatorMs,
    required this.totalMs,
  });

  factory LatencyBreakdown.fromJson(Map<String, dynamic> json) =>
      LatencyBreakdown(
        embedMs: json['embed_ms'] as int?,
        hydeMs: json['hyde_ms'] as int?,
        rewriteMs: json['rewrite_ms'] as int?,
        retrievalMs: json['retrieval_ms'] as int?,
        rerankMs: json['rerank_ms'] as int?,
        generatorMs: json['generator_ms'] as int?,
        totalMs: json['total_ms'] as int,
      );
}
