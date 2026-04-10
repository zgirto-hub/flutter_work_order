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
              Container(
                color: AppColors.bgSurface,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    Row(
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
                              Icons.arrow_back_rounded,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Create Official Letter',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _Tab(
                          label: 'New Letter',
                          active: _tabIndex == 0,
                          onTap: () => setState(() => _tabIndex = 0),
                        ),
                        _Tab(
                          label: 'History',
                          active: _tabIndex == 1,
                          onTap: () => setState(() => _tabIndex = 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 0, thickness: 0.5, color: AppColors.border),
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

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        margin: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
