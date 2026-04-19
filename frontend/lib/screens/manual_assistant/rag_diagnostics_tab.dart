import 'package:flutter/material.dart';
import '../../models/rag_diagnostic_entry.dart';
import '../../services/rag_diagnostic_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bottom_sheet_widgets.dart';

class RagDiagnosticsTab extends StatefulWidget {
  final String userEmail;
  final RagDiagnosticService? service;

  const RagDiagnosticsTab({
    super.key,
    required this.userEmail,
    this.service,
  });

  @override
  State<RagDiagnosticsTab> createState() => RagDiagnosticsTabState();
}

class RagDiagnosticsTabState extends State<RagDiagnosticsTab> {
  late final RagDiagnosticService _service;
  List<RagDiagnosticEntry> _entries = [];
  int _total = 0;
  bool _loading = true;
  String? _error;

  String? _sourceFilter;
  String? _decisionFilter;
  String? _reasonCodeFilter;
  String _timeRange = 'last24h';
  int _offset = 0;
  static const int _limit = 50;

  static const List<String> _sourceOptions = ['user', 'test_suite', 'internal'];
  static const List<String> _decisionOptions = ['grounded', 'ungrounded', 'error'];
  static const List<String> _reasonCodeOptions = [
    'grounded_answer',
    'verbatim_answer',
    'short_circuited_no_rag',
    'no_chunks_retrieved',
    'rerank_below_threshold',
    'generator_refused_with_chunks',
    'pipeline_error',
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RagDiagnosticService();
    _loadEntries();
  }

  void reload() => _loadEntries();

  String _fromTimestamp() {
    final now = DateTime.now();
    switch (_timeRange) {
      case 'last1h':
        return now.subtract(const Duration(hours: 1)).toUtc().toIso8601String();
      case 'last7d':
        return now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
      default:
        return now.subtract(const Duration(hours: 24)).toUtc().toIso8601String();
    }
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (entries, total) = await _service.fetchEntries(
        source: _sourceFilter,
        decision: _decisionFilter,
        reasonCode: _reasonCodeFilter,
        from: _fromTimestamp(),
        limit: _limit,
        offset: _offset,
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _total = total;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _showDetail(RagDiagnosticEntry entry) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final detail = await _service.fetchDetail(entry.id);
      if (mounted) {
        Navigator.of(context).pop();
        showAppBottomSheet(
          context: context,
          child: _DiagnosticDetailSheet(entry: detail),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load detail: $e')),
        );
      }
    }
  }

  Color _decisionColor(String decision) {
    switch (decision) {
      case 'grounded':
        return Colors.green.shade700;
      case 'ungrounded':
        return Colors.orange.shade700;
      case 'error':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildFilterRow(theme),
        const Divider(height: 1),
        Expanded(child: _buildList(theme)),
      ],
    );
  }

  Widget _buildFilterRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _filterChip('Source', _sourceFilter, _sourceOptions, (v) {
            setState(() { _sourceFilter = v; _offset = 0; });
            _loadEntries();
          }),
          _filterChip('Decision', _decisionFilter, _decisionOptions, (v) {
            setState(() { _decisionFilter = v; _offset = 0; });
            _loadEntries();
          }),
          _filterChip('Reason', _reasonCodeFilter, _reasonCodeOptions, (v) {
            setState(() { _reasonCodeFilter = v; _offset = 0; });
            _loadEntries();
          }),
          _timeRangeChip(),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? value, List<String> options, Function(String?) onSelected) {
    return InputChip(
      label: Text(value != null ? '$label: $value' : label),
      selected: value != null,
      onDeleted: value != null ? () { onSelected(null); } : null,
      onPressed: () {
        showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('Select $label'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('(All)'),
              ),
              ...options.map((o) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, o),
                child: Text(o),
              )),
            ],
          ),
        ).then((v) {
          if (v != null || label == 'Decision' || label == 'Source' || label == 'Reason') {
            onSelected(v);
          }
        });
      },
    );
  }

  Widget _timeRangeChip() {
    return InputChip(
      label: Text(_timeRangeLabel()),
      onPressed: () {
        showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Time Range'),
            children: [
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'last1h'), child: const Text('Last 1 hour')),
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'last24h'), child: const Text('Last 24 hours')),
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'last7d'), child: const Text('Last 7 days')),
            ],
          ),
        ).then((v) {
          if (v != null) {
            setState(() { _timeRange = v; _offset = 0; });
            _loadEntries();
          }
        });
      },
    );
  }

  String _timeRangeLabel() {
    switch (_timeRange) {
      case 'last1h': return 'Last 1h';
      case 'last7d': return 'Last 7d';
      default: return 'Last 24h';
    }
  }

  Widget _buildList(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('No diagnostic entries found.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('$_total total', style: theme.textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _entries.length,
            itemBuilder: (ctx, i) {
              final e = _entries[i];
              return ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _decisionColor(e.decision).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    e.decision,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _decisionColor(e.decision)),
                  ),
                ),
                title: Text(
                  e.questionRaw.length > 80 ? '${e.questionRaw.substring(0, 80)}...' : e.questionRaw,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                subtitle: Text(
                  '${e.reasonCode}  ${e.totalMs}ms',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
                trailing: Text(
                  _formatTime(e.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
                onTap: () => _showDetail(e),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _DiagnosticDetailSheet extends StatelessWidget {
  final RagDiagnosticEntry entry;
  const _DiagnosticDetailSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerRow(theme),
          const SizedBox(height: 12),
          _sectionTitle('Question', theme),
          Text(entry.questionRaw, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          _decisionBadge(theme),
          const SizedBox(height: 8),
          _infoRow('Reason Code', entry.reasonCode, theme),
          if (entry.reasonNote != null) _infoRow('Note', entry.reasonNote!, theme),
          _infoRow('Source', entry.source, theme),
          _infoRow('Provider', entry.providerUsed ?? '-', theme),
          const Divider(height: 24),
          if (entry.pipelineStages != null) ...[
            _sectionTitle('Pipeline Stages', theme),
            ..._buildStages(theme),
          ],
          if (entry.thresholds != null) ...[
            const SizedBox(height: 12),
            _sectionTitle('Thresholds', theme),
            _jsonBlock(entry.thresholds!, theme),
          ],
          const SizedBox(height: 12),
          _sectionTitle('Latency Breakdown', theme),
          _jsonBlock(entry.latencyBreakdown, theme),
        ],
      ),
    );
  }

  Widget _headerRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Diagnostic Detail',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Text(_formatTimestamp(entry.createdAt), style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _decisionBadge(ThemeData theme) {
    final color = entry.decision == 'grounded' ? Colors.green
        : entry.decision == 'ungrounded' ? Colors.orange : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        entry.decision.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
      ),
    );
  }

  Widget _sectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  Widget _infoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text('$label:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  List<Widget> _buildStages(ThemeData theme) {
    final stages = entry.pipelineStages!;
    final widgets = <Widget>[];
    for (final stage in _stageOrder) {
      if (!stages.containsKey(stage)) continue;
      final data = stages[stage];
      if (data is! Map) continue;
      widgets.add(const SizedBox(height: 8));
      widgets.add(_sectionTitle(_stageLabel(stage), theme));
      widgets.add(_jsonBlock(Map<String, dynamic>.from(data), theme));
    }
    return widgets;
  }

  Widget _jsonBlock(Map<String, dynamic> data, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _prettyJson(data),
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  String _prettyJson(Map<String, dynamic> data) {
    final buf = StringBuffer();
    for (final e in data.entries) {
      if (e.value is List) {
        buf.writeln('${e.key}:');
        for (final item in (e.value as List).take(5)) {
          buf.writeln('  - $item');
        }
        if ((e.value as List).length > 5) {
          buf.writeln('  ... and ${(e.value as List).length - 5} more');
        }
      } else if (e.value is Map) {
        buf.writeln('${e.key}: ${_prettyJson(Map<String, dynamic>.from(e.value as Map))}');
      } else {
        buf.writeln('${e.key}: ${e.value}');
      }
    }
    return buf.toString().trim();
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static const List<String> _stageOrder = [
    'rewrite', 'hyde', 'retrieval', 'rerank', 'grounding', 'generator',
  ];

  static String _stageLabel(String stage) {
    switch (stage) {
      case 'rewrite': return 'Query Rewrite';
      case 'hyde': return 'Hypothetical Document (HyDE)';
      case 'retrieval': return 'Retrieval';
      case 'rerank': return 'Rerank';
      case 'grounding': return 'Grounding Decision';
      case 'generator': return 'Generator';
      default: return stage;
    }
  }
}