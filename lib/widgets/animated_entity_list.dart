import 'package:flutter/material.dart';

class AnimatedEntityList<T> extends StatelessWidget {
  final List<T> items;
  final Future<void> Function()? onRefresh;
  final Widget Function(BuildContext, T, int) itemBuilder;

  const AnimatedEntityList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {

    Widget list = ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {

        final item = items[index];

        return TweenAnimationBuilder<double>(
          key: ValueKey(index),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            );
          },
          child: itemBuilder(context, item, index),
        );
      },
    );

    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: onRefresh!,
        child: list,
      );
    }

    return list;
  }
}