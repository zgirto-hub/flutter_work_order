import 'package:flutter/material.dart';

class QaCandidateCard extends StatefulWidget {
  final String question;
  final String answer;
  final String sourceTitle;
  final bool isApproved;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final Function(String newQuestion, String newAnswer) onEdit;

  const QaCandidateCard({
    super.key,
    required this.question,
    required this.answer,
    required this.sourceTitle,
    this.isApproved = false,
    required this.onApprove,
    required this.onReject,
    required this.onEdit,
  });

  @override
  State<QaCandidateCard> createState() => _QaCandidateCardState();
}

class _QaCandidateCardState extends State<QaCandidateCard> {
  bool _isEditing = false;
  bool _showFullAnswer = false;
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
  void didUpdateWidget(QaCandidateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question != widget.question) {
      _questionController.text = widget.question;
    }
    if (oldWidget.answer != widget.answer) {
      _answerController.text = widget.answer;
    }
  }

  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _questionController.text = widget.question;
        _answerController.text = widget.answer;
      }
    });
  }

  void _saveEdit() {
    widget.onEdit(
        _questionController.text.trim(), _answerController.text.trim());
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final answerLines = widget.answer.split('\n');
    final showTruncate = answerLines.length > 3 && !_showFullAnswer;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: widget.isApproved ? Colors.green : Colors.grey.shade300,
          width: widget.isApproved ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isApproved)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Approved',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Icon(Icons.help_outline, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Question',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_isEditing)
              TextField(
                controller: _questionController,
                maxLines: 2,
                decoration: const InputDecoration(
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
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Answer',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_isEditing)
              TextField(
                controller: _answerController,
                maxLines: 4,
                decoration: const InputDecoration(
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
                  Text(
                    showTruncate
                        ? answerLines.take(3).join('\n')
                        : widget.answer,
                    style: const TextStyle(fontSize: 13),
                    maxLines: showTruncate ? 3 : null,
                  ),
                  if (answerLines.length > 3)
                    TextButton(
                      onPressed: () =>
                          setState(() => _showFullAnswer = !_showFullAnswer),
                      child: Text(_showFullAnswer ? 'Show less' : 'Show more'),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.sourceTitle,
                      style:
                          TextStyle(fontSize: 11, color: Colors.blue.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: widget.onReject,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade600),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _toggleEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(_isEditing ? 'Cancel' : 'Edit'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isEditing ? _saveEdit : widget.onApprove,
                  icon: Icon(
                      _isEditing ? Icons.check : Icons.check_circle_outline,
                      size: 18),
                  label: Text(_isEditing ? 'Save' : 'Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
