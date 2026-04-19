import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../models/system_status_report.dart';
import '../services/system_status_service.dart';
import '../widgets/system_status_sheet.dart';

class SystemStatusScreen extends StatefulWidget {
  const SystemStatusScreen({super.key});

  @override
  State<SystemStatusScreen> createState() => _SystemStatusScreenState();
}

class _SystemStatusScreenState extends State<SystemStatusScreen>
    with WidgetsBindingObserver {
  final _service = SystemStatusService();
  bool _loading = true;
  List<SystemStatus> _systems = [];
  List<SystemStatusReport> _history = [];

  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  String get _userName => _email
      .split('@')
      .first
      .split('.')
      .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : s)
      .join(' ');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _load();
    }
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    }
  }

  // ── Report Issue ──────────────────────────────────────────────────────────────

  void _showDrillInSheet(SystemStatus system) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 350),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SystemStatusSheet(
        system: system,
        onReportSystemIssue: () {
          Navigator.pop(ctx);
          _showReportIssueSheet(system);
        },
        onShowIssueDetails: (report) {
          Navigator.pop(ctx);
          _showIssueDetailsSheet(report);
        },
        onEditIssue: (report) {
          Navigator.pop(ctx);
          _showEditIssueSheet(report);
        },
        onResolveIssue: (report) {
          Navigator.pop(ctx);
          _showResolveSheet(report);
        },
        onDeleteIssue: (report) {
          Navigator.pop(ctx);
          _confirmDelete(report);
        },
        onReportAssetIssue: (asset) {
          Navigator.pop(ctx);
          _showReportIssueSheet(system, asset: asset);
        },
        onChange: _load,
      ),
    );
  }

  void _showReportIssueSheet(SystemStatus system, {AssetStatusEntry? asset}) {
    if (asset != null && asset.hasIssue) {
      _showIssueDetailsSheet(asset.activeReport!);
      return;
    }
    if (asset == null && system.hasIssue) {
      _showIssueDetailsSheet(system.activeReport!);
      return;
    }

    DateTime selectedDate = DateTime.now();
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 350),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
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
                asset != null
                    ? '${system.systemName} \u{2192} ${asset.assetName}'
                    : system.systemName,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
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
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
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
                        assetId: asset?.assetId,
                      );
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _load();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Issue reported')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
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
                  child: const Text(
                    'Report Issue',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Issue Details ─────────────────────────────────────────────────────────

  void _showIssueDetailsSheet(SystemStatusReport report) {
    final isResolved = report.isResolved;
    final dotColor = isResolved
        ? const Color(0xFF15803D)
        : const Color(0xFFB91C1C);
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
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.assetName != null
                        ? '${report.systemName} \u{2192} ${report.assetName}'
                        : report.systemName,
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
            _detailRow(
              'Reported by',
              report.reportedByName.isNotEmpty
                  ? report.reportedByName
                  : report.reportedBy,
            ),
            if (isResolved) ...[
              _detailRow(
                'Resolved on',
                report.resolvedAt!.split('T').first,
              ),
              if (report.resolvedNotes.isNotEmpty)
                _detailRow('Resolve comment', report.resolvedNotes),
              if ((report.resolvedBy ?? '').isNotEmpty)
                _detailRow('Resolved by', report.resolvedBy!),
            ],
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
                // Resolve / Unresolve button
                Expanded(
                  child: isResolved
                      ? OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmUnresolve(report);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD97706),
                            side: const BorderSide(color: Color(0xFFD97706)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Unresolve',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showResolveSheet(report);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF15803D),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Resolve',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUnresolve(SystemStatusReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen issue?'),
        content: Text(
          'Reopen ${report.assetName != null ? '${report.systemName} \u{2192} ${report.assetName}' : report.systemName} on ${report.reportDate}? The resolve date and comment will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD97706),
            ),
            child: const Text('Unresolve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.unresolveIssue(reportId: report.id);
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Issue reopened')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ── Resolve Issue ─────────────────────────────────────────────────────────

  void _showResolveSheet(SystemStatusReport report) {
    final notesCtrl = TextEditingController();
    bool resolving = false;
    DateTime selectedResolveDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
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
                      color: Color(0xFF15803D),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Resolve Issue',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                report.assetName != null
                    ? '${report.systemName} \u{2192} ${report.assetName}'
                    : report.systemName,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: notesCtrl,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Describe how the issue was resolved...',
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
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              Text(
                'Resolve Date',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final reportDate =
                      DateTime.tryParse(report.reportDate) ?? DateTime(2024);
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedResolveDate,
                    firstDate: reportDate,
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setSheet(() => selectedResolveDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${selectedResolveDate.year}-${selectedResolveDate.month.toString().padLeft(2, '0')}-${selectedResolveDate.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: resolving
                      ? null
                      : () async {
                          final resolveDateStr =
                              '${selectedResolveDate.year}-${selectedResolveDate.month.toString().padLeft(2, '0')}-${selectedResolveDate.day.toString().padLeft(2, '0')}';
                          setSheet(() => resolving = true);
                          try {
                            await _service.resolveIssue(
                              reportId: report.id,
                              resolvedBy: _email,
                              resolvedNotes: notesCtrl.text.trim(),
                              resolvedAt: resolveDateStr,
                            );
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            _load();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Issue resolved')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setSheet(() => resolving = false);
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: resolving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Confirm Resolve',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Edit Issue ────────────────────────────────────────────────────────────

  void _showEditIssueSheet(SystemStatusReport report) {
    final notesController = TextEditingController(text: report.notes);
    DateTime selectedDate =
        DateTime.tryParse(report.reportDate) ?? DateTime.now();
    DateTime? selectedResolveDate =
        report.isResolved && report.resolvedAt != null
            ? DateTime.tryParse(report.resolvedAt!)
            : null;

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
            20,
            20,
            20,
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
                report.assetName != null
                    ? '${report.systemName} \u{2192} ${report.assetName}'
                    : report.systemName,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
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
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              if (report.isResolved) ...[
                Text(
                  'Resolve Date',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final initialResolveDate = selectedResolveDate != null &&
                            !selectedResolveDate!.isBefore(selectedDate)
                        ? selectedResolveDate!
                        : selectedDate;
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: initialResolveDate,
                      firstDate: selectedDate,
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setSheetState(() => selectedResolveDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border2),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          selectedResolveDate != null
                              ? '${selectedResolveDate!.year}-${selectedResolveDate!.month.toString().padLeft(2, '0')}-${selectedResolveDate!.day.toString().padLeft(2, '0')}'
                              : 'Select a resolve date',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final dateStr =
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                    final resolveDateStr = selectedResolveDate != null
                        ? '${selectedResolveDate!.year}-${selectedResolveDate!.month.toString().padLeft(2, '0')}-${selectedResolveDate!.day.toString().padLeft(2, '0')}'
                        : null;
                    try {
                      await _service.updateIssue(
                        reportId: report.id,
                        notes: notesController.text.trim(),
                        reportDate: dateStr,
                        resolvedAt: resolveDateStr,
                      );
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _load();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Issue updated')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
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
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Delete Issue',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Delete the issue report for ${report.assetName != null ? '${report.systemName} \u{2192} ${report.assetName}' : report.systemName} on ${report.reportDate}? This cannot be undone.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Issue deleted')));
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$e')));
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
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
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
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('$e')));
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
                          : const Text(
                              'Generate Report',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
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
                          ...reportData!.map(
                            (r) => _SystemUptimeCard(report: r),
                          ),
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
        automaticallyImplyLeading: false,
        leading: ModalRoute.of(context)?.isFirst == false
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(
              Icons.pie_chart_outline,
              color: AppColors.textSecondary,
              size: 20,
            ),
            tooltip: 'Uptime Report',
            onPressed: _showUptimeReportSheet,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.textSecondary, size: 20),
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
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 3.0,
                      ),
                      itemCount: _systems.length,
                      itemBuilder: (context, i) => _SystemCard(
                        system: _systems[i],
                        onTap: () => _showDrillInSheet(_systems[i]),
                      ),
                    ),
                    const SizedBox(height: 16),

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
                      const SizedBox(height: 8),
                      ..._history.map(
                        (r) => _HistoryCard(
                          report: r,
                          onEdit: () => _showEditIssueSheet(r),
                          onDelete: () => _confirmDelete(r),
                        ),
                      ),
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
  final VoidCallback onTap;

  const _SystemCard({
    required this.system,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isIssue = system.hasIssue;
    final statusColor =
        isIssue ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    final badge = system.assetIssuesCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border2, width: 0.5),
          boxShadow: AppShadows.cardLight,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                system.systemName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isIssue ? 'Issue' : 'OK',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
            if (badge) ...[
              const SizedBox(width: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '\u{26A0} ${system.assetIssuesCount}',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD97706),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
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
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isResolved
                  ? const Color(0xFF15803D)
                  : const Color(0xFFB91C1C),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        report.systemName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isResolved
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        isResolved ? 'Resolved' : 'Unresolved',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: isResolved
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      report.reportDate,
                      style: TextStyle(
                        fontSize: 10,
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
                                Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Color(0xFFB91C1C),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFB91C1C),
                                  ),
                                ),
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
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
                Icon(
                  Icons.calendar_today,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
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
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    final allOperational = report.daysWithIssues == 0 &&
        report.assets.every((a) => a.daysWithIssues == 0);

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        collapsedIconColor: AppColors.textTertiary,
        iconColor: AppColors.textSecondary,
        title: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border2, width: 0.5),
          ),
          child: Row(
            children: [
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
              Icon(
                Icons.expand_more,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
        children: [
          if (report.assets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No linked assets',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else if (allOperational)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'All assets operational for the period',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ...([...report.assets]..sort((a, b) => a.uptimePct.compareTo(b.uptimePct)))
                .map((a) => _AssetUptimeRow(asset: a)),
        ],
      ),
    );
  }
}

class _AssetUptimeRow extends StatelessWidget {
  final AssetUptimeReport asset;

  const _AssetUptimeRow({required this.asset});

  Color get _severityColor {
    if (asset.daysWithIssues == 0) return const Color(0xFF15803D);
    if (asset.uptimePct >= 95.0) return const Color(0xFFD97706);
    return const Color(0xFFB91C1C);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: _severityColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _severityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.assetName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${asset.role} · ${asset.site}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${asset.uptimePct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _severityColor,
            ),
          ),
        ],
      ),
    );
  }
}
