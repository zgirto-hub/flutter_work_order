import 'package:flutter/material.dart';
import '../models/work_order.dart';
import 'work_order_card.dart';
import 'animated_entity_list.dart';


class WorkOrderList extends StatelessWidget {
  final List<WorkOrder> orders;
  final Future<void> Function() onRefresh;
  final int? expandedIndex;
  final Function(int) onTap;
  final Function(WorkOrder) onEdit;

  const WorkOrderList({
    super.key,
    required this.orders,
    required this.onRefresh,
    required this.expandedIndex,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: Text("No Work Orders"),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AnimatedEntityList<WorkOrder>(
  items: orders,
  onRefresh: onRefresh,
  itemBuilder: (context, workOrder, index) {

    return WorkOrderCard(
      workOrder: workOrder,
      onTap: () => onTap(index),
      isExpanded: expandedIndex == index,
      onEdit: () => onEdit(workOrder),
    );

  },
)
    );
  }
}