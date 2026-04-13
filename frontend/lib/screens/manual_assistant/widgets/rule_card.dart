import 'package:flutter/material.dart';
import '../../../models/pattern_rule.dart';

class RuleCard extends StatelessWidget {
  final PatternRule rule;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const RuleCard({
    super.key,
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getDetectionTypeLabel(String detectionType) {
    switch (detectionType) {
      case 'recurring_fault':
        return 'Recurring Fault';
      case 'technician_recurring':
        return 'Technician Recurring';
      case 'procedure_deviation':
        return 'Procedure Deviation';
      case 'seasonal_pattern':
        return 'Seasonal Pattern';
      case 'long_resolution':
        return 'Long Resolution';
      case 'parts_replaced_recurrence':
        return 'Parts Recurrence';
      default:
        return detectionType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = _getSeverityColor(rule.severity);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    rule.severity.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (rule.description != null && rule.description!.isNotEmpty)
              Text(
                rule.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text(
                    _getDetectionTypeLabel(rule.detectionType),
                    style: const TextStyle(fontSize: 10),
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                if (rule.isBuiltIn)
                  const Chip(
                    label: Text(
                      'Built-in',
                      style: TextStyle(fontSize: 10),
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                const Spacer(),
                Switch(
                  value: rule.enabled,
                  onChanged: (_) => onToggle(),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
