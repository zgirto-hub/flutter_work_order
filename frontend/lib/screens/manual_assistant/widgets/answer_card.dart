import 'package:flutter/material.dart';
import '../../../models/manual_qa_answer.dart';
import 'source_card.dart';

class AnswerCard extends StatelessWidget {
  final ManualQaAnswer answer;

  const AnswerCard({super.key, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              answer.answer,
              style: const TextStyle(fontSize: 14),
            ),
            if (answer.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text('Sources (${answer.sources.length})'),
                children: answer.sources
                    .map((source) => SourceCard(source: source))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
