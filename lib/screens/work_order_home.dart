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
  String selectedFilter = "All";
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

  List<WorkOrder> filteredOrders = selectedFilter == "All"
      ? workOrders
      : workOrders
          .where((wo) => wo.status == selectedFilter)
          .toList();

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

    body: Column(
      children: [

        const SizedBox(height: 10),

        // ✅ FILTER BUTTONS
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                buildFilterButton("All"),
                buildFilterButton("Open"),
                buildFilterButton("In Progress"),
                buildFilterButton("Closed"),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // ✅ LIST
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredOrders.length,
            itemBuilder: (context, index) {

              final workOrder = filteredOrders[index];

              return WorkOrderCard(
                workOrder: workOrder,

                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) {
                      return WorkOrderDetailsModal(
                          workOrder: workOrder);
                    },
                  );
                },

                onEdit: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddWorkOrderScreen(workOrder: workOrder),
                    ),
                  );

                  if (result != null && result is WorkOrder) {
                    setState(() {
                      final originalIndex =
                          workOrders.indexOf(workOrder);
                      workOrders[originalIndex] = result;
                    });
                  }
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
Widget buildFilterButton(String status) {

  final isSelected = selectedFilter == status;

  return Expanded(
    child: GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = status;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Center(
          child: Text(
            status,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}
}