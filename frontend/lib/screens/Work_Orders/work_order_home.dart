import 'package:flutter/material.dart';
import '../../models/work_order.dart';
import '../../widgets/work_order_card.dart';
import '../../services/work_order_service.dart';
import 'add_work_order.dart';
import '../../models/employee_assignment.dart';
import '../../widgets/active_filters_row.dart';
import '../../widgets/search_appbar.dart';
import '../../widgets/status_filter_bar.dart';
import '../../controllers/filter_controller.dart';
import '../../filters/work_order_filter_engine.dart';
import '../../widgets/work_order_list.dart';


class WorkOrderHome extends StatefulWidget {
  const WorkOrderHome({super.key});

  @override
  State<WorkOrderHome> createState() => _WorkOrderHomeState();
}

class _WorkOrderHomeState extends State<WorkOrderHome> {

  bool _isSearching = false;
 
  
  final TextEditingController _searchController = TextEditingController();
 
  int? expandedIndex;

  
  final FilterController filterController = FilterController();
  final WorkOrderService _service = WorkOrderService();


  List<WorkOrder> workOrders = [];

  @override
  void initState() {
    super.initState();
    loadWorkOrders();
  }
  Widget buildActiveFiltersRow() {
  final List<Widget> chips = [];

  if (filterController.searchQuery.isNotEmpty) {
    chips.add(
      FilterChip(
        label: Text("🔍 ${filterController.searchQuery}"),
        onSelected: (_) {
          setState(() {
            _searchController.clear();
           filterController.setSearchQuery("");
          });
        },
      ),
    );
  }

  if (filterController.selectedDate != null) {
    chips.add(
      FilterChip(
        label: Text(
          "📅 ${filterController.selectedDate!.day}/${filterController.selectedDate!.month}/${filterController.selectedDate!.year}",
        ),
        onSelected: (_) {
          setState(() {
            filterController.selectedDate = null;
          });
        },
      ),
    );
  }

  if (filterController.selectedEmployeeId != null) {
    final employeeName = workOrders
        .expand((wo) => wo.assignedEmployees)
        .firstWhere(
          (emp) => emp.id == filterController.selectedEmployeeId,
          orElse: () =>  EmployeeAssignment(id: '', fullName: ''),
        )
        .fullName;

    chips.add(
      FilterChip(
        label: Text("👤 $employeeName"),
        onSelected: (_) {
          setState(() {
            filterController.selectedEmployeeId = null;
          });
        },
      ),
    );
  }

  if (chips.isEmpty) return const SizedBox();

  chips.add(
    TextButton(
      onPressed: () {
        setState(() {
          filterController.searchQuery = "";
          _searchController.clear();
          filterController.selectedDate = null;
          filterController.selectedEmployeeId = null;
       //   filterController.selectedEmployeeId = "All";
        });
      },
      child: const Text("Clear All"),
    ),
  );

return ActiveFiltersRow(chips: chips);
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
  final filteredOrders =
    WorkOrderFilterEngine.applyFilters(
        workOrders,
        filterController);


    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color.fromARGB(237, 221, 226, 226),
        foregroundColor: Colors.black,
        elevation: 0,
        title: _isSearching
    ? SearchAppBar(
  controller: _searchController,
  hintText: "Search job no, title or description...",
  onChanged: (value) {
    filterController.setSearchQuery(value.toLowerCase());

    setState(() {});
  },
)

            : const Text("Work Orders"),
        actions: [

  // 🔍 SEARCH BUTTON
  IconButton(
    icon: Icon(_isSearching ? Icons.close : Icons.search),
    onPressed: () {
      setState(() {
        _isSearching = !_isSearching;
        if (!_isSearching) {
          _searchController.clear();
          filterController.searchQuery = "";
        }
      });
    },
  ),

  // 📅 DATE FILTER BUTTON
  IconButton(
    icon: Icon(
      filterController.selectedDate == null
          ? Icons.calendar_today
          : Icons.close,
    ),
    onPressed: () async {
      if (filterController.selectedDate != null) {
        setState(() {
          filterController.selectedDate = null;
        });
      } else {
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );

        if (pickedDate != null) {
          setState(() {
            filterController.selectedDate = pickedDate;
          });
        }
      }
    },
  ),
  
   // 👤 EMPLOYEE FILTER
IconButton(
  icon: Icon(
    filterController.selectedEmployeeId == null
        ? Icons.person
        : Icons.close,
  ),
  onPressed: () async {
    if (filterController.selectedEmployeeId != null) {
      setState(() {
        filterController.selectedEmployeeId = null;
      });
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final employees = workOrders
            .expand((wo) => wo.assignedEmployees)
            .toList();

        final uniqueEmployees = {
          for (var e in employees) e.id: e
        }.values.toList();

        return ListView(
          children: uniqueEmployees.map((employee) {
            return ListTile(
              title: Text(employee.fullName),
              onTap: () {
                Navigator.pop(context, employee.id);
              },
            );
          }).toList(),
        );
      },
    );

    if (selected != null) {
      setState(() {
        filterController.setEmployee(selected);
      });
    }
  },
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
              child: StatusFilterBar(
  filters: const ["All", "Pending", "In Progress", "Closed"],
  selectedFilter: filterController.statusFilter,
  onFilterSelected: (status) {
    filterController.setStatus(status);

    setState(() {
      expandedIndex = null;
    });
  },
)
            ),
          ),

          const SizedBox(height: 10),
         buildActiveFiltersRow(),
          // ✅ LIST
          Expanded(
  child: WorkOrderList(
    orders: filteredOrders,
    onRefresh: loadWorkOrders,
    expandedIndex: expandedIndex,
    onTap: (index) {
      setState(() {
        expandedIndex = expandedIndex == index ? null : index;
      });
    },
    onEdit: (workOrder) async {
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
        await loadWorkOrders();
      }

      if (result == "deleted") {
        await loadWorkOrders();
      }
    },
  ),
)
        ],
      ),
      floatingActionButton: Column(
  mainAxisSize: MainAxisSize.min,
  children: [

    // 🔄 REFRESH BUTTON
    FloatingActionButton(
      heroTag: "refresh",
      mini: true,
      onPressed: loadWorkOrders,
      child: const Icon(Icons.refresh),
    ),

    const SizedBox(height: 10),

    // ➕ ADD WORK ORDER
    FloatingActionButton(
      heroTag: "add",
      onPressed: openAddScreen,
      child: const Icon(Icons.add),
    ),
  ],
),
    );
  }

 
}
