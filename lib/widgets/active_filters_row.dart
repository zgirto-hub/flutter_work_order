import 'package:flutter/material.dart';

class ActiveFiltersRow extends StatelessWidget {
  final List<Widget> chips;

  const ActiveFiltersRow({
    super.key,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) {
      return const SizedBox();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: chips,
      ),
    );
  }
}