import 'package:flutter/material.dart';
import '../models/user.dart';

class TechnicianSelector extends StatefulWidget {
  final List<AppUser> technicians;
  final List<String> selectedIds;
  final Function(List<String>) onChanged;

  const TechnicianSelector({
    super.key,
    required this.technicians,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<TechnicianSelector> createState() => _TechnicianSelectorState();
}

class _TechnicianSelectorState extends State<TechnicianSelector> {
  late List<String> selected;
  String search = "";

  @override
  void initState() {
    super.initState();
    selected = List.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.technicians
        .where((e) =>
            (e.fullName ?? '').toLowerCase().contains(search.toLowerCase()))
        .toList();

    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: SizedBox(
        height: 500,
        child: Column(
          children: [
            const SizedBox(height: 10),

            const Text(
              "Select Technicians",
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
                  hintText: "Search technician...",
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
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final technician = filtered[index];
                  final isSelected = selected.contains(technician.id);

                  return CheckboxListTile(
                    value: isSelected,
                    title: Text(technician.displayName),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selected.add(technician.id);
                        } else {
                          selected.remove(technician.id);
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
