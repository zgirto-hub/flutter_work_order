import 'package:flutter/material.dart';
import '../models/employee.dart';

class EmployeeSelector extends StatefulWidget {
  final List<Employee> employees;
  final List<String> selectedIds;
  final Function(List<String>) onChanged;

  const EmployeeSelector({
    super.key,
    required this.employees,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<EmployeeSelector> createState() => _EmployeeSelectorState();
}

class _EmployeeSelectorState extends State<EmployeeSelector> {
  late List<String> selected;
  String search = "";

  @override
  void initState() {
    super.initState();
    selected = List.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final filteredEmployees = widget.employees
        .where((e) =>
            e.fullName.toLowerCase().contains(search.toLowerCase()))
        .toList();

    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: SizedBox(
        height: 500,
        child: Column(
          children: [
            const SizedBox(height: 10),

            const Text(
              "Select Employees",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: "Search employee...",
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    search = value;
                  });
                },
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: filteredEmployees.length,
                itemBuilder: (context, index) {
                  final employee = filteredEmployees[index];
                  final isSelected = selected.contains(employee.id);

                  return CheckboxListTile(
                    value: isSelected,
                    title: Text(employee.fullName),
                    subtitle: Text(employee.shiftType),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selected.add(employee.id);
                        } else {
                          selected.remove(employee.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () {
                  widget.onChanged(selected);
                  Navigator.pop(context);
                },
                child: const Text("Confirm Selection"),
              ),
            )
          ],
        ),
      ),
    );
  }
}