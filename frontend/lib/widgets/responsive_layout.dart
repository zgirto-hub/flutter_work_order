import 'package:flutter/material.dart';
import '../constants/app_icons.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isDesktop(context) && desktop != null) {
      return desktop!;
    }

    if (Breakpoints.isTablet(context) && tablet != null) {
      return tablet!;
    }

    return mobile;
  }
}

class ContentContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const ContentContainer({
    super.key,
    required this.child,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? Breakpoints.getContentWidth(context),
        ),
        child: child,
      ),
    );
  }
}

class ResponsivePadding extends StatelessWidget {
  final Widget child;
  final bool horizontalOnly;

  const ResponsivePadding({
    super.key,
    required this.child,
    this.horizontalOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final padding = Breakpoints.getPagePadding(context);
    return Padding(
      padding: horizontalOnly ? EdgeInsets.symmetric(horizontal: padding.left) : padding,
      child: child,
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 16,
    this.runSpacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    final columns = Breakpoints.getGridColumns(context);

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children.map((child) {
        final availableWidth = MediaQuery.of(context).size.width -
            (Breakpoints.getPagePadding(context).left + Breakpoints.getPagePadding(context).right) -
            (spacing * (columns - 1));
        final itemWidth = availableWidth / columns;
        return SizedBox(
          width: itemWidth,
          child: child,
        );
      }).toList(),
    );
  }
}
