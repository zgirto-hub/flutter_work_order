import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A28) : const Color(0xFFF5F4F0),
      highlightColor: isDark ? const Color(0xFF3A3A38) : const Color(0xFFFFFFFF),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class WorkOrderCardSkeleton extends StatelessWidget {
  const WorkOrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 200, height: 16),
                    const SizedBox(height: 6),
                    ShimmerBox(width: 80, height: 12),
                  ],
                ),
              ),
              ShimmerBox(width: 70, height: 24, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 12),
          ShimmerBox(width: double.infinity, height: 14),
          const SizedBox(height: 6),
          ShimmerBox(width: 250, height: 14),
          const SizedBox(height: 12),
          Row(
            children: [
              ShimmerBox(width: 32, height: 32, borderRadius: 16),
              const SizedBox(width: 8),
              ShimmerBox(width: 100, height: 12),
              const Spacer(),
              ShimmerBox(width: 60, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

class FileCardSkeleton extends StatelessWidget {
  const FileCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          ShimmerBox(width: 44, height: 44, borderRadius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: double.infinity, height: 16),
                const SizedBox(height: 6),
                ShimmerBox(width: 120, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double spacing;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: spacing),
      itemBuilder: (_, __) => const WorkOrderCardSkeleton(),
    );
  }
}

class FormFieldSkeleton extends StatelessWidget {
  const FormFieldSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShimmerBox(width: 100, height: 12),
        const SizedBox(height: 8),
        ShimmerBox(width: double.infinity, height: 48, borderRadius: 10),
      ],
    );
  }
}

class LoadingContent extends StatelessWidget {
  final int itemCount;

  const LoadingContent({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const WorkOrderCardSkeleton(),
    );
  }
}
