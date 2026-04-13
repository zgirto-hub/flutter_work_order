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
            if (answer.manualsConsulted.isNotEmpty) ...[
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
                        'Synthesized from ${answer.manualsConsulted.length} manuals: ${answer.manualsConsulted.map((m) => m.title).join(", ")}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.blueGrey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (answer.hasConflicts) ...[
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
            if (answer.model != null) ...[
              const SizedBox(height: 8),
              Text(
                '${answer.model} · ${answer.durationFormatted}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (answer.toolsUsed.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: answer.toolsUsed.map((tool) {
                  final toolName = tool['tool_name'] ?? '';
                  final success = tool['success'] ?? false;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          success ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: success
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Text(
                      toolName,
                      style: TextStyle(
                        fontSize: 10,
                        color: success
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
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
