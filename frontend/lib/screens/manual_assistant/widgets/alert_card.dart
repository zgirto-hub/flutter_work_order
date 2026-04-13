import 'package:flutter/material.dart';
import '../../../models/pattern_alert.dart';
import '../../../theme/app_theme.dart';

class AlertCard extends StatelessWidget {
  final PatternAlert alert;
  final Function(String) onStatusChange;

  const AlertCard({
    super.key,
    required this.alert,
    required this.onStatusChange,
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

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    }
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = _getSeverityColor(alert.severity);

    Color textColor;
    Color? bgColor;
    switch (alert.status) {
      case 'new':
        textColor = Colors.black87;
        bgColor = Colors.blue.shade50;
        break;
      case 'acknowledged':
        textColor = Colors.black87;
        bgColor = null;
        break;
      case 'resolved':
        textColor = Colors.grey;
        bgColor = Colors.grey.shade100;
        break;
      default:
        textColor = Colors.black87;
        bgColor = null;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    alert.severity.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(alert.status),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    alert.status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDateTime(alert.detectedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              alert.ruleName ?? 'Unknown Rule',
              style: TextStyle(
                fontWeight:
                    alert.status == 'new' ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              alert.message,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
              ),
            ),
            if (alert.equipmentId != null || alert.faultType != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (alert.equipmentId != null)
                    Chip(
                      label: Text(
                        alert.equipmentId!,
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (alert.faultType != null)
                    Chip(
                      label: Text(
                        alert.faultType!,
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            if (alert.assetContext != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Asset Context',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Location: ${alert.assetContext!['location'] ?? 'N/A'}',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textPrimary),
                    ),
                    Text(
                      'Type: ${alert.assetContext!['type'] ?? 'N/A'}',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textPrimary),
                    ),
                    if (alert.assetContext!['systems'] != null &&
                        (alert.assetContext!['systems'] as List).isNotEmpty)
                      Text(
                        'Systems: ${(alert.assetContext!['systems'] as List).map((s) => '${s['system']} [${s['role']}]').join(', ')}',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textPrimary),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'new':
        return Colors.blue;
      case 'acknowledged':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActions() {
    if (alert.status == 'new') {
      return ElevatedButton(
        onPressed: () => onStatusChange('acknowledged'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: const Text('Acknowledge'),
      );
    } else if (alert.status == 'acknowledged') {
      return ElevatedButton(
        onPressed: () => onStatusChange('resolved'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: const Text('Resolve'),
      );
    }
    return const SizedBox.shrink();
  }
}
