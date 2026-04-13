import 'package:flutter/material.dart';
import '../../../models/manual_qa_answer.dart';
import 'source_card.dart';

class AnswerCard extends StatefulWidget {
  final ManualQaAnswer answer;
  final String questionText;
  final Function(String rating)? onRate;

  const AnswerCard({
    super.key,
    required this.answer,
    this.questionText = '',
    this.onRate,
  });

  @override
  State<AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends State<AnswerCard> {
  String? _selectedRating;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isVerified = widget.answer.isVerified;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isVerified) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified,
                        size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Verified Answer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              widget.answer.answer,
              style: const TextStyle(fontSize: 14),
            ),
            if (widget.answer.manualsConsulted.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 14, color: Colors.blueGrey.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Synthesized from ${widget.answer.manualsConsulted.length} manuals: ${widget.answer.manualsConsulted.map((m) => m.title).join(", ")}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.blueGrey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.answer.hasConflicts) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.amber.shade800),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'This answer contains conflicting information between manuals',
                        style: TextStyle(
                            fontSize: 11, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.answer.model != null) ...[
              const SizedBox(height: 8),
              Text(
                '${widget.answer.model} · ${widget.answer.durationFormatted}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (widget.answer.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text('Sources (${widget.answer.sources.length})'),
                children: widget.answer.sources
                    .map((source) => SourceCard(source: source))
                    .toList(),
              ),
            ],
            if (widget.onRate != null) ...[
              const SizedBox(height: 8),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Was this helpful?',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.thumb_up_outlined,
                      color: _selectedRating == 'positive'
                          ? primaryColor
                          : Colors.grey,
                      size: 20,
                    ),
                    onPressed: () => _handleRate('positive'),
                    tooltip: 'Thumbs up',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.thumb_down_outlined,
                      color: _selectedRating == 'negative'
                          ? Colors.red.shade400
                          : Colors.grey,
                      size: 20,
                    ),
                    onPressed: () => _handleRate('negative'),
                    tooltip: 'Thumbs down',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleRate(String rating) {
    if (_selectedRating == rating) return;
    setState(() => _selectedRating = rating);
    widget.onRate?.call(rating);
  }
}
