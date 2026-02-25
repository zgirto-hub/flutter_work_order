import 'package:flutter/material.dart';
import '../models/work_order.dart';

class AddWorkOrderScreen extends StatefulWidget {
  final WorkOrder? workOrder;

  const AddWorkOrderScreen({super.key, this.workOrder});

  @override
  State<AddWorkOrderScreen> createState() => _AddWorkOrderScreenState();
}
  

class _AddWorkOrderScreenState extends State<AddWorkOrderScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController jobNoController = TextEditingController();
  final TextEditingController clientController = TextEditingController();
  final TextEditingController descriptionController =
      TextEditingController();

  String selectedStatus = "Open";
@override
void initState() {
  super.initState();

  if (widget.workOrder != null) {
    jobNoController.text = widget.workOrder!.jobNo;
    clientController.text = widget.workOrder!.client;
    descriptionController.text = widget.workOrder!.description;
    selectedStatus = widget.workOrder!.status;
  }
}
void submit() {
  if (_formKey.currentState!.validate()) {
    final updatedWorkOrder = WorkOrder(
      jobNo: jobNoController.text,
      client: clientController.text,
      status: selectedStatus,
      description: descriptionController.text,
    );

    Navigator.pop(context, updatedWorkOrder);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: Text(
    widget.workOrder == null
        ? "New Work Order"
        : "Edit Work Order",
  ),
),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: jobNoController,
                decoration: const InputDecoration(labelText: "Job No"),
                validator: (value) =>
                    value!.isEmpty ? "Enter Job No" : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: clientController,
                decoration: const InputDecoration(labelText: "Client"),
                validator: (value) =>
                    value!.isEmpty ? "Enter Client" : null,
              ),
              const SizedBox(height: 10),
               DropdownButtonFormField<String>(
               initialValue: selectedStatus,
                items: const [
                  DropdownMenuItem(
                      value: "Open", child: Text("Open")),
                  DropdownMenuItem(
                      value: "In Progress",
                      child: Text("In Progress")),
                  DropdownMenuItem(
                      value: "Closed", child: Text("Closed")),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedStatus = value!;
                  });
                },
                decoration:
                    const InputDecoration(labelText: "Status"),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: descriptionController,
                decoration:
                    const InputDecoration(labelText: "Description"),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: submit,
               child: Text(
                  widget.workOrder == null
                      ? "Add Work Order"
                      : "Save Changes",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}