import 'package:flutter/material.dart';
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

  void _onLetterSaved() {
    setState(() {
      _tabIndex = 1;
      _historyKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إنشاء خطاب رسمي'),
          centerTitle: true,
        ),
        body: Column(
          children: [
            // Tab bar
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  _Tab(
                    label: 'خطاب جديد',
                    icon: Icons.edit_document,
                    active: _tabIndex == 0,
                    onTap: () => setState(() => _tabIndex = 0),
                  ),
                  _Tab(
                    label: 'السجل',
                    icon: Icons.history,
                    active: _tabIndex == 1,
                    onTap: () => setState(() => _tabIndex = 1),
                  ),
                ],
              ),
            ),
            // Tab body
            Expanded(
              child: _tabIndex == 0
                  ? LetterFormTabV2(onLetterSaved: _onLetterSaved)
                  : LetterHistoryTabV2(key: _historyKey),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade600;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
