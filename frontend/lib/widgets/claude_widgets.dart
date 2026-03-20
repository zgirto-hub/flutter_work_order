import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─── Status Badge ────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final String status;
  final bool isSmall;

  const StatusBadge({super.key, required this.status, this.isSmall = false});

  String get _statusLabel {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'in progress':
        return 'In Progress';
      case 'closed':
        return 'Closed';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color bg;
    Color text;

    switch (status.toLowerCase()) {
      case 'pending':
        bg = AppColors.pendingBg;
        text = AppColors.pendingText;
        break;
      case 'in progress':
        bg = AppColors.inProgressBg;
        text = AppColors.inProgressText;
        break;
      case 'closed':
        bg = AppColors.closedBg;
        text = AppColors.closedText;
        break;
      default:
        bg = AppColors.bgSurface2;
        text = AppColors.textSecondary;
    }

    return Semantics(
      label: 'Status: $_statusLabel',
      readOnly: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 8 : 10,
          vertical: isSmall ? 4 : 6,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(
          status,
          style: theme.textTheme.labelSmall?.copyWith(
            color: text,
            fontSize: isSmall ? 10 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Section Label ───────────────────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SectionLabel({
    super.key,
    required this.text,
    this.padding = const EdgeInsets.only(bottom: 6, top: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.06,
        ),
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final Color? iconColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIconColor = iconColor ?? AppColors.accent;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: effectiveIconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: effectiveIconColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Surface Card ─────────────────────────────────────────────────────────────

enum SurfaceLevel { base, elevated, raised }

class SurfaceCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final SurfaceLevel level;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.borderRadius,
    this.level = SurfaceLevel.elevated,
  });

  @override
  State<SurfaceCard> createState() => _SurfaceCardState();
}

class _SurfaceCardState extends State<SurfaceCard> {
  bool _isPressed = false;

  List<BoxShadow>? _getShadows() {
    final brightness = Theme.of(context).brightness;
    switch (widget.level) {
      case SurfaceLevel.base:
        return null;
      case SurfaceLevel.elevated:
        return _isPressed ? AppShadows.cardLight : AppShadows.card(brightness);
      case SurfaceLevel.raised:
        return _isPressed
            ? AppShadows.card(brightness)
            : AppShadows.card(brightness, elevated: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(14);

    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _isPressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: widget.onTap != null ? () => setState(() => _isPressed = false) : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: _getShadows(),
          ),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}

// ─── Filter Chip Row ──────────────────────────────────────────────────────────

class FilterChipRow extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final ValueChanged<String> onSelected;

  const FilterChipRow({
    super.key,
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => SizedBox(width: 6),
        itemBuilder: (context, i) {
          final isSelected = filters[i] == selected;
          return GestureDetector(
            onTap: () => onSelected(filters[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border2,
                  width: 0.5,
                ),
              ),
              child: Text(
                filters[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Search Bar ───────────────────────────────────────────────────────────────

class ClaudeSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const ClaudeSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Search $hintText',
      textField: true,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            prefixIcon: Semantics(
              excludeSemantics: true,
              child: Icon(Icons.search_rounded, size: 16, color: AppColors.textTertiary),
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            filled: false,
          ),
        ),
      ),
    );
  }
}

// ─── Avatar Initials ──────────────────────────────────────────────────────────

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool large;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 24,
    this.large = false,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (name.length >= 2) return name.substring(0, 2).toUpperCase();
    return name.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: large ? AppColors.textPrimary : AppColors.accentBg,
        borderRadius: BorderRadius.circular(large ? size * 0.3 : size / 2),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            fontSize: size * (large ? 0.36 : 0.34),
            fontWeight: FontWeight.w600,
            color: large ? Colors.white : AppColors.accent,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }
}

// ─── Icon Button ──────────────────────────────────────────────────────────────

class ClaudeIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final String? semanticsLabel;

  const ClaudeIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.semanticsLabel,
  });

  @override
  State<ClaudeIconButton> createState() => _ClaudeIconButtonState();
}

class _ClaudeIconButtonState extends State<ClaudeIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel ?? widget.tooltip,
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border2, width: 0.5),
            ),
            child: Icon(widget.icon, size: 16, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

// ─── FAB ──────────────────────────────────────────────────────────────────────

class ClaudeFAB extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String? tooltip;
  final String? semanticsLabel;

  const ClaudeFAB({
    super.key,
    required this.onTap,
    this.icon = Icons.add_rounded,
    this.tooltip,
    this.semanticsLabel,
  });

  @override
  State<ClaudeFAB> createState() => _ClaudeFABState();
}

class _ClaudeFABState extends State<ClaudeFAB> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Semantics(
      label: widget.semanticsLabel ?? widget.tooltip ?? 'Action button',
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppShadows.fab(brightness),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─── Settings Row ─────────────────────────────────────────────────────────────

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: AppColors.textSecondary),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                      if (subtitle != null) ...[
                        SizedBox(height: 1),
                        Text(subtitle!, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 0, thickness: 0.5, color: AppColors.border),
      ],
    );
  }
}
