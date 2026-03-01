import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../widgets/work_order_card.dart';
import '../services/work_order_service.dart';
import 'add_work_order.dart';
import '../models/employee_assignment.dart';
class WorkOrderHome extends StatefulWidget {
  const WorkOrderHome({super.key});

  @override
  State<WorkOrderHome> createState() => _WorkOrderHomeState();
}

class _WorkOrderHomeState extends State<WorkOrderHome> {
  bool _isSearching = false;
  String _searchQuery = "";
  String? _selectedEmployeeId;
  final TextEditingController _searchController = TextEditingController();
  String selectedFilter = "All";
  int? expandedIndex;

  DateTime? _selectedDate;

  final WorkOrderService _service = WorkOrderService();
  List<WorkOrder> workOrders = [];

  @override
  void initState() {
    super.initState();
    loadWorkOrders();
  }
  Widget buildActiveFiltersRow() {
  final List<Widget> chips = [];

  if (_searchQuery.isNotEmpty) {
    chips.add(
      FilterChip(
        label: Text("🔍 $_searchQuery"),
        onSelected: (_) {
          setState(() {
            _searchController.clear();
            _searchQuery = "";
          });
        },
      ),
    );
  }

  if (_selectedDate != null) {
    chips.add(
      FilterChip(
        label: Text(
          "📅 ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}",
        ),
        onSelected: (_) {
          setState(() {
            _selectedDate = null;
          });
        },
      ),
    );
  }

  if (_selectedEmployeeId != null) {
    final employeeName = workOrders
        .expand((wo) => wo.assignedEmployees)
        .firstWhere(
          (emp) => emp.id == _selectedEmployeeId,
          orElse: () =>  EmployeeAssignment(id: '', fullName: ''),
        )
        .fullName;

    chips.add(
      FilterChip(
        label: Text("👤 $employeeName"),
        onSelected: (_) {
          setState(() {
            _selectedEmployeeId = null;
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
          _searchQuery = "";
          _searchController.clear();
          _selectedDate = null;
          _selectedEmployeeId = null;
          selectedFilter = "All";
        });
      },
      child: const Text("Clear All"),
    ),
  );

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      children: chips,
    ),
  );
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
    List<WorkOrder> filteredOrders = workOrders;

// ✅ Filter by StatusList<WorkOrder> filteredOrders = workOrders;

// ✅ Filter by Status
    if (selectedFilter != "All") {
      filteredOrders =
          filteredOrders.where((wo) => wo.status == selectedFilter).toList();
    }

// ✅ Filter by Search (Job No + Description)
    if (_searchQuery.isNotEmpty) {
      filteredOrders = filteredOrders.where((wo) {
        final jobNoMatch = wo.jobNo.toLowerCase().contains(_searchQuery);

        final descriptionMatch =
            wo.description.toLowerCase().contains(_searchQuery);

        return jobNoMatch || descriptionMatch;
      }).toList();
    }
    // ✅ Filter by Date
if (_selectedDate != null) {
  filteredOrders = filteredOrders.where((wo) {
    final workOrderDate = DateTime.tryParse(wo.dateCreated);

    if (workOrderDate == null) return false;

    return workOrderDate.year == _selectedDate!.year &&
        workOrderDate.month == _selectedDate!.month &&
        workOrderDate.day == _selectedDate!.day;
  }).toList();
}
// ✅ Filter by Employee
if (_selectedEmployeeId != null) {
  filteredOrders = filteredOrders.where((wo) {
    return wo.assignedEmployees
        .any((emp) => emp.id == _selectedEmployeeId);
  }).toList();
}
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color.fromARGB(237, 221, 226, 226),
        foregroundColor: Colors.black,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "Search job no or description...",
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
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
          _searchQuery = "";
        }
      });
    },
  ),

  // 📅 DATE FILTER BUTTON
  IconButton(
    icon: Icon(
      _selectedDate == null
          ? Icons.calendar_today
          : Icons.close,
    ),
    onPressed: () async {
      if (_selectedDate != null) {
        setState(() {
          _selectedDate = null;
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
            _selectedDate = pickedDate;
          });
        }
      }
    },
  ),
  
  
IconButton(
  icon: Icon(
    _selectedEmployeeId == null
        ? Icons.person
        : Icons.close,
  ),
  onPressed: () async {
    if (_selectedEmployeeId != null) {
      setState(() {
        _selectedEmployeeId = null;
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
        _selectedEmployeeId = selected;
      });
    }
  },
),
  // ➕ ADD BUTTON
  IconButton(
    icon: const Icon(Icons.add),
    onPressed: openAddScreen,
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
         buildActiveFiltersRow(),
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
