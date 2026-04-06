import 'package:flutter/material.dart';
import '../../models/generated_letter.dart';
import '../../theme/app_theme.dart';
import 'letter_form_tab.dart';
import 'letter_history_tab.dart';

class LetterGeneratorScreen extends StatefulWidget {
  const LetterGeneratorScreen({super.key});

  @override
  State<LetterGeneratorScreen> createState() => _LetterGeneratorScreenState();
}

class _LetterGeneratorScreenState extends State<LetterGeneratorScreen> {
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
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إنشاء خطاب رسمي',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: AppColors.bgSurface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
              ),
              child: Row(
                children: [
                  _Tab(
                    label: 'خطاب جديد',
                    active: _tabIndex == 0,
                    onTap: () => setState(() => _tabIndex = 0),
                  ),
                  const SizedBox(width: 16),
                  _Tab(
                    label: 'السجل',
                    active: _tabIndex == 1,
                    onTap: () => setState(() => _tabIndex = 1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tabIndex == 0
                  ? LetterFormTab(
                      key: ValueKey(_editLetter?.id),
                      onLetterSaved: _onLetterSaved,
                      editLetter: _editLetter,
                    )
                  : LetterHistoryTab(
                      key: _historyKey,
                      onEditLetter: _onEditLetter,
                    ),
            ),
          ],
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
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
