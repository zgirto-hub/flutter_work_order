import 'package:flutter/material.dart';

const _colorInaccurate = Color(0xFFE57373);
const _colorIncomplete = Color(0xFFFFB74D);
const _colorOutdated = Color(0xFFFFCA28);
const _colorWrongSource = Color(0xFFBA68C8);
const _colorUnclear = Color(0xFF90A4AE);

enum FeedbackReason {
  inaccurate('inaccurate', 'Inaccurate', _colorInaccurate),
  incomplete('incomplete', 'Incomplete', _colorIncomplete),
  outdated('outdated', 'Outdated', _colorOutdated),
  wrongSource('wrong_source', 'Wrong source', _colorWrongSource),
  unclear('unclear', 'Unclear', _colorUnclear);

  final String value;
  final String label;
  final Color color;

  const FeedbackReason(this.value, this.label, this.color);

  static FeedbackReason? fromValue(String? value) {
    if (value == null) return null;
    for (final r in FeedbackReason.values) {
      if (r.value == value) return r;
    }
    return null;
  }
}

class FeedbackSheetResult {
  final String reason;
  final String? comment;

  const FeedbackSheetResult({required this.reason, this.comment});
}

class FeedbackReasonSheet extends StatefulWidget {
  const FeedbackReasonSheet({super.key});

  static Future<FeedbackSheetResult?> show(BuildContext context) {
    return showModalBottomSheet<FeedbackSheetResult>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FeedbackReasonSheet(),
    );
  }

  @override
  State<FeedbackReasonSheet> createState() => _FeedbackReasonSheetState();
}

class _FeedbackReasonSheetState extends State<FeedbackReasonSheet> {
  FeedbackReason? _selectedReason;
  final TextEditingController _commentController = TextEditingController();
  bool _counterRed = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _onCommentChanged(String value) {
    setState(() {
      _counterRed = value.length > 500;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    const _textSecondary = Color(0xFF717171);
    const _border2 = Color(0xFFE0E0E0);

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What went wrong?',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: FeedbackReason.values.map((reason) {
                    final isSelected = _selectedReason == reason;
                    return ChoiceChip(
                      label: Text(reason.label),
                      selected: isSelected,
                      selectedColor: reason.color.withValues(alpha: 0.3),
                      backgroundColor: theme.colorScheme.surface,
                      labelStyle: TextStyle(
                        color: isSelected ? reason.color : _textSecondary,
                      ),
                      side: isSelected
                          ? BorderSide(color: reason.color, width: 1.5)
                          : const BorderSide(color: _border2),
                      onSelected: (selected) {
                        setState(() {
                          _selectedReason = selected ? reason : null;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Tell us more (optional)',
                    border: const OutlineInputBorder(),
                    counterText: '${_commentController.text.length}/2000',
                    counterStyle: TextStyle(
                      color: _counterRed ? Colors.red : _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: _onCommentChanged,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Skip'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _selectedReason == null
                          ? null
                          : () {
                              Navigator.pop(
                                context,
                                FeedbackSheetResult(
                                  reason: _selectedReason!.value,
                                  comment: _commentController.text.isNotEmpty
                                      ? _commentController.text
                                      : null,
                                ),
                              );
                            },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
