import 'package:flutter/material.dart';

class ReviewEntryCard extends StatefulWidget {
  final Map<String, dynamic> entry;
  final Function(String ratingId) onApprove;
  final Function(String ratingId, String correctedAnswer) onCorrect;

  const ReviewEntryCard({
    super.key,
    required this.entry,
    required this.onApprove,
    required this.onCorrect,
  });

  @override
  State<ReviewEntryCard> createState() => _ReviewEntryCardState();
}

class _ReviewEntryCardState extends State<ReviewEntryCard> {
  final TextEditingController _correctController = TextEditingController();
  bool _showCorrection = false;

  @override
  void dispose() {
    _correctController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questionText = widget.entry['question_text'] as String? ?? '';
    final answerText = widget.entry['answer_text'] as String? ?? '';
    final sourceChunks = widget.entry['source_chunks'] as List<dynamic>? ?? [];
    final createdAt = widget.entry['created_at'] as String?;
    final raterEmail = widget.entry['rater_email'] as String? ?? '';
    final entryId = widget.entry['id'] as String? ?? '';
    final isReflagged = widget.entry['is_reflagged'] as bool? ?? false;
    final thumbsUp = widget.entry['thumbs_up_count'] as int? ?? 0;
    final thumbsDown = widget.entry['thumbs_down_count'] as int? ?? 0;

    DateTime? parsedDate;
    if (createdAt != null) {
      parsedDate = DateTime.tryParse(createdAt);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isReflagged) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber,
                        size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Re-flagged ($thumbsUp up / $thumbsDown down)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              questionText,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  answerText,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            if (sourceChunks.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                title: Text('Sources (${sourceChunks.length})'),
                tilePadding: EdgeInsets.zero,
                children: sourceChunks.map((chunk) {
                  final manualTitle =
                      chunk['manual_title'] as String? ?? 'Unknown';
                  final sourcePage = chunk['source_page'];
                  final content = chunk['content'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.article_outlined, size: 18),
                    title: Text(
                      '$manualTitle ${sourcePage != null ? "— Page $sourcePage" : ""}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      content.length > 150
                          ? '${content.substring(0, 150)}...'
                          : content,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (parsedDate != null) ...[
                  Icon(Icons.access_time,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(parsedDate),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 12),
                ],
                Icon(Icons.person_outline,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  raterEmail,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => widget.onApprove(entryId),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showCorrection = !_showCorrection),
                  icon: const Icon(Icons.edit, size: 18),
                  label: Text(_showCorrection ? 'Cancel' : 'Correct'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
            if (_showCorrection) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _correctController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Enter corrected answer...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () {
                    if (_correctController.text.trim().isNotEmpty) {
                      widget.onCorrect(entryId, _correctController.text.trim());
                      _correctController.clear();
                      setState(() => _showCorrection = false);
                    }
                  },
                  child: const Text('Save Correction'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
