import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class DocumentChunkCard extends StatelessWidget {
  final Map<String, dynamic> chunk;
  final bool isParent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSplit;
  final VoidCallback? onMerge;
  final VoidCallback? onReEmbed;

  const DocumentChunkCard({
    super.key,
    required this.chunk,
    required this.isParent,
    required this.onEdit,
    required this.onDelete,
    required this.onSplit,
    this.onMerge,
    this.onReEmbed,
  });

  @override
  Widget build(BuildContext context) {
    final chunkType = chunk['chunk_type'] as String? ?? 'child';
    final sectionTitle = chunk['section_title'] as String? ?? '';
    final pageNumber = chunk['page_number'] as int?;
    final content = chunk['content'] as String? ?? '';
    final charCount = chunk['char_count'] as int? ?? content.length;
    final embeddingStale = chunk['embedding_stale'] as bool? ?? false;
    final childrenCount = chunk['children_count'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        isParent ? AppColors.textSecondary : AppColors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isParent ? 'Parent' : 'Child',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (pageNumber != null)
                  Text(
                    'Page $pageNumber',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  '$charCount chars',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                if (embeddingStale)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber,
                            size: 12, color: Colors.amber.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Stale',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isParent && childrenCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '$childrenCount children',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
            if (sectionTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                sectionTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
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
            if (!isParent) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onSplit,
                    icon: const Icon(Icons.call_split, size: 16),
                    label: const Text('Split'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  if (onMerge != null)
                    TextButton.icon(
                      onPressed: onMerge,
                      icon: const Icon(Icons.merge_type, size: 16),
                      label: const Text('Merge'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
}
