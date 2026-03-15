import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../theme/app_theme.dart';

class BreadcrumbRow extends StatelessWidget {
  final List<FolderModel> breadcrumb;
  final VoidCallback onTapRoot;
  final void Function(int index) onTapLevel;

  const BreadcrumbRow({
    super.key,
    required this.breadcrumb,
    required this.onTapRoot,
    required this.onTapLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: onTapRoot,
              child: const Icon(Icons.home_outlined, size: 14, color: AppColors.accent),
            ),
            for (int i = 0; i < breadcrumb.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textTertiary),
              ),
              GestureDetector(
                onTap: () => onTapLevel(i),
                child: Text(
                  breadcrumb[i].name,
                  style: TextStyle(
                    fontSize: 12,
                    color: i == breadcrumb.length - 1 ? AppColors.textPrimary : AppColors.accent,
                    fontWeight: i == breadcrumb.length - 1 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
