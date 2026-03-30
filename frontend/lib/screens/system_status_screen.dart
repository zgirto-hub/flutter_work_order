import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../models/system_status_report.dart';
import '../services/system_status_service.dart';

class SystemStatusScreen extends StatefulWidget {
  const SystemStatusScreen({super.key});

  @override
  State<SystemStatusScreen> createState() => _SystemStatusScreenState();
}

class _SystemStatusScreenState extends State<SystemStatusScreen> {
  final _service = SystemStatusService();
  bool _loading = true;
  List<SystemStatus> _systems = [];
  List<SystemStatus> _mainSystems = [];
  Map<String, List<SystemStatus>> _groupedSystems = {};
  List<SystemStatusReport> _history = [];

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  String get _userName =>
      _email.split('@').first.split('.').map((s) =>
        s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : s
      ).join(' ');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.fetchTodayStatus(),
        _service.fetchHistory(limit: 20),
      ]);
      if (!mounted) return;
      setState(() {
        _systems = results[0] as List<SystemStatus>;
        _history = results[1] as List<SystemStatusReport>;
        _mainSystems = [];
        _groupedSystems = {};
        for (final s in _systems) {
          if (s.systemName.contains(' - ')) {
            final prefix = s.systemName.split(' - ').first;
            _groupedSystems.putIfAbsent(prefix, () => []).add(s);
          } else {
            _mainSystems.add(s);
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load: $e')),
      );
    }
  }

  // ── Report Issue ──────────────────────────────────────────────────────────

  void _showReportIssueSheet(SystemStatus system) {
    if (system.hasIssue) {
      _showIssueDetailsSheet(system);
      return;
    }

    DateTime selectedDate = DateTime.now();
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Issue',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                system.systemName,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // Date picker
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setSheetState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe the issue...',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.bgSurface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final dateStr =
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                    try {
                      await _service.reportIssue(
                        systemName: system.systemName,
                        reportDate: dateStr,
                        notes: notesController.text.trim(),
                        reportedBy: _email,
                        reportedByName: _userName,
                      );
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _load();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Issue reported')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Report Issue',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Issue Details ─────────────────────────────────────────────────────────

  void _showIssueDetailsSheet(SystemStatus system) {
    final report = system.activeReport!;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFB91C1C),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    system.systemName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Date', report.reportDate),
            if (report.notes.isNotEmpty) _detailRow('Notes', report.notes),
            _detailRow('Reported by', report.reportedByName.isNotEmpty
                ? report.reportedByName
                : report.reportedBy),
            const SizedBox(height: 20),
            // Action buttons row
            Row(
              children: [
                // Edit button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditIssueSheet(report);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Delete button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDelete(report);
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      side: const BorderSide(color: Color(0xFFB91C1C)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Resolve button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await _service.resolveIssue(
                          reportId: report.id,
                          resolvedBy: _email,
                        );
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        _load();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Issue resolved')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Resolve',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit Issue ────────────────────────────────────────────────────────────

  void _showEditIssueSheet(SystemStatusReport report) {
    final notesController = TextEditingController(text: report.notes);
    DateTime selectedDate = DateTime.tryParse(report.reportDate) ?? DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Issue',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                report.systemName,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // Date picker
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setSheetState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe the issue...',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.bgSurface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final dateStr =
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                    try {
                      await _service.updateIssue(
                        reportId: report.id,
                        notes: notesController.text.trim(),
                        reportDate: dateStr,
                      );
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _load();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Issue updated')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delete Confirmation ───────────────────────────────────────────────────

  void _confirmDelete(SystemStatusReport report) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(
          'Delete Issue',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Delete the issue report for ${report.systemName} on ${report.reportDate}? This cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _service.deleteIssue(reportId: report.id);
                if (!mounted) return;
                Navigator.pop(ctx);
                _load();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Issue deleted')),
                );
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$e')),
                );
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Uptime Report ─────────────────────────────────────────────────────────

  void _showUptimeReportSheet() {
    DateTime startDate = DateTime.now().subtract(const Duration(days: 30));
    DateTime endDate = DateTime.now();
    List<SystemUptimeReport>? reportData;
    bool generating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          String formatDate(DateTime d) =>
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

          Future<void> pickDate(bool isStart) async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: isStart ? startDate : endDate,
              firstDate: DateTime(2024),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setSheetState(() {
                if (isStart) {
                  startDate = picked;
                } else {
                  endDate = picked;
                }
              });
            }
          }

          Future<void> generate() async {
            setSheetState(() => generating = true);
            try {
              final data = await _service.fetchUptimeReport(
                startDate: formatDate(startDate),
                endDate: formatDate(endDate),
              );
              setSheetState(() {
                reportData = data;
                generating = false;
              });
            } catch (e) {
              setSheetState(() => generating = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('$e')),
                );
              }
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            expand: false,
            builder: (_, scrollController) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Uptime Report',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date pickers
                  Row(
                    children: [
                      Expanded(
                        child: _DatePickerField(
                          label: 'Start',
                          value: formatDate(startDate),
                          onTap: () => pickDate(true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DatePickerField(
                          label: 'End',
                          value: formatDate(endDate),
                          onTap: () => pickDate(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: generating ? null : generate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: generating
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Generate Report',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Results
                  if (reportData != null)
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          // Overall summary donut
                          _OverallUptimeChart(data: reportData!),
                          const SizedBox(height: 16),

                          // Per-system cards
                          ...reportData!
                              .map((r) => _SystemUptimeCard(report: r)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'System Status',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.pie_chart_outline,
                color: AppColors.textSecondary, size: 20),
            tooltip: 'Uptime Report',
            onPressed: _showUptimeReportSheet,
          ),
          IconButton(
            icon: Icon(Icons.refresh,
                color: AppColors.textSecondary, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main systems grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: _mainSystems.length,
                      itemBuilder: (context, i) => _SystemCard(
                        system: _mainSystems[i],
                        onTap: () =>
                            _showReportIssueSheet(_mainSystems[i]),
                      ),
                    ),

                    // Grouped sub-systems
                    for (final entry in _groupedSystems.entries) ...[
                      const SizedBox(height: 20),
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: entry.value.length,
                        itemBuilder: (context, i) => _SystemCard(
                          system: entry.value[i],
                          displayName: entry.value[i].systemName.split(' - ').last,
                          onTap: () =>
                              _showReportIssueSheet(entry.value[i]),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // History section
                    if (_history.isNotEmpty) ...[
                      Text(
                        'Recent Issues',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._history.map((r) => _HistoryCard(
                        report: r,
                        onEdit: () => _showEditIssueSheet(r),
                        onDelete: () => _confirmDelete(r),
                      )),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

// ── System Card ───────────────────────────────────────────────────────────────

class _SystemCard extends StatelessWidget {
  final SystemStatus system;
  final String? displayName;
  final VoidCallback onTap;

  const _SystemCard({required this.system, this.displayName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIssue = system.hasIssue;
    final statusColor =
        isIssue ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    final bgColor =
        isIssue ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border2, width: 0.5),
          boxShadow: AppShadows.cardLight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName ?? system.systemName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isIssue ? 'Issue Reported' : 'Operational',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: statusColor,
                ),
              ),
            ),
            if (isIssue && system.activeReport != null) ...[
              const SizedBox(height: 4),
              Text(
                system.activeReport!.notes.isNotEmpty
                    ? system.activeReport!.notes
                    : 'Reported by ${system.activeReport!.reportedByName.isNotEmpty ? system.activeReport!.reportedByName : system.activeReport!.reportedBy}',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── History Card ──────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final SystemStatusReport report;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HistoryCard({
    required this.report,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isResolved = report.isResolved;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isResolved
                  ? const Color(0xFF15803D)
                  : const Color(0xFFB91C1C),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      report.systemName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      report.reportDate,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        icon: Icon(
                          Icons.more_vert,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        onSelected: (value) {
                          if (value == 'edit') onEdit();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          if (!isResolved)
                            const PopupMenuItem(
                              value: 'edit',
                              height: 36,
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('Edit', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          PopupMenuItem(
                            value: 'delete',
                            height: 36,
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 16, color: Color(0xFFB91C1C)),
                                SizedBox(width: 8),
                                Text('Delete',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFB91C1C),
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (report.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    report.notes,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  isResolved ? 'Resolved' : 'Unresolved',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isResolved
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB91C1C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date Picker Field ─────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overall Uptime Chart ──────────────────────────────────────────────────────

class _OverallUptimeChart extends StatelessWidget {
  final List<SystemUptimeReport> data;

  const _OverallUptimeChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final avgUptime = data.isEmpty
        ? 100.0
        : data.map((d) => d.uptimePct).reduce((a, b) => a + b) / data.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2, width: 0.5),
        boxShadow: AppShadows.cardLight,
      ),
      child: Column(
        children: [
          Text(
            'Overall Uptime',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 50,
                    sections: [
                      PieChartSectionData(
                        value: avgUptime,
                        color: const Color(0xFF15803D),
                        radius: 22,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: 100 - avgUptime,
                        color: const Color(0xFFB91C1C),
                        radius: 22,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${avgUptime.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Uptime',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(const Color(0xFF15803D), 'Uptime'),
              const SizedBox(width: 20),
              _legendDot(const Color(0xFFB91C1C), 'Downtime'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Per-System Uptime Card ────────────────────────────────────────────────────

class _SystemUptimeCard extends StatelessWidget {
  final SystemUptimeReport report;

  const _SystemUptimeCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: Row(
        children: [
          // Small donut chart
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 1,
                    centerSpaceRadius: 16,
                    sections: [
                      PieChartSectionData(
                        value: report.uptimePct,
                        color: const Color(0xFF15803D),
                        radius: 8,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: report.downtimePct,
                        color: const Color(0xFFB91C1C),
                        radius: 8,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${report.uptimePct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.systemName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  report.daysWithIssues == 0
                      ? 'No issues in ${report.totalDays} days'
                      : '${report.daysWithIssues} day${report.daysWithIssues > 1 ? 's' : ''} with issues out of ${report.totalDays}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
