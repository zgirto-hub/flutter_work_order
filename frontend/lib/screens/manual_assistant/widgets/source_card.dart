import 'package:flutter/material.dart';
import '../../../models/manual_source.dart';

class SourceCard extends StatelessWidget {
  final ManualSource source;

  const SourceCard({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    if (source.type == 'document') {
      return _buildDocumentSource(context);
    }
    return _buildManualSource(context);
  }

  Widget _buildDocumentSource(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    source.displayName ?? source.manualTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                if (source.score != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          _getScoreColor(source.score!).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${(source.score! * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getScoreColor(source.score!),
                      ),
                    ),
                  ),
              ],
            ),
            if (source.sectionTitle != null &&
                source.sectionTitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                source.sectionTitle!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (source.pageNumber != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.book, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 2),
                  Text(
                    'Page ${source.pageNumber}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManualSource(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.manualTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'page ${source.sourcePage ?? "—"}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final preview = source.contentPreview;
    final start = source.highlightStart;
    final end = source.highlightEnd;

    if (start == null ||
        end == null ||
        start < 0 ||
        end > preview.length ||
        start >= end) {
      return Text(
        preview,
        style: const TextStyle(fontSize: 12, height: 1.4),
      );
    }

    return Text.rich(
      TextSpan(
        style:
            const TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
        children: [
          TextSpan(text: preview.substring(0, start)),
          TextSpan(
            text: preview.substring(start, end),
            style: TextStyle(
              backgroundColor: Colors.yellow.shade200,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: preview.substring(end)),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 0.85) return Colors.green;
    if (score >= 0.70) return Colors.orange;
    return Colors.red;
  }
}
