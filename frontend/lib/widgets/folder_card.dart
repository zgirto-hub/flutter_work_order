import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/folder_model.dart';
import '../theme/app_theme.dart';

class FolderCard extends StatelessWidget {
  final FolderModel folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final bool selectionMode;

  const FolderCard({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser?.email;
    final isOwner = folder.createdBy == currentUser;

    return GestureDetector(
      onTap: onTap,
      onLongPress: selectionMode
          ? null
          : () {
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.bgSurface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => _FolderActionSheet(
                  folder: folder,
                  isOwner: isOwner,
                  onRename: () { Navigator.pop(context); onRename(); },
                  onMove: () { Navigator.pop(context); onMove(); },
                  onDelete: () { Navigator.pop(context); onDelete(); },
                ),
              );
            },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            // Folder icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.folder_outlined, size: 19, color: AppColors.accent),
            ),

            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Text(
                folder.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _FolderActionSheet extends StatelessWidget {
  final FolderModel folder;
  final bool isOwner;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  const _FolderActionSheet({
    required this.folder,
    required this.isOwner,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(folder.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          const Text('Folder', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(height: 14),
          const Divider(height: 0, thickness: 0.5),
          _FolderActionRow(icon: Icons.edit_outlined, label: 'Rename', enabled: isOwner, onTap: isOwner ? onRename : null),
          _FolderActionRow(icon: Icons.drive_file_move_outline, label: 'Move to folder', enabled: isOwner, onTap: isOwner ? onMove : null),
          _FolderActionRow(icon: Icons.delete_outline_rounded, label: 'Delete', enabled: isOwner, danger: true, onTap: isOwner ? onDelete : null),
          const Divider(height: 0, thickness: 0.5),
          _FolderActionRow(icon: Icons.close_rounded, label: 'Cancel', onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _FolderActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool danger;

  const _FolderActionRow({required this.icon, required this.label, this.onTap, this.enabled = true, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerText : enabled ? AppColors.textPrimary : AppColors.textTertiary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: color),
      title: Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
      onTap: enabled ? onTap : null,
    );
  }
}
