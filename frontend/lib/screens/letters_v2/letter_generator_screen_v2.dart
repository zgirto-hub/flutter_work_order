import 'package:flutter/material.dart';
import '../../models/generated_letter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import 'letter_form_tab_v2.dart';
import 'letter_history_tab_v2.dart';

class LetterGeneratorScreenV2 extends StatefulWidget {
  const LetterGeneratorScreenV2({super.key});

  @override
  State<LetterGeneratorScreenV2> createState() =>
      _LetterGeneratorScreenV2State();
}

class _LetterGeneratorScreenV2State extends State<LetterGeneratorScreenV2> {
  Key _historyKey = UniqueKey();

  void _onLetterSaved() {
    setState(() {
      _historyKey = UniqueKey();
    });
  }

  void _openForm({GeneratedLetter? letter}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LetterFormScreen(
          editLetter: letter,
          onLetterSaved: _onLetterSaved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        floatingActionButton: ClaudeFAB(
          onTap: () => _openForm(),
          tooltip: 'Create new letter',
          semanticsLabel: 'Create new letter',
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: AppColors.bgSurface,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    if (Navigator.canPop(context)) ...[
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
                    ],
                    Expanded(
                      child: Text(
                        'Official Letters',
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
              ),
              Divider(height: 0, thickness: 0.5, color: AppColors.border),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: LetterHistoryTabV2(
                      key: _historyKey,
                      onEditLetter: (letter) => _openForm(letter: letter),
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

/// Separate screen for creating/editing a letter (pushed via Navigator).
class _LetterFormScreen extends StatelessWidget {
  final GeneratedLetter? editLetter;
  final VoidCallback onLetterSaved;

  const _LetterFormScreen({
    this.editLetter,
    required this.onLetterSaved,
  });

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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        onLetterSaved();
                        Navigator.of(context).maybePop();
                      },
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
                        editLetter != null
                            ? 'Edit Letter'
                            : 'Create Official Letter',
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
              ),
              Divider(height: 0, thickness: 0.5, color: AppColors.border),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: LetterFormTabV2(
                      key: ValueKey(editLetter?.id),
                      onLetterSaved: () {
                        onLetterSaved();
                        Navigator.of(context).maybePop();
                      },
                      editLetter: editLetter,
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
