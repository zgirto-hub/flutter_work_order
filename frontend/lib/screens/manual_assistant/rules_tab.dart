import 'package:flutter/material.dart';
import '../../services/pattern_service.dart';
import '../../models/pattern_rule.dart';
import 'widgets/rule_card.dart';
import 'rule_edit_screen.dart';

class RulesTab extends StatefulWidget {
  final String userEmail;

  const RulesTab({
    super.key,
    required this.userEmail,
  });

  @override
  State<RulesTab> createState() => RulesTabState();
}

class RulesTabState extends State<RulesTab> {
  final PatternService _service = PatternService();
  List<PatternRule> _rules = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  void reload() => _loadRules();

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await _service.getRules();
      if (mounted) {
        setState(() {
          _rules = rules;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleToggle(PatternRule rule) async {
    try {
      final updated = await _service.toggleRule(rule.id, widget.userEmail);
      if (mounted) {
        setState(() {
          final idx = _rules.indexWhere((r) => r.id == rule.id);
          if (idx != -1) {
            _rules[idx] = updated;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleDelete(PatternRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content: Text('Are you sure you want to delete "${rule.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteRule(rule.id, widget.userEmail);
      if (mounted) {
        setState(() {
          _rules.removeWhere((r) => r.id == rule.id);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rule deleted')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${e.toString()}')),
        );
      }
    }
  }

  void _navigateToEdit({PatternRule? rule}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RuleEditScreen(rule: rule, userEmail: widget.userEmail),
      ),
    );
    if (result == true) {
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: _loadRules,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_rules.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rule, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No pattern rules configured'),
          ],
        ),
      );
    } else {
      body = ListView.builder(
        itemCount: _rules.length,
        itemBuilder: (context, index) {
          final rule = _rules[index];
          return RuleCard(
            rule: rule,
            onToggle: () => _handleToggle(rule),
            onEdit: () => _navigateToEdit(rule: rule),
            onDelete: () => _handleDelete(rule),
          );
        },
      );
    }

    return Stack(
      children: [
        body,
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () => _navigateToEdit(),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
