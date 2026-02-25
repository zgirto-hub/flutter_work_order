import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../widgets/work_order_card.dart';
import 'work_order_details.dart';
import 'add_work_order.dart';

class WorkOrderHome extends StatefulWidget {
  const WorkOrderHome({super.key});

  @override
  State<WorkOrderHome> createState() => _WorkOrderHomeState();
}

class _WorkOrderHomeState extends State<WorkOrderHome> {
  final List<WorkOrder> workOrders = [
    const WorkOrder(
      jobNo: "WO-1001",
      client: "Kuwait Airport",
      status: "Open",
      description: "Runway lighting inspection",
    ),
    const WorkOrder(
      jobNo: "WO-1002",
      client: "NBK HQ",
      status: "In Progress",
      description: "Server room maintenance",
    ),
  ];

  void openAddScreen() async {
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AddWorkOrderScreen(),
    ),
  );

  if (result != null && result is WorkOrder) {
    setState(() {
      workOrders.add(result);
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("Work Orders"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
           onPressed: openAddScreen,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: workOrders.length,
        itemBuilder: (context, index) {
          final workOrder = workOrders[index];

          return WorkOrderCard(
            workOrder: workOrder,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      WorkOrderDetails(workOrder: workOrder),
                ),
              );
            },
          );
        },
      ),
    );
  }
}