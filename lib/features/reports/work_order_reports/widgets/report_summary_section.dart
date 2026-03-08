import 'package:flutter/material.dart';
import 'package:work_order/models/workorder_report.dart';

class ReportSummarySection extends StatelessWidget {

  final String employeeName;
  final DateTime startDate;
  final DateTime endDate;
  final int total;
  final VoidCallback onExport;

  const ReportSummarySection({
    super.key,
    required this.employeeName,
    required this.startDate,
    required this.endDate,
    required this.total,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {

    if (total == 0) return const SizedBox();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                const Text(
                  "Report Summary",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("Export PDF"),
                  onPressed: onExport,
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text("Employee: $employeeName"),

            Text(
              "Date Range: "
              "${startDate.toString().split(' ')[0]} to "
              "${endDate.toString().split(' ')[0]}",
            ),

            const SizedBox(height: 8),

            Text(
              "Total Closed Work Orders: $total",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}