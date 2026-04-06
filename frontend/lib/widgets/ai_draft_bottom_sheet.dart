import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'bottom_sheet_widgets.dart';

enum AiDraftAction { create, edit }

Future<AiDraftAction?> showAiDraftBottomSheet({
  required BuildContext context,
  required Map<String, dynamic> draftData,
}) {
  return showAppBottomSheet<AiDraftAction>(
    context: context,
    child: _AiDraftContent(draftData: draftData),
  );
}

class _AiDraftContent extends StatelessWidget {
  final Map<String, dynamic> draftData;

  const _AiDraftContent({required this.draftData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleIsEmpty = draftData['title'] == null ||
        draftData['title'].toString().trim().isEmpty;

    final fields = [
      ('Title', draftData['title']),
      ('Description', draftData['description']),
      ('Location', draftData['location']),
      ('Type', draftData['type']),
      ('Department', draftData['department']),
      ('Status', draftData['status']),
    ];

    final nonEmptyFields = fields
        .where((f) => f.$2 != null && f.$2.toString().trim().isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.accent),
              const SizedBox(width: 8),
              Text("Draft Work Order", style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          ...nonEmptyFields
              .map((field) => _buildFieldRow(field.$1, field.$2, theme)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, AiDraftAction.edit),
                  child: const Text("Edit"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: titleIsEmpty
                      ? null
                      : () => Navigator.pop(context, AiDraftAction.create),
                  child: const Text("Create"),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, dynamic value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.toString() ?? '',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
