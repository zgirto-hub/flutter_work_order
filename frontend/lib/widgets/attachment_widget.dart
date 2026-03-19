import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/work_order_attachment.dart';
import '../theme/app_theme.dart';
import '../config.dart';

class AttachmentWidget extends StatelessWidget {
  final WorkOrderAttachment attachment;
  final VoidCallback? onDelete;
  final bool showDelete;

  const AttachmentWidget({
    super.key,
    required this.attachment,
    this.onDelete,
    this.showDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.icon,
            size: 20,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.fileName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!attachment.isImage)
                  Text(
                    attachment.extension.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _openAttachment(context),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.open_in_new,
                size: 16,
                color: AppColors.accent,
              ),
            ),
          ),
          if (showDelete && onDelete != null) ...[
            GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.dangerText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAttachment(BuildContext context) async {
    final url = '${AppConfig.downloadUrl}${attachment.fileUrl}';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file'),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class PendingAttachmentChip extends StatelessWidget {
  final PlatformFile file;
  final VoidCallback onRemove;

  const PendingAttachmentChip({
    super.key,
    required this.file,
    required this.onRemove,
  });

  IconData get _icon {
    final ext = file.extension?.toLowerCase() ?? '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              file.name,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
