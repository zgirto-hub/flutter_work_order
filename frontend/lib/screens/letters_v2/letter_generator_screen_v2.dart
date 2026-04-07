import 'package:flutter/material.dart';
import '../../models/generated_letter.dart';
import '../../theme/app_theme.dart';
import 'letter_form_tab_v2.dart';
import 'letter_history_tab_v2.dart';

class LetterGeneratorScreenV2 extends StatefulWidget {
  const LetterGeneratorScreenV2({super.key});

  @override
  State<LetterGeneratorScreenV2> createState() =>
      _LetterGeneratorScreenV2State();
}

class _LetterGeneratorScreenV2State extends State<LetterGeneratorScreenV2> {
  int _tabIndex = 0;
  Key _historyKey = UniqueKey();
  GeneratedLetter? _editLetter;

  void _onLetterSaved() {
    setState(() {
      _tabIndex = 1;
      _editLetter = null;
      _historyKey = UniqueKey();
    });
  }

  void _onEditLetter(GeneratedLetter letter) {
    setState(() {
      _editLetter = letter;
      _tabIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (matches More screen) ──
              Container(
                color: AppColors.bgSurface,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: AppColors.border2, width: 0.5),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          size: 17,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create Official Letter',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 0, thickness: 0.5, color: AppColors.border),

              // ── iOS-style segmented tabs ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SegmentedTabs(
                  tabs: const ['New Letter', 'History'],
                  selectedIndex: _tabIndex,
                  onChanged: (i) => setState(() => _tabIndex = i),
                ),
              ),

              // ── Tab body ──
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: _tabIndex == 0
                          ? LetterFormTabV2(
                              key: ValueKey(_editLetter?.id),
                              onLetterSaved: _onLetterSaved,
                              editLetter: _editLetter,
                            )
                          : LetterHistoryTabV2(
                              key: _historyKey,
                              onEditLetter: _onEditLetter,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS-style segmented control (pill-shaped tabs)
class _SegmentedTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SegmentedTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: active ? AppColors.bgSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

