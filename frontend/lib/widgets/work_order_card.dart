import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../theme/app_theme.dart';
import 'claude_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: expanded ? AppColors.border2 : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [

            // ── Main Row ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Left accent dot
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 12),
                    child: _StatusDot(status: workOrder.status),
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Top row: job no + badge
                        Row(
                          children: [
                            Text(
                              workOrder.jobNo,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textTertiary,
                                letterSpacing: 0.03,
                              ),
                            ),
                            const Spacer(),
                            StatusBadge(status: workOrder.status),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Title
                        Text(
                          workOrder.Title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 5),

                        // Meta: location
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textTertiary),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                workOrder.location,
                                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // Employees
                        if (workOrder.assignedEmployees.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ...workOrder.assignedEmployees.take(3).map(
                                (emp) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: InitialsAvatar(name: emp.fullName, size: 22),
                                ),
                              ),
                              if (workOrder.assignedEmployees.length > 3) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '+${workOrder.assignedEmployees.length - 3}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Expand icon
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 8),
                    child: Icon(
                      expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Expanded Section ──────────────────────────────
            if (expanded) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: const BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    if (workOrder.description.isNotEmpty) ...[
                      Text(
                        workOrder.description,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (workOrder.assignedEmployees.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: workOrder.assignedEmployees.map((emp) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border2, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InitialsAvatar(name: emp.fullName, size: 18),
                                const SizedBox(width: 6),
                                Text(emp.fullName, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],

                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.border2, width: 0.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined, size: 13, color: AppColors.textSecondary),
                              SizedBox(width: 5),
                              Text('Edit', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  Color get _color {
    switch (status.toLowerCase()) {
      case 'pending': return AppColors.pendingText;
      case 'in progress': return AppColors.inProgressText;
      case 'closed': return AppColors.closedText;
      default: return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
    );
  }
}
