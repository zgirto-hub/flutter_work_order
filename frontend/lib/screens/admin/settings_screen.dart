import 'package:flutter/material.dart';
import '../../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService();
  bool _loading = true;
  bool _extractionEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final data = await _service.getSetting('entity_extraction_enabled');
      setState(() {
        _extractionEnabled = data['value'] == 'true';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleExtraction(bool value) async {
    try {
      await _service.updateSetting(
          'entity_extraction_enabled', value ? 'true' : 'false');
      setState(() {
        _extractionEnabled = value;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI & Automation Controls'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  children: [
                    SwitchListTile(
                      title: const Text('Entity Extraction'),
                      subtitle: const Text(
                        'Automatically extract equipment, faults, and actions from work orders',
                      ),
                      value: _extractionEnabled,
                      onChanged: _toggleExtraction,
                    ),
                  ],
                ),
    );
  }
}
