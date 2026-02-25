import 'package:flutter/material.dart';
import '../models/work_order.dart';

class WorkOrderCard extends StatelessWidget {
  final WorkOrder workOrder;
 final VoidCallback onEdit;
 final VoidCallback onTap;

  const WorkOrderCard({
  super.key,
  required this.workOrder,
  required this.onTap,
  required this.onEdit,
});

  Color getStatusColor(String status) {
    switch (status) {
      case "Open":
        return Colors.redAccent;
      case "In Progress":
        return Colors.orangeAccent;
      case "Closed":
        return Colors.greenAccent;
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF37474F), Color(0xFF263238)],
          ),
        ),
       child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          workOrder.jobNo,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.white),
          onPressed: onEdit,
        ),
      ],
    ),
    const SizedBox(height: 10),
    Text(
      workOrder.client,
      style: const TextStyle(color: Colors.white70),
    ),
    const SizedBox(height: 10),
    Text(
      workOrder.status,
      style: TextStyle(
        color: getStatusColor(workOrder.status),
        fontWeight: FontWeight.bold,
      ),
    ),
  ],
),
      ),
    );
  }
}