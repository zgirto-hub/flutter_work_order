import 'package:flutter/material.dart';

class StaleEntryCard extends StatefulWidget {
  final String qaId;
  final String question;
  final String answer;
  final String manualTitle;
  final int daysSinceUpdate;
  final bool isLoading;
  final VoidCallback onConfirm;
  final Function(String newQuestion, String newAnswer) onEditConfirm;
  final VoidCallback onRemove;

  const StaleEntryCard({
    super.key,
    required this.qaId,
    required this.question,
    required this.answer,
    required this.manualTitle,
    required this.daysSinceUpdate,
    this.isLoading = false,
    required this.onConfirm,
    required this.onEditConfirm,
    required this.onRemove,
  });

  @override
  State<StaleEntryCard> createState() => _StaleEntryCardState();
}

class _StaleEntryCardState extends State<StaleEntryCard> {
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

  void _confirmRemove() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Cache'),
        content: const Text(
          'Remove this answer and all its variants from the cache? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onRemove();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final answerLines = widget.answer.split('\n');
    final showTruncate = answerLines.length > 3 && !_expanded;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.orange.shade300, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber,
                      size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Source manual was updated ${widget.daysSinceUpdate} days ago',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Manual name
            Row(
              children: [
                Icon(Icons.menu_book, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  widget.manualTitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                            widget.onEditConfirm(
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
                    label: const Text('Save & Reconfirm'),
                  ),
                ] else ...[
                  TextButton.icon(
                    onPressed: widget.isLoading ? null : _confirmRemove,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Remove'),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _isEditing = true),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit & Reconfirm'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.isLoading ? null : widget.onConfirm,
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Still Valid'),
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
}
