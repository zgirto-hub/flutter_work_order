import 'package:flutter/material.dart';

class UsageSuggestionCard extends StatefulWidget {
  final String question;
  final String answer;
  final int ratingCount;
  final String lastAskedAt;
  final bool isLoading;
  final VoidCallback onAddToCache;
  final Function(String newQuestion, String newAnswer) onEditThenAdd;
  final VoidCallback onDismiss;

  const UsageSuggestionCard({
    super.key,
    required this.question,
    required this.answer,
    required this.ratingCount,
    required this.lastAskedAt,
    this.isLoading = false,
    required this.onAddToCache,
    required this.onEditThenAdd,
    required this.onDismiss,
  });

  @override
  State<UsageSuggestionCard> createState() => _UsageSuggestionCardState();
}

class _UsageSuggestionCardState extends State<UsageSuggestionCard> {
  bool _isEditing = false;
  bool _expanded = false;
  late TextEditingController _questionController;
  late TextEditingController _answerController;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.question);
    _answerController = TextEditingController(text: widget.answer);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final answerLines = widget.answer.split('\n');
    final showTruncate = answerLines.length > 3 && !_expanded;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question
            if (_isEditing)
              TextField(
                controller: _questionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Question',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(8),
                ),
                style: const TextStyle(fontSize: 14),
              )
            else
              Text(
                widget.question,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 8),
            // Answer (collapsible)
            if (_isEditing)
              TextField(
                controller: _answerController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Answer',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(8),
                ),
                style: const TextStyle(fontSize: 13),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      showTruncate
                          ? answerLines.take(3).join('\n')
                          : widget.answer,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (answerLines.length > 3)
                    TextButton(
                      onPressed: () =>
                          setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Show less' : 'Show more'),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            // Rating badge + date
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.thumb_up, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.ratingCount} ratings',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  'Last asked: ${_formatDate(widget.lastAskedAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Action row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isEditing) ...[
                  OutlinedButton(
                    onPressed: () => setState(() => _isEditing = false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: widget.isLoading
                        ? null
                        : () {
                            widget.onEditThenAdd(
                              _questionController.text.trim(),
                              _answerController.text.trim(),
                            );
                          },
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: const Text('Save & Add'),
                  ),
                ] else ...[
                  TextButton.icon(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Dismiss'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _isEditing = true),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit then Add'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.isLoading ? null : widget.onAddToCache,
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Add to Cache'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inDays > 0) return '${diff.inDays} days ago';
      if (diff.inHours > 0) return '${diff.inHours} hours ago';
      return '${diff.inMinutes} min ago';
    } catch (_) {
      return dateStr;
    }
  }
}
