import 'package:flutter/material.dart';
import '../../../widgets/bottom_sheet_widgets.dart';

Future<List<String>?> showVariantsModal({
  required BuildContext context,
  required String originalQuestion,
  required List<String> generatedVariants,
  String? notice,
}) async {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => VariantsModal(
      originalQuestion: originalQuestion,
      generatedVariants: generatedVariants,
      notice: notice,
    ),
  );
}

class VariantsModal extends StatefulWidget {
  final String originalQuestion;
  final List<String> generatedVariants;
  final String? notice;

  const VariantsModal({
    super.key,
    required this.originalQuestion,
    required this.generatedVariants,
    this.notice,
  });

  @override
  State<VariantsModal> createState() => _VariantsModalState();
}

class _VariantsModalState extends State<VariantsModal> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      TextEditingController(text: widget.originalQuestion),
      ...widget.generatedVariants.map((v) => TextEditingController(text: v)),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get _nonEmptyTexts {
    return _controllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  bool get _canSave {
    final nonEmpty = _nonEmptyTexts;
    return nonEmpty.isNotEmpty && nonEmpty.every((t) => t.length <= 500);
  }

  void _addVariant() {
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removeVariant(int index) {
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BottomSheetContainer(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Save verified answer',
                  style: theme.textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.notice != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.notice!,
                        style: TextStyle(
                            color: Colors.orange.shade900, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Edit or remove variants, then save all:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_controllers.length, (index) {
                    final controller = _controllers[index];
                    return _VariantChip(
                      controller: controller,
                      onDelete: () => _removeVariant(index),
                      onChanged: (_) => setState(() {}),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _addVariant,
                  child: const Text('Add variant'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canSave
                      ? () => Navigator.pop(context, _nonEmptyTexts)
                      : null,
                  child: const Text('Save all'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onChanged;

  const _VariantChip({
    required this.controller,
    this.onDelete,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = controller.text.trim();
    final isOverLength = text.length > 500;

    return InputChip(
      label: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 320),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: InputBorder.none,
            hintText: 'Enter variant...',
            errorText: isOverLength ? 'Too long (max 500 chars)' : null,
            errorStyle: const TextStyle(fontSize: 11),
          ),
          style: Theme.of(context).textTheme.bodyMedium,
          maxLines: 1,
          onChanged: onChanged,
        ),
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onDelete,
      backgroundColor: isOverLength
          ? Colors.red.shade50
          : Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
