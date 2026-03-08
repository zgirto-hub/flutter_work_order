import 'package:flutter/material.dart';
import '../../../../models/workorder_report.dart';
//import 'package:work_order/models/workorder_report.dart';

class ReportTableSection extends StatefulWidget {
  final List<WorkOrderReport> results;

  const ReportTableSection({
    super.key,
    required this.results,
  });

  @override
  State<ReportTableSection> createState() => _ReportTableSectionState();
}

class _ReportTableSectionState extends State<ReportTableSection> {
  final Set<int> expandedRows = {};

  @override
  Widget build(BuildContext context) {

    if (widget.results.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.assignment_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 10),
          Text("No work orders found"),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: IntrinsicWidth(
          child: DataTable(
            columnSpacing: 30,
            headingRowHeight: 42,
            columns: const [
              DataColumn(label: Text("Title")),
              DataColumn(label: Text("Location")),
              DataColumn(label: Text("Closed")),
            ],
            rows: widget.results.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              return DataRow(
                cells: [

                  /// Title (expandable)
                  DataCell(
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (expandedRows.contains(index)) {
                            expandedRows.remove(index);
                          } else {
                            expandedRows.add(index);
                          }
                        });
                      },
                      child: SizedBox(
                        width: 260,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          alignment: Alignment.topLeft,
                          child: Text(
                            item.title,
                            maxLines:
                                expandedRows.contains(index) ? null : 1,
                            overflow: expandedRows.contains(index)
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),

                  /// Location
                  DataCell(
                    SizedBox(
                      width: 140,
                      child: Text(item.location),
                    ),
                  ),

                  /// Closed date
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(
                        item.modifiedDate.toString().split(" ")[0],
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}