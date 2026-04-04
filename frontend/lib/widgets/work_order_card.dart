import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../theme/app_theme.dart';
import 'claude_widgets.dart';

class WorkOrderCard extends StatefulWidget {
  final WorkOrder workOrder;
  final bool expanded;
  final int unreadActivityCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onActivity;
  final VoidCallback? onStatusTap;
  final VoidCallback? onExportPdf;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final String? signatureState;
  final int approvalLevel;
  final List<String> userDepartmentIds;

  const WorkOrderCard({
    super.key,
    required this.workOrder,
    required this.expanded,
    this.unreadActivityCount = 0,
    required this.onTap,
    required this.onEdit,
    this.onActivity,
    this.onStatusTap,
    this.onExportPdf,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.signatureState,
    this.approvalLevel = 0,
    this.userDepartmentIds = const [],
  });

  @override
  State<WorkOrderCard> createState() => _WorkOrderCardState();
}

class _WorkOrderCardState extends State<WorkOrderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.expanded ? 1.0 : 0.0,
  );

  late final Animation<double> _size =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<double> _chevron =
      Tween<double>(begin: 0.0, end: 0.5).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic),
  );

  @override
  void didUpdateWidget(WorkOrderCard old) {
    super.didUpdateWidget(old);
    if (old.expanded != widget.expanded) {
      widget.expanded ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isInspection => widget.workOrder.type == 'Inspection';

  @override
  Widget build(BuildContext context) {
    final canTapStatus = widget.onStatusTap != null &&
        !widget.selectionMode &&
        widget.workOrder.status.toLowerCase() != 'closed';

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: widget.isSelected ? AppColors.accentBg : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isSelected
                ? AppColors.accent
                : (_isInspection
                    ? AppColors.inProgressText.withValues(alpha: 0.3)
                    : (widget.expanded ? AppColors.border2 : AppColors.border)),
            width: widget.isSelected ? 1.5 : 0.5,
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
                    child: widget.selectionMode
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(
                              value: widget.isSelected,
                              onChanged: (_) => widget.onTap(),
                              activeColor: AppColors.accent,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(
                                  color: AppColors.border2, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                          )
                        : _isInspection
                            ? Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: AppColors.inProgressText,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : _StatusDot(status: widget.workOrder.status),
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: job no + inspection badge + status badge
                        Row(
                          children: [
                            Text(
                              widget.workOrder.jobNo,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textTertiary,
                                letterSpacing: 0.03,
                              ),
                            ),
                            if (_isInspection) ...[
                              SizedBox(width: 6),
                              _InspectionBadge(),
                            ],
                            if (widget.unreadActivityCount > 0) ...[
                              SizedBox(width: 6),
                              _UnreadBadge(count: widget.unreadActivityCount),
                            ],
                            if (widget.signatureState != null) ...[
                              SizedBox(width: 6),
                              _SignatureBadge(
                                state: widget.signatureState!,
                                approvalLevel: widget.approvalLevel,
                                userDepartmentIds: widget.userDepartmentIds,
                                woDepartmentId: widget.workOrder.departmentId,
                              ),
                            ],
                            const Spacer(),
                            canTapStatus
                                ? _StatusTapTarget(
                                    onTap: widget.onStatusTap!,
                                    child: StatusBadge(
                                      status: widget.workOrder.status,
                                    ),
                                  )
                                : StatusBadge(status: widget.workOrder.status),
                          ],
                        ),

                        SizedBox(height: 5),

                        // Title row with inspection icon
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isInspection) ...[
                              Padding(
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
                                widget.workOrder.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Description (if present)
                        if (widget.workOrder.description.isNotEmpty) ...[
                          SizedBox(height: 3),
                          Text(
                            widget.workOrder.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        SizedBox(height: 5),

                        // Location
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 12, color: AppColors.textTertiary),
                            SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                widget.workOrder.location,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // Employees
                        if (widget.workOrder.assignedTechnician != null) ...[
                          SizedBox(height: 8),
                          Row(
                            children: [
                              InitialsAvatar(
                                  name: widget
                                      .workOrder.assignedTechnician!.fullName,
                                  size: 22),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Chevron — rotates 0° (down) → 180° (up)
                  if (!widget.selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 8),
                      child: AnimatedBuilder(
                        animation: _chevron,
                        builder: (_, child) => Transform.rotate(
                          angle: _chevron.value * 3.14159265,
                          child: child,
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Expanded Section — animated ───────────────────
            if (!widget.selectionMode)
              SizeTransition(
                sizeFactor: _size,
                axisAlignment: -1,
                child: FadeTransition(
                  opacity: _fade,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(14)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.workOrder.description.isNotEmpty) ...[
                          Text(
                            widget.workOrder.description,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.5),
                          ),
                          SizedBox(height: 10),
                        ],
                        if (widget.workOrder.assignedTechnician != null) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [widget.workOrder.assignedTechnician]
                                .map((emp) {
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
                                        name: emp!.fullName, size: 18),
                                    SizedBox(width: 6),
                                    Text(emp.fullName,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          SizedBox(height: 10),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.onExportPdf != null &&
                                widget.workOrder.status.toLowerCase() ==
                                    'closed')
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Semantics(
                                  label: 'Export PDF report',
                                  button: true,
                                  child: GestureDetector(
                                    onTap: widget.onExportPdf,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: AppColors.bgSurface,
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(
                                            color: AppColors.border2,
                                            width: 0.5),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.picture_as_pdf_outlined,
                                              size: 13,
                                              color: AppColors.textSecondary),
                                          SizedBox(width: 5),
                                          Text('PDF',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.onActivity != null)
                              Semantics(
                                label: 'View activity for work order',
                                button: true,
                                child: GestureDetector(
                                  onTap: widget.onActivity,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppColors.bgSurface,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                          color: AppColors.border2, width: 0.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.history_rounded,
                                            size: 13,
                                            color: AppColors.textSecondary),
                                        SizedBox(width: 5),
                                        Text('Activity',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.w500)),
                                        if (widget.unreadActivityCount > 0) ...[
                                          SizedBox(width: 6),
                                          _UnreadBadge(
                                              count:
                                                  widget.unreadActivityCount),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.onActivity != null) SizedBox(width: 8),
                            Semantics(
                              label: 'Edit work order',
                              button: true,
                              child: GestureDetector(
                                onTap: widget.onEdit,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.bgSurface,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                        color: AppColors.border2, width: 0.5),
                                  ),
                                  child: Row(
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
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Signature Badge ──────────────────────────────────────────────────────────

class _SignatureBadge extends StatelessWidget {
  final String state;
  final int approvalLevel;
  final List<String> userDepartmentIds;
  final String woDepartmentId;

  const _SignatureBadge({
    required this.state,
    required this.approvalLevel,
    required this.userDepartmentIds,
    required this.woDepartmentId,
  });

  @override
  Widget build(BuildContext context) {
    if (approvalLevel == 0) return SizedBox.shrink();

    final bool isInUserDept = userDepartmentIds.contains(woDepartmentId);

    if (state == 'fully_signed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.closedText.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: AppColors.closedText),
            SizedBox(width: 3),
            Text('Completed',
                style: TextStyle(
                    fontSize: 10,
                    color: AppColors.closedText,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    if (approvalLevel == 1 && state == 'pending_supervisor' && isInUserDept) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.pendingText.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pending, size: 12, color: AppColors.pendingText),
            SizedBox(width: 3),
            Text('Pending',
                style: TextStyle(
                    fontSize: 10,
                    color: AppColors.pendingText,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    if (approvalLevel == 2 && state == 'pending_superintendent') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.pendingText.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pending, size: 12, color: AppColors.pendingText),
            SizedBox(width: 3),
            Text('Pending',
                style: TextStyle(
                    fontSize: 10,
                    color: AppColors.pendingText,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return SizedBox.shrink();
  }
}

class _InspectionBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.inProgressBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
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

/// Tappable status badge wrapper. Uses [HitTestBehavior.opaque] so the
/// inner tap wins the gesture arena over the outer card GestureDetector.
/// Adds a small chevron icon as a visual affordance.
class _StatusTapTarget extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _StatusTapTarget({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(width: 2),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

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
