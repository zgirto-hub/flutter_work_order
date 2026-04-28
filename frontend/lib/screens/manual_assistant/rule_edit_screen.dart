import 'package:flutter/material.dart';
import '../../services/pattern_service.dart';
import '../../models/pattern_rule.dart';

class RuleEditScreen extends StatefulWidget {
  final PatternRule? rule;
  final String userEmail;

  const RuleEditScreen({
    super.key,
    this.rule,
    required this.userEmail,
  });

  @override
  State<RuleEditScreen> createState() => _RuleEditScreenState();
}

class _RuleEditScreenState extends State<RuleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = PatternService();
  bool _saving = false;

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _thresholdCountController;
  late TextEditingController _thresholdDaysController;

  String _severity = 'medium';
  String _detectionType = 'recurring_fault';
  String? _targetField;
  bool _enabled = true;

  bool get _isEdit => widget.rule != null;

  final _detectionTypes = {
    'recurring_fault': 'Recurring Fault',
    'technician_recurring': 'Technician Recurring',
    'procedure_deviation': 'Procedure Deviation',
    'seasonal_pattern': 'Seasonal Pattern',
    'long_resolution': 'Long Resolution',
    'parts_replaced_recurrence': 'Parts Recurrence',
  };

  final _targetFields = {
    'equipment_id': 'Equipment ID',
    'equipment_type': 'Equipment Type',
    'fault_type': 'Fault Type',
    'technician_id': 'Technician ID',
  };

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _descriptionController = TextEditingController(text: rule?.description ?? '');
    _thresholdCountController = TextEditingController(
      text: rule?.thresholdCount?.toString() ?? '',
    );
    _thresholdDaysController = TextEditingController(
      text: rule?.thresholdDays?.toString() ?? '',
    );
    if (rule != null) {
      _severity = rule.severity;
      _detectionType = rule.detectionType;
      _targetField = rule.targetField;
      _enabled = rule.enabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _thresholdCountController.dispose();
    _thresholdDaysController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final body = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'severity': _severity,
        'detection_type': _detectionType,
        'threshold_count': int.tryParse(_thresholdCountController.text),
        'threshold_days': int.tryParse(_thresholdDaysController.text),
        'target_field': _targetField,
        'enabled': _enabled,
      };

      PatternRule result;
      if (_isEdit) {
        result = await _service.updateRule(widget.rule!.id, body, widget.userEmail);
      } else {
        result = await _service.createRule(body, widget.userEmail);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Rule updated' : 'Rule created'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Rule' : 'Create Rule'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _severity,
              decoration: const InputDecoration(
                labelText: 'Severity',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _severity = value);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _detectionType,
              decoration: const InputDecoration(
                labelText: 'Detection Type',
                border: OutlineInputBorder(),
              ),
              items: _detectionTypes.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _detectionType = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _thresholdCountController,
              decoration: const InputDecoration(
                labelText: 'Threshold Count',
                border: OutlineInputBorder(),
                hintText: 'e.g., 3 occurrences',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final n = int.tryParse(value);
                  if (n == null || n < 1) {
                    return 'Must be >= 1';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _thresholdDaysController,
              decoration: const InputDecoration(
                labelText: 'Threshold Days',
                border: OutlineInputBorder(),
                hintText: 'e.g., 180 days',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final n = int.tryParse(value);
                  if (n == null || n < 1) {
                    return 'Must be >= 1';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _targetField,
              decoration: const InputDecoration(
                labelText: 'Target Field',
                border: OutlineInputBorder(),
              ),
              items: _targetFields.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                setState(() => _targetField = value);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Update Rule' : 'Create Rule'),
            ),
          ],
        ),
      ),
    );
  }
}