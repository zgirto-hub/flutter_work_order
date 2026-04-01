import 'package:flutter/material.dart';
import '../models/nav_screen.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class NavBarCustomizationSheet extends StatefulWidget {
  final ThemeController themeController;
  final String userRole;
  final List<String>? allowedScreens;

  const NavBarCustomizationSheet({
    super.key,
    required this.themeController,
    required this.userRole,
    this.allowedScreens,
  });

  @override
  State<NavBarCustomizationSheet> createState() =>
      _NavBarCustomizationSheetState();
}

class _NavBarCustomizationSheetState extends State<NavBarCustomizationSheet> {
  late List<String> _pinned;

  static const int _maxPinned = 2;

  @override
  void initState() {
    super.initState();
    _pinned = List.of(widget.themeController.pinnedNavScreens);
  }

  bool _canShow(String key) {
    if (widget.userRole == 'admin') return true;
    if (widget.allowedScreens == null) return true;
    return widget.allowedScreens!.contains(key);
  }

  void _toggle(String key) {
    setState(() {
      if (_pinned.contains(key)) {
        _pinned.remove(key);
      } else if (_pinned.length < _maxPinned) {
        _pinned.add(key);
      }
    });
    widget.themeController.setPinnedNavScreens(_pinned);
  }

  void _reset() {
    setState(() => _pinned.clear());
    widget.themeController.setPinnedNavScreens(_pinned);
  }

  @override
  Widget build(BuildContext context) {
    final available =
        NavScreenRegistry.all.where((s) => _canShow(s.key)).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Navigation Bar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pin up to $_maxPinned screens for quick access',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_pinned.isNotEmpty)
                GestureDetector(
                  onTap: _reset,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border2, width: 0.5),
                    ),
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Screen list
          ...available.map((screen) {
            final isPinned = _pinned.contains(screen.key);
            final isFull = _pinned.length >= _maxPinned && !isPinned;

            return GestureDetector(
              onTap: isFull ? null : () => _toggle(screen.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isPinned
                      ? AppColors.accentBg
                      : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPinned ? AppColors.accent : AppColors.border,
                    width: isPinned ? 1 : 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: screen.bgColor,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child:
                          Icon(screen.icon, size: 17, color: screen.color),
                    ),
                    const SizedBox(width: 12),
                    // Title & subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            screen.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isFull
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            screen.subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Toggle indicator
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isPinned
                            ? AppColors.accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isPinned
                              ? AppColors.accent
                              : isFull
                                  ? AppColors.border
                                  : AppColors.border2,
                          width: 1.5,
                        ),
                      ),
                      child: isPinned
                          ? const Icon(Icons.push_pin_rounded,
                              size: 13, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
