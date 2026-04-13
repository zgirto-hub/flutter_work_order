import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class ChunkCard extends StatelessWidget {
  final Map<String, dynamic> chunk;
  final bool selectionMode;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSplit;
  final VoidCallback? onMerge;
  final ValueChanged<bool?>? onSelectChanged;

  const ChunkCard({
    super.key,
    required this.chunk,
    required this.selectionMode,
    required this.selected,
    required this.isLast,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
    required this.onSplit,
    this.onMerge,
    this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final chunkIndex = chunk['chunk_index'] as int;
    final sourcePage = chunk['source_page'] as int?;
    final content = chunk['content'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Checkbox(
                  value: selected,
                  onChanged: onSelectChanged,
                  activeColor: AppColors.accent,
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$chunkIndex',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sourcePage != null ? 'Page $sourcePage' : 'No page',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert,
                              color: AppColors.textSecondary, size: 20),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'split',
                              child: Row(
                                children: [
                                  Icon(Icons.call_split, size: 18),
                                  SizedBox(width: 8),
                                  Text('Split'),
                                ],
                              ),
                            ),
                            if (!isLast && onMerge != null)
                              const PopupMenuItem(
                                value: 'merge',
                                child: Row(
                                  children: [
                                    Icon(Icons.merge_type, size: 18),
                                    SizedBox(width: 8),
                                    Text('Merge with next'),
                                  ],
                                ),
                              ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                onEdit();
                                break;
                              case 'split':
                                onSplit();
                                break;
                              case 'merge':
                                onMerge?.call();
                                break;
                              case 'delete':
                                onDelete();
                                break;
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      content.length > 200
                          ? '${content.substring(0, 200)}...'
                          : content,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
