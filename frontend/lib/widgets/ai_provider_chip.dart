import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AiProviderChip extends StatelessWidget {
  final String providerDisplayName;
  final bool fallbackUsed;

  const AiProviderChip({
    super.key,
    required this.providerDisplayName,
    this.fallbackUsed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (fallbackUsed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 12,
              color: Color(0xFFD97706),
            ),
            const SizedBox(width: 4),
            Text(
              '$providerDisplayName (fallback)',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFFD97706),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF22C55E),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            providerDisplayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
