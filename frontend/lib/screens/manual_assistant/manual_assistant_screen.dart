import 'package:flutter/material.dart';
import '../../services/manual_assistant_service.dart';
import 'chat_tab.dart';
import 'manuals_tab.dart';

class ManualAssistantScreen extends StatelessWidget {
  final String userRole;
  const ManualAssistantScreen({super.key, this.userRole = ''});

  @override
  Widget build(BuildContext context) {
    final isAdmin = userRole == 'admin';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ask the AI'),
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.tune_outlined, size: 20),
                tooltip: 'System Instructions',
                onPressed: () => _showInstructionsDialog(context),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chat'),
              Tab(text: 'Knowledge'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ChatTab(),
            ManualsTab(),
          ],
        ),
      ),
    );
  }

  void _showInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _SystemInstructionsDialog(),
    );
  }
}

class _SystemInstructionsDialog extends StatefulWidget {
  const _SystemInstructionsDialog();

  @override
  State<_SystemInstructionsDialog> createState() =>
      _SystemInstructionsDialogState();
}

class _SystemInstructionsDialogState extends State<_SystemInstructionsDialog> {
  final _service = ManualAssistantService();
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final instructions = await _service.getSystemInstructions();
    if (mounted) {
      setState(() {
        _controller.text = instructions;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.updateSystemInstructions(_controller.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('System instructions saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('System Instructions'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'These instructions are prepended to every assistant prompt. '
                    'Use them to describe your department, terminology, and rules.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    maxLines: 8,
                    minLines: 4,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. You are assisting technicians at Kuwait DGCA. '
                          'Our main systems are CADAS-IMS and AFTN...',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  if (_saving) ...[
                    const SizedBox(height: 8),
                    const Center(
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 1.5))),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving || _loading ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
