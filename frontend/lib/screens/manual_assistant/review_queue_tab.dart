import 'package:flutter/material.dart';
import '../../services/manual_assistant_service.dart';
import 'widgets/review_entry_card.dart';
import 'widgets/variants_modal.dart';

class ReviewQueueTab extends StatefulWidget {
  final String userEmail;
  final ValueChanged<int>? onCountChanged;

  const ReviewQueueTab({
    super.key,
    required this.userEmail,
    this.onCountChanged,
  });

  @override
  State<ReviewQueueTab> createState() => ReviewQueueTabState();
}

class ReviewQueueTabState extends State<ReviewQueueTab> {
  final ManualAssistantService _service = ManualAssistantService();
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  /// Called by parent when tab is re-activated to refresh data.
  void reload() => _loadEntries();

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries =
          await _service.getFlaggedAnswers(userEmail: widget.userEmail);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
        widget.onCountChanged?.call(entries.length);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleApprove(String ratingId) async {
    final entry = _entries.firstWhere((e) => e['id'] == ratingId);
    final questionText = entry['question_text'] as String? ?? '';

    try {
      List<String> variants;
      String? notice;

      try {
        variants = await _service.generateParaphraseVariants(
          questionText: questionText,
          ratingId: ratingId,
        );
        if (variants.isEmpty) {
          notice = 'Automatic variants could not be generated.';
        }
      } catch (e) {
        variants = [];
        notice = 'Automatic variants could not be generated.';
      }

      final selectedVariants = await showVariantsModal(
        context: context,
        originalQuestion: questionText,
        generatedVariants: variants,
        notice: notice,
      );

      if (selectedVariants == null) return;

      await _service.reviewAnswerWithVariants(
        ratingId: ratingId,
        action: 'approve',
        variants: selectedVariants,
      );

      if (mounted) {
        setState(() {
          _entries.removeWhere((e) => e['id'] == ratingId);
        });
        widget.onCountChanged?.call(_entries.length);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selectedVariants.length} verified answers saved'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve: $e')),
        );
      }
    }
  }

  Future<void> _handleCorrect(String ratingId, String correctedAnswer) async {
    try {
      await _service.reviewAnswer(
        ratingId: ratingId,
        action: 'correct',
        correctedAnswer: correctedAnswer,
        reviewerEmail: widget.userEmail,
      );
      if (mounted) {
        setState(() {
          _entries.removeWhere((e) => e['id'] == ratingId);
        });
        widget.onCountChanged?.call(_entries.length);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Answer corrected and added to validated QA')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to correct: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEntries,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text(
              'No flagged answers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'All flagged answers have been reviewed',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3),
          child: Row(
            children: [
              Icon(
                Icons.pending_actions,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '${_entries.length} item${_entries.length == 1 ? '' : 's'} pending review',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loadEntries,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadEntries,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return ReviewEntryCard(
                  entry: entry,
                  onApprove: _handleApprove,
                  onCorrect: _handleCorrect,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
