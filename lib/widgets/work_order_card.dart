//new theme
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/work_order.dart';

class WorkOrderCard extends StatelessWidget {
  final WorkOrder workOrder;
  final VoidCallback onEdit;
  final VoidCallback onTap;
  final bool isExpanded;

  const WorkOrderCard({
    super.key,
    required this.workOrder,
    required this.isExpanded,
    required this.onTap,
    required this.onEdit,
  });

  Color getStatusColor(BuildContext context, String status) {
    final primary = Theme.of(context).colorScheme.primary;

    switch (status) {
      case "Pending":
        return primary;
      case "In Progress":
        return Colors.orange;
      case "Closed":
        return Colors.green;
      default:
        return primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primary.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: isExpanded ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔹 TOP ROW
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    workOrder.jobNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      color: primary,
                      onPressed: onEdit,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 6),

            /// 🔹 Title
            Text(
              workOrder.Title,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF6B7280),
              ),
            ),

// 🔹 DESCRIPTION PREVIEW (only when collapsed)
            if (!isExpanded) ...[
              const SizedBox(height: 6),
              Text(
                workOrder.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],

            const SizedBox(height: 8),
            // 🔹 ASSIGNED COUNT (collapsed only)
            if (!isExpanded && workOrder.assignedEmployees.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B5563).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 14,
                          color: Color(0xFF4B5563),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${workOrder.assignedEmployees.length} Assigned",
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4B5563),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),

            /// 🔹 STATUS BADGE
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: getStatusColor(context, workOrder.status)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        workOrder.status == "Closed"
                            ? Icons.check_circle
                            : workOrder.status == "In Progress"
                                ? Icons.autorenew
                                : Icons.schedule,
                        size: 16,
                        color: getStatusColor(context, workOrder.status),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        workOrder.status,
                        style: TextStyle(
                          color: getStatusColor(context, workOrder.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            /// 🔹 EXPANDABLE SECTION
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  Text(
                    "Description",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    workOrder.description,
                    style: const TextStyle(
                      fontSize: 16, // 🔥 Bigger text
                      height: 1.4, // Better spacing
                      color: Color(0xFF374151), // Slightly darker
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 🔹 ASSIGNED EMPLOYEES (expanded only)
                  if (workOrder.assignedEmployees.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      "Assigned To",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: workOrder.assignedEmployees.map((emp) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            "• ${emp.fullName}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF374151),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  Text(
                    "Created: ${workOrder.dateCreated}",
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  Text(
                    "Modified: ${workOrder.dateModified}",
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
