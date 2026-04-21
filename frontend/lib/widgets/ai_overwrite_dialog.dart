import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class OverwriteField {
  final String fieldName;
  final String fieldLabel;
  final String currentValue;
  final String proposedValue;

  const OverwriteField({
    required this.fieldName,
    required this.fieldLabel,
    required this.currentValue,
    required this.proposedValue,
  });
}

class AiOverwriteDialog extends StatefulWidget {
  final List<OverwriteField> conflicts;

  const AiOverwriteDialog({super.key, required this.conflicts});

  @override
  State<AiOverwriteDialog> createState() => _AiOverwriteDialogState();
}

class _AiOverwriteDialogState extends State<AiOverwriteDialog> {
  late Map<String, bool> _selections;

  @override
  void initState() {
    super.initState();
    _selections = {
      for (final field in widget.conflicts) field.fieldName: false
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI Suggestions'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Some fields already have your input. Choose which to keep:',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ...widget.conflicts.map((field) => _buildConflictRow(field)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(_selections);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _buildConflictRow(OverwriteField field) {
    final useAi = _selections[field.fieldName] ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.fieldLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: useAi ? AppColors.bgSurface2 : AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: useAi ? AppColors.textTertiary : AppColors.accent,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    field.currentValue,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: useAi ? AppColors.accent.withValues(alpha: 0.1) : AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: useAi ? AppColors.accent : AppColors.textTertiary,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    field.proposedValue,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Radio<bool>(
                value: false,
                groupValue: _selections[field.fieldName],
                onChanged: (val) {
                  setState(() => _selections[field.fieldName] = val!);
                },
                activeColor: AppColors.accent,
              ),
              const Text('Keep mine', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 16),
              Radio<bool>(
                value: true,
                groupValue: _selections[field.fieldName],
                onChanged: (val) {
                  setState(() => _selections[field.fieldName] = val!);
                },
                activeColor: AppColors.accent,
              ),
              const Text('Use AI', style: TextStyle(fontSize: 12)),
            ],
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}