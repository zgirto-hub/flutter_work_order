import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../theme/app_theme.dart';
import 'claude_widgets.dart';

class WorkOrderCard extends StatelessWidget {
  final WorkOrder workOrder;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;

  const WorkOrderCard({
    super.key,
    required this.workOrder,
    required this.expanded,
    required this.onTap,
    required this.onEdit,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
  });

  bool get _isInspection => workOrder.type == 'Inspection';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentBg : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : (_isInspection
                    ? AppColors.inProgressText.withValues(alpha: 0.3)
                    : (expanded ? AppColors.border2 : AppColors.border)),
            width: isSelected ? 1.5 : 0.5,
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

                  // Left: checkbox or dot
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 12),
                    child: selectionMode
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => onTap(),
                              activeColor: AppColors.accent,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              side: const BorderSide(
                                  color: AppColors.border2, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                          )
                        : _isInspection
                            ? Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.inProgressText,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : _StatusDot(status: workOrder.status),
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Top row: job no + inspection badge + status badge
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
                            if (_isInspection) ...[
                              const SizedBox(width: 6),
                              _InspectionBadge(),
                            ],
                            const Spacer(),
                            StatusBadge(status: workOrder.status),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Title row with inspection icon
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isInspection) ...[
                              const Padding(
                                padding: EdgeInsets.only(top: 1, right: 6),
                                child: Icon(
                                  Icons.checklist_rounded,
                                  size: 14,
                                  color: AppColors.inProgressText,
                                ),
                              ),
                            ],
                            Expanded(
                              child: Text(
                                workOrder.Title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Location
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: AppColors.textTertiary),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                workOrder.location,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary),
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
                              ...workOrder.assignedEmployees
                                  .take(3)
                                  .map((emp) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 4),
                                        child: InitialsAvatar(
                                            name: emp.fullName, size: 22),
                                      )),
                              if (workOrder.assignedEmployees.length > 3) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '+${workOrder.assignedEmployees.length - 3}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Expand icon
                  if (!selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 8),
                      child: Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),

            // ── Expanded Section ──────────────────────────────
            if (expanded && !selectionMode) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: const BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (workOrder.description.isNotEmpty) ...[
                      Text(
                        workOrder.description,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.5),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (workOrder.assignedEmployees.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: workOrder.assignedEmployees.map((emp) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.border2, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InitialsAvatar(
                                    name: emp.fullName, size: 18),
                                const SizedBox(width: 6),
                                Text(emp.fullName,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500)),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: AppColors.border2, width: 0.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined,
                                  size: 13,
                                  color: AppColors.textSecondary),
                              SizedBox(width: 5),
                              Text('Edit',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500)),
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

// ── Inspection Badge ──────────────────────────────────────────────────────────

class _InspectionBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.inProgressBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rounded,
              size: 10, color: AppColors.inProgressText),
          SizedBox(width: 3),
          Text(
            'Inspection',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: AppColors.inProgressText,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status Dot ────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  Color get _color {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppColors.pendingText;
      case 'in progress':
        return AppColors.inProgressText;
      case 'closed':
        return AppColors.closedText;
      default:
        return AppColors.textTertiary;
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
