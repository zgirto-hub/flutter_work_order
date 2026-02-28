import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../widgets/work_order_card.dart';
import '../services/work_order_service.dart';
import 'add_work_order.dart';

class WorkOrderHome extends StatefulWidget {
  const WorkOrderHome({super.key});

  @override
  State<WorkOrderHome> createState() => _WorkOrderHomeState();
}

class _WorkOrderHomeState extends State<WorkOrderHome> {
  String selectedFilter = "All";
  int? expandedIndex;

  final WorkOrderService _service = WorkOrderService();
  List<WorkOrder> workOrders = [];

  @override
  void initState() {
    super.initState();
    loadWorkOrders();
  }

  Future<void> loadWorkOrders() async {
    final data = await _service.fetchWorkOrders();
    if (!mounted) return;

    setState(() {
      workOrders = data;
    });
  }

  Future<void> openAddScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddWorkOrderScreen(),
      ),
    );

    if (!mounted) return;

    // ✅ CREATED
    if (result is WorkOrder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Work Order created successfully"),
        ),
      );

      setState(() {
        workOrders.insert(0, result);
      });
    }

    // ✅ UPDATED
    if (result == "updated") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Work Order updated successfully"),
        ),
      );

      await loadWorkOrders();
    }

    // ✅ DELETED
    if (result == "deleted") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Work Order deleted successfully"),
        ),
      );

      await loadWorkOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = selectedFilter == "All"
        ? workOrders
        : workOrders.where((wo) => wo.status == selectedFilter).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text("Work Orders"),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(237, 221, 226, 226),
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  buildFilterButton("All"),
                  buildFilterButton("Pending"),
                  buildFilterButton("In Progress"),
                  buildFilterButton("Closed"),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ✅ LIST
          Expanded(
            child: RefreshIndicator(
              onRefresh: loadWorkOrders,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: filteredOrders.isEmpty
                    ? ListView(
                        key: const ValueKey("empty"),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 150),
                          Center(child: Text("No Work Orders")),
                        ],
                      )
                    : ListView.builder(
                        key: ValueKey(selectedFilter),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredOrders.length,
                        itemBuilder: (context, index) {
                          final workOrder = filteredOrders[index];

                          return TweenAnimationBuilder<double>(
                            key: ValueKey(workOrder.id),
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 20 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: WorkOrderCard(
                              workOrder: workOrder,
                              onTap: () {
                                setState(() {
                                  expandedIndex =
                                      expandedIndex == index ? null : index;
                                });
                              },
                              isExpanded: expandedIndex == index,
                              onEdit: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AddWorkOrderScreen(
                                      workOrder: workOrder,
                                    ),
                                  ),
                                );

                                if (!mounted) return;

                                if (result == "updated") {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "Work Order updated successfully"),
                                    ),
                                  );

                                  await loadWorkOrders();
                                }

                                if (result == "deleted") {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "Work Order deleted successfully"),
                                    ),
                                  );

                                  await loadWorkOrders();
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFilterButton(String status) {
    final theme = Theme.of(context);
    final isSelected = selectedFilter == status;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedFilter = status;
            expandedIndex = null;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Center(
            child: Text(
              status,
              style: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
