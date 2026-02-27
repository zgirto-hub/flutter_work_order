/*import 'package:flutter/material.dart';
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

  Color getStatusColor(String status) {
    switch (status) {
      case "Open":
        return const Color.fromARGB(255, 143, 128, 82);
      case "In Progress":
        return const Color.fromARGB(255, 110, 94, 231);
      case "Closed":
        return const Color.fromARGB(255, 60, 103, 82);
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 16),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            //Gold Color
            //
            /*  colors: [
              Color.fromARGB(255, 215, 213, 162),
              Color.fromARGB(235, 177, 167, 105),
            ],*/

            colors: [Color(0xFFF8F3D4), Color(0xFFE8DFA7)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: isExpanded ? 12 : 6,
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
                      color: Color(0xFF3E2F1C),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Color(0xFF2D2215),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color(0xFF2D2215)),
                      onPressed: onEdit,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 6),

            Text(
              workOrder.client,
              style: const TextStyle(color: Color.fromARGB(179, 58, 32, 10)),
            ),

            const SizedBox(height: 6),

            Text(
              workOrder.status,
              style: TextStyle(
                color: getStatusColor(workOrder.status),
                fontWeight: FontWeight.bold,
              ),
            ),

            /// 🔹 EXPANDABLE SECTION
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white54, height: 25),
                  Text(
                    "Description: ${workOrder.description}",
                    style: const TextStyle(
                      color: Color.fromARGB(179, 58, 32, 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Created: ${workOrder.dateCreated}",
                    style: const TextStyle(
                      color: Color.fromARGB(179, 58, 32, 10),
                    ),
                  ),
                  Text(
                    "Modified: ${workOrder.dateModified}",
                    style: const TextStyle(
                      color: Color.fromARGB(179, 58, 32, 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}*/

//new theme

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
      case "Open":
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
                      fontSize: 18,
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

            /// 🔹 CLIENT
            Text(
              workOrder.Title,
              style: const TextStyle(
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

            const SizedBox(height: 10),

            /// 🔹 STATUS BADGE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:
                    getStatusColor(context, workOrder.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                workOrder.status,
                style: TextStyle(
                  color: getStatusColor(context, workOrder.status),
                  fontWeight: FontWeight.w600,
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
