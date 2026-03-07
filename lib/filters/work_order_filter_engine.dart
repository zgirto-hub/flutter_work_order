import '../models/work_order.dart';
import '../controllers/filter_controller.dart';

class WorkOrderFilterEngine {

  static List<WorkOrder> applyFilters(
    List<WorkOrder> orders,
    FilterController filter,
  ) {

    List<WorkOrder> filtered = List.from(orders);

    // STATUS FILTER
    if (filter.statusFilter != "All") {
      filtered = filtered
          .where((wo) => wo.status == filter.statusFilter)
          .toList();
    }

    // SEARCH FILTER
    if (filter.searchQuery.isNotEmpty) {
      final query = filter.searchQuery;

      filtered = filtered.where((wo) {

        final jobNoMatch =
            wo.jobNo.toLowerCase().contains(query);

        final titleMatch =
            wo.Title.toLowerCase().contains(query);

        final descriptionMatch =
            wo.description.toLowerCase().contains(query);

        return jobNoMatch || titleMatch || descriptionMatch;

      }).toList();
    }

    // DATE FILTER
    if (filter.selectedDate != null) {

      filtered = filtered.where((wo) {

        final workOrderDate =
            DateTime.tryParse(wo.dateCreated);

        if (workOrderDate == null) return false;

        return workOrderDate.year == filter.selectedDate!.year &&
            workOrderDate.month == filter.selectedDate!.month &&
            workOrderDate.day == filter.selectedDate!.day;

      }).toList();
    }

    // EMPLOYEE FILTER
    if (filter.selectedEmployeeId != null) {

      filtered = filtered.where((wo) {

        return wo.assignedEmployees.any(
          (emp) => emp.id == filter.selectedEmployeeId,
        );

      }).toList();
    }

    return filtered;
  }
}