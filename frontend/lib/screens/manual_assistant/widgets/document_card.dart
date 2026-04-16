import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class DocumentCard extends StatelessWidget {
  final Map<String, dynamic> document;
  final VoidCallback onReindex;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const DocumentCard({
    super.key,
    required this.document,
    required this.onReindex,
    required this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = document['status'] ?? 'pending';
    final displayName = document['display_name'] ?? 'Untitled';
    final filename = document['filename'] ?? '';
    final totalChunks = document['total_chunks'];
    final uploadedBy = document['uploaded_by'] ?? '';
    final createdAt = document['created_at'] ?? '';
    final errorMessage = document['error_message'];
    final isReady = status == 'ready';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: isReady ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 4),
              Text(filename, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                children: [
                  if (totalChunks != null)
                    Text('$totalChunks chunks',
                        style: Theme.of(context).textTheme.bodySmall),
                  Text('by $uploadedBy',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(_formatDate(createdAt),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (status == 'preprocessing' || status == 'indexing') ...[
                const SizedBox(height: 8),
                _progressBar(status),
              ],
              if (status == 'failed' && errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.computeLuminance() > 0.5
                            ? Colors.red.withValues(alpha: 0.7)
                            : Colors.red.withValues(alpha: 1.0),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isReady && onTap != null)
                    TextButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.list_alt, size: 18),
                      label: const Text('Chunks'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Re-index',
                    onPressed: (status == 'indexing' || status == 'preprocessing') ? null : onReindex,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete',
                    color: Colors.red.shade400,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'ready':
        color = Colors.green;
        label = 'Ready';
        break;
      case 'preprocessing':
        color = Colors.cyan;
        label = 'Enhancing content...';
        break;
      case 'indexing':
        color = Colors.amber;
        label = 'Indexing';
        break;
      case 'failed':
        color = Colors.red;
        label = 'Failed';
        break;
      default:
        color = Colors.grey;
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color.computeLuminance() > 0.5
              ? color.withValues(alpha: 0.7)
              : color.withValues(alpha: 1.0),
        ),
      ),
    );
  }

  Widget _progressBar(String status) {
    final totalPages = document['total_pages'] as int? ?? 0;
    final progress = document['preprocessing_progress'] as int? ?? 0;
    final isPreprocessing = status == 'preprocessing';

    final double fraction =
        isPreprocessing && totalPages > 0 ? progress / totalPages : 0;
    final String label = isPreprocessing
        ? 'Enhancing page $progress of $totalPages'
        : 'Indexing...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: isPreprocessing ? fraction : null,
            minHeight: 6,
            backgroundColor: AppColors.bgSurface2,
            valueColor: AlwaysStoppedAnimation<Color>(
              isPreprocessing ? Colors.cyan : Colors.amber,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
