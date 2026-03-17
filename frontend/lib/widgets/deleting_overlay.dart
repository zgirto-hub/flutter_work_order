import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DeletingOverlay extends StatelessWidget {
  final int current;
  final int total;

  const DeletingOverlay({super.key, required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : current / total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.dangerBorder, width: 0.5),
              ),
              child: Icon(Icons.delete_sweep_outlined, size: 26, color: AppColors.dangerText),
            ),
            SizedBox(height: 20),
            Text('Deleting $current of $total',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            SizedBox(height: 6),
            Text('Please wait…',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
            SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 7,
                backgroundColor: AppColors.bgSurface3,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.dangerText),
              ),
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$current deleted', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                Text('${(percent * 100).toInt()}%',
                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
                Text('$total total', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
