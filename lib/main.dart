import 'package:flutter/material.dart';

void main() {
  runApp(const WorkOrderApp());
}

class WorkOrderApp extends StatelessWidget {
  const WorkOrderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WorkOrderHome(),
    );
  }
}

class WorkOrder {
  final String jobNo;
  final String client;
  final String status;
  final String description;

  WorkOrder({
    required this.jobNo,
    required this.client,
    required this.status,
    required this.description,
  });
}

class WorkOrderHome extends StatefulWidget {
  const WorkOrderHome({super.key});

  @override
  State<WorkOrderHome> createState() => _WorkOrderHomeState();
}

class _WorkOrderHomeState extends State<WorkOrderHome> {
  List<WorkOrder> workOrders = [
    WorkOrder(
      jobNo: "WO-1001",
      client: "Kuwait Airport",
      status: "Open",
      description: "Runway lighting inspection",
    ),
    WorkOrder(
      jobNo: "WO-1002",
      client: "NBK HQ",
      status: "In Progress",
      description: "Server room maintenance",
    ),
  ];

  void addWorkOrder() {
    setState(() {
      workOrders.add(
        WorkOrder(
          jobNo: "WO-${1000 + workOrders.length + 1}",
          client: "New Client",
          status: "Open",
          description: "New job description",
        ),
      );
    });
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
        actions: const [
          Icon(Icons.search),
          SizedBox(width: 15),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addWorkOrder,
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: workOrders.length,
        itemBuilder: (context, index) {
          final workOrder = workOrders[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkOrderDetails(workOrder: workOrder),
                ),
              );
            },
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
                  Text(
                    workOrder.jobNo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    workOrder.client,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    workOrder.status,
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class WorkOrderDetails extends StatelessWidget {
  final WorkOrder workOrder;

  const WorkOrderDetails({super.key, required this.workOrder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(workOrder.jobNo),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Client: ${workOrder.client}",
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            Text("Status: ${workOrder.status}",
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            Text("Description:",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(workOrder.description,
                style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}