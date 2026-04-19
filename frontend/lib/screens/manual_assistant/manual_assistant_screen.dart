import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/manual_assistant_service.dart';
import 'chat_tab.dart';
import 'review_queue_tab.dart';
import 'rules_tab.dart';
import 'alerts_tab.dart';
import 'verified_answers_tab.dart';
import 'documents_tab.dart';
import 'train_ai_tab.dart';
import 'rag_diagnostics_tab.dart';
import '../../services/rag_diagnostic_service.dart';

class ManualAssistantScreen extends StatefulWidget {
  final String userRole;
  const ManualAssistantScreen({super.key, this.userRole = ''});

  @override
  State<ManualAssistantScreen> createState() => _ManualAssistantScreenState();
}

class _ManualAssistantScreenState extends State<ManualAssistantScreen>
    with TickerProviderStateMixin {
  late final bool _isAdmin;
  late final String _userEmail;
  late final TabController _tabController;
  final ManualAssistantService _service = ManualAssistantService();
  int _flaggedCount = 0;
  final GlobalKey<ReviewQueueTabState> _reviewQueueKey =
      GlobalKey<ReviewQueueTabState>();

  @override
  void initState() {
    super.initState();
    _isAdmin = widget.userRole == 'admin';
    _userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    _tabController = TabController(length: _isAdmin ? 8 : 1, vsync: this);

    if (_isAdmin) {
      _loadFlaggedCount();
      _tabController.addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && _tabController.index == 1) {
      // Switched to Review Queue tab — reload entries (index 1 after Knowledge tab removed)
      _reviewQueueKey.currentState?.reload();
    }
  }

  Future<void> _loadFlaggedCount() async {
    try {
      final entries = await _service.getFlaggedAnswers(userEmail: _userEmail);
      if (mounted) {
        setState(() => _flaggedCount = entries.length);
      }
    } catch (_) {}
  }

  void _onReviewCountChanged(int newCount) {
    if (mounted) {
      setState(() => _flaggedCount = newCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask the AI'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.tune_outlined, size: 20),
              tooltip: 'System Instructions',
              onPressed: () => _showInstructionsDialog(context),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Chat'),
            if (_isAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Badge(
                      isLabelVisible: _flaggedCount > 0,
                      label: Text('$_flaggedCount'),
                      child: const Icon(Icons.rate_review, size: 18),
                    ),
                    const SizedBox(width: 4),
                    const Text('Review'),
                  ],
                ),
              ),
            if (_isAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.rule, size: 18),
                    SizedBox(width: 4),
                    Text('Rules'),
                  ],
                ),
              ),
            if (_isAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.notifications_active, size: 18),
                    SizedBox(width: 4),
                    Text('Alerts'),
                  ],
                ),
              ),
            if (_isAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.verified_outlined, size: 18),
                    SizedBox(width: 4),
                    Text('Verified'),
                  ],
                ),
              ),
            if (_isAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.description_outlined, size: 18),
                    SizedBox(width: 4),
                    Text('Documents'),
                  ],
                ),
              ),
            if (_isAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.psychology_outlined, size: 18),
                    SizedBox(width: 4),
                    Text('Train AI'),
                  ],
                ),
              ),
            if (_isAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.analytics_outlined, size: 18),
                    SizedBox(width: 4),
                    Text('RAG Logs'),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const ChatTab(),
          if (_isAdmin)
            ReviewQueueTab(
              key: _reviewQueueKey,
              userEmail: _userEmail,
              onCountChanged: _onReviewCountChanged,
            ),
          if (_isAdmin) RulesTab(userEmail: _userEmail),
          if (_isAdmin) AlertsTab(userEmail: _userEmail),
          if (_isAdmin) VerifiedAnswersTab(userEmail: _userEmail),
          if (_isAdmin) DocumentsTab(userEmail: _userEmail),
          if (_isAdmin) TrainAiTab(userEmail: _userEmail, service: _service),
            if (_isAdmin) RagDiagnosticsTab(userEmail: _userEmail, service: RagDiagnosticService()),
        ],
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
