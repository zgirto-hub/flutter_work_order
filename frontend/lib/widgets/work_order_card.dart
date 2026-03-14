import 'package:flutter/material.dart';
import '../models/work_order.dart';

class WorkOrderCard extends StatelessWidget {
  final WorkOrder workOrder;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const WorkOrderCard({
    super.key,
    required this.workOrder,
    required this.expanded,
    required this.onTap,
    required this.onEdit,
  });

  Color statusColor(String status) {
    switch (status) {
      case "Pending":
        return Colors.orange;
      case "In Progress":
        return Colors.blue;
      case "Closed":
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(workOrder.status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black.withOpacity(0.04),
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          children: [

            /// MAIN ROW
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  /// STATUS COLOR BAR
                  Container(
                    width: 6,
                    height: 50,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),

                  const SizedBox(width: 12),

                  /// CONTENT
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        /// JOB NUMBER + STATUS
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                workOrder.jobNo,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            Text(
                              workOrder.status,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        /// TITLE
                        Text(
                          workOrder.Title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 4),

                        /// DESCRIPTION
                        Text(
                          workOrder.description ?? "",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  /// EXPAND ICON
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  )
                ],
              ),
            ),

            /// EXPANDED SECTION
            if (expanded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    /// EMPLOYEES
                    if (workOrder.assignedEmployees.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: workOrder.assignedEmployees.map((emp) {
                          return Chip(
                            label: Text(emp.fullName),
                            avatar: const CircleAvatar(
                              radius: 10,
                              child: Icon(Icons.person, size: 12),
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 10),

                    /// ACTION BUTTON
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit),
                        label: const Text("Edit"),
                      ),
                    )
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }
}