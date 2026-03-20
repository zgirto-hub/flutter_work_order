import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => BottomSheetContainer(child: child),
  );
}

class BottomSheetContainer extends StatelessWidget {
  final Widget child;
  final double? maxHeight;

  const BottomSheetContainer({
    super.key,
    required this.child,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight ?? screenHeight * 0.9),
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
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class FilterOption {
  final String value;
  final String label;
  final String? description;
  final IconData? icon;

  const FilterOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
  });
}

class FilterBottomSheet extends StatelessWidget {
  final List<FilterOption> options;
  final String? selectedValue;
  final ValueChanged<String> onSelected;
  final String title;

  const FilterBottomSheet({
    super.key,
    required this.options,
    this.selectedValue,
    required this.onSelected,
    this.title = 'Filter',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final isSelected = option.value == selectedValue;

                return InkWell(
                  onTap: () {
                    onSelected(option.value);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent.withValues(alpha: 0.1)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        if (option.icon != null) ...[
                          Icon(
                            option.icon,
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.label,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: isSelected
                                      ? AppColors.accent
                                      : null,
                                  fontWeight:
                                      isSelected ? FontWeight.w600 : null,
                                ),
                              ),
                              if (option.description != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  option.description!,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check, color: AppColors.accent),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

class ActionOption {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const ActionOption({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });
}

class ActionsBottomSheet extends StatelessWidget {
  final List<ActionOption> actions;
  final String? title;

  const ActionsBottomSheet({
    super.key,
    required this.actions,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
          ],
          ...actions.map((action) => InkWell(
                onTap: () {
                  Navigator.pop(context);
                  action.onTap();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        action.icon,
                        color: action.isDestructive
                            ? AppColors.dangerText
                            : AppColors.textPrimary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          action.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: action.isDestructive
                                ? AppColors.dangerText
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
