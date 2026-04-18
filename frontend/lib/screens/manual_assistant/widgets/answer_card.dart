import 'package:flutter/material.dart';
import '../../../models/manual_qa_answer.dart';
import '../../../models/latency_breakdown.dart';
import '../../../utils/latency_formatter.dart';
import 'source_card.dart';

class AnswerCard extends StatefulWidget {
  final ManualQaAnswer answer;
  final String questionText;
  final Function(String rating)? onRate;
  final VoidCallback? onUnrate;
  final String? ratingId;
  final bool isStreaming;

  const AnswerCard({
    super.key,
    required this.answer,
    this.questionText = '',
    this.onRate,
    this.onUnrate,
    this.ratingId,
    this.isStreaming = false,
  });

  @override
  State<AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends State<AnswerCard>
    with SingleTickerProviderStateMixin {
  String? _selectedRating;
  bool _expanded = false;
  late AnimationController _cursorController;
  late Animation<double> _cursorAnimation;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);
    _cursorAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_cursorController);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isVerified = widget.answer.isVerified;

    if (widget.isStreaming) {
      return Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.answer.answer,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _cursorAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _cursorAnimation.value,
                        child: const Text(
                          '|',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

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
            if (isVerified && widget.answer.verificationMode == 'synthesized') ...[
              const SizedBox(height: 8),
              Text(
                'Synthesized from ${widget.answer.verifiedSourceCount ?? widget.answer.sources.length} verified sources',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
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
              if (widget.answer.retrievalInfo?.filterApplied == true &&
                  widget.answer.retrievalInfo?.detectedSystem != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt_outlined,
                          size: 12, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Filtered to: ${widget.answer.retrievalInfo!.detectedSystem}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.blue.shade700),
                      ),
                    ],
                  ),
                ),
              ],
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
            if (widget.answer.latencyBreakdown != null) ...[
              const SizedBox(height: 8),
              _buildLatencyFooter(widget.answer.latencyBreakdown!),
            ] else if (widget.answer.providerDisplayName != null ||
                widget.answer.model != null) ...[
              const SizedBox(height: 8),
              Text(
                '${widget.answer.providerDisplayName ?? widget.answer.model ?? 'Unknown'} · ${widget.answer.durationFormatted}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (widget.answer.toolsUsed.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: widget.answer.toolsUsed.map((tool) {
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
            if (!isVerified && widget.answer.sources.isNotEmpty) ...[
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
    if (_selectedRating == rating) {
      setState(() => _selectedRating = null);
      widget.onUnrate?.call();
      return;
    }
    setState(() => _selectedRating = rating);
    widget.onRate?.call(rating);
  }

  Widget _buildLatencyFooter(LatencyBreakdown lb) {
    final providerName = widget.answer.providerDisplayName ?? 'Unknown';
    final hasGenerator = lb.generatorMs != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              providerName,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (hasGenerator) ...[
              Text(
                ' · ${formatStageLatency(lb.generatorMs)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            Text(
              ' · pipeline ${formatStageLatency(lb.totalMs)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
            const Spacer(),
            Semantics(
              label: 'Show pipeline timing breakdown',
              button: true,
              child: IconButton(
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ),
          ],
        ),
        if (_expanded)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Column(
              children: [
                _latencyRow('Embed', lb.embedMs),
                _latencyRow('HyDE', lb.hydeMs),
                _latencyRow('Rewrite', lb.rewriteMs),
                _latencyRow('Retrieval', lb.retrievalMs),
                _latencyRow('Rerank', lb.rerankMs),
                _latencyRow('Generator', lb.generatorMs),
                _latencyRow('Total', lb.totalMs),
              ],
            ),
          ),
      ],
    );
  }

  Widget _latencyRow(String label, int? ms) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          const Spacer(),
          Text(
            formatStageLatency(ms),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
