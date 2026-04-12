import 'package:flutter/material.dart';
import '../../../models/manual_source.dart';

class SourceCard extends StatelessWidget {
  final ManualSource source;

  const SourceCard({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
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
}
