import 'package:flutter/material.dart';
import '../../services/pattern_service.dart';
import '../../models/pattern_alert.dart';
import 'widgets/alert_card.dart';

class AlertsTab extends StatefulWidget {
  final String userEmail;

  const AlertsTab({
    super.key,
    required this.userEmail,
  });

  @override
  State<AlertsTab> createState() => AlertsTabState();
}

class AlertsTabState extends State<AlertsTab> {
  final PatternService _service = PatternService();
  List<PatternAlert> _alerts = [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;
  String? _severityFilter;
  int _page = 1;
  int _total = 0;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  void reload() => _loadAlerts();

  Future<void> _loadAlerts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.getAlerts(
        userEmail: widget.userEmail,
        status: _statusFilter,
        severity: _severityFilter,
        page: _page,
        pageSize: _pageSize,
      );
      if (mounted) {
        setState(() {
          _alerts = result['alerts'] as List<PatternAlert>;
          _total = result['total'] as int;
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

  Future<void> _handleStatusChange(PatternAlert alert, String newStatus) async {
    try {
      final updated = await _service.updateAlertStatus(alert.id, newStatus, widget.userEmail);
      if (mounted) {
        setState(() {
          final idx = _alerts.indexWhere((a) => a.id == alert.id);
          if (idx != -1) {
            _alerts[idx] = updated;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _triggerScan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run Full Scan'),
        content: const Text(
            'Run full pattern scan against all work order entities?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _service.triggerScan(widget.userEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scan complete: ${result['alerts_created']} alerts created, '
              '${result['alerts_skipped_duplicate']} duplicates skipped in '
              '${result['duration_seconds']}s',
            ),
          ),
        );
        reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: _buildAlertList(),
        ),
        _buildPagination(),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          DropdownButton<String?>(
            value: _statusFilter,
            hint: const Text('Status'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All')),
              DropdownMenuItem(value: 'new', child: Text('New')),
              DropdownMenuItem(
                  value: 'acknowledged', child: Text('Acknowledged')),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
            ],
            onChanged: (value) {
              setState(() {
                _statusFilter = value;
                _page = 1;
              });
              _loadAlerts();
            },
          ),
          const SizedBox(width: 8),
          DropdownButton<String?>(
            value: _severityFilter,
            hint: const Text('Severity'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
            ],
            onChanged: (value) {
              setState(() {
                _severityFilter = value;
                _page = 1;
              });
              _loadAlerts();
            },
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: reload,
          ),
          IconButton(
            icon: const Icon(Icons.radar),
            onPressed: _triggerScan,
            tooltip: 'Run Full Scan',
          ),
        ],
      ),
    );
  }

  Widget _buildAlertList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: _loadAlerts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No pattern alerts'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _alerts.length,
      itemBuilder: (context, index) {
        final alert = _alerts[index];
        return AlertCard(
          alert: alert,
          onStatusChange: (status) => _handleStatusChange(alert, status),
        );
      },
    );
  }

  Widget _buildPagination() {
    final totalPages = (_total / _pageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1
                ? () {
                    setState(() => _page--);
                    _loadAlerts();
                  }
                : null,
          ),
          Text('Page $_page of $totalPages'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page < totalPages
                ? () {
                    setState(() => _page++);
                    _loadAlerts();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
