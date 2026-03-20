import 'package:flutter/material.dart';
import '../../services/fixer_reporter_service.dart';
import '../../theme/app_theme.dart';

class FixerReportersScreen extends StatefulWidget {
  const FixerReportersScreen({super.key});

  @override
  State<FixerReportersScreen> createState() => _FixerReportersScreenState();
}

class _FixerReportersScreenState extends State<FixerReportersScreen> {
  final _service = FixerReporterService();
  List<Map<String, dynamic>> _mappings = [];
  List<String> _allDepartments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchFixerReporters(),
        _service.fetchDepartments(),
      ]);
      setState(() {
        _mappings = (results[0] as List).cast<Map<String, dynamic>>();
        _allDepartments = (results[1] as List).cast<String>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (Navigator.canPop(context))
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.border2, width: 0.5),
                ),
                child: Icon(Icons.arrow_back_rounded,
                    size: 16, color: AppColors.textSecondary),
              ),
            ),
          Expanded(
            child: Text('Fixer Departments',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3)),
          ),
          IconButton(
            onPressed: () => _showCreateDialog(context),
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.add_rounded, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.dangerText),
            SizedBox(height: 12),
            Text('Failed to load mappings', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadData,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_mappings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree_outlined, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('No fixer-reporter mappings',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: Icon(Icons.add, size: 16),
              label: Text('Add Mapping'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _mappings.length,
        itemBuilder: (context, index) => _buildMappingCard(_mappings[index]),
      ),
    );
  }

  Widget _buildMappingCard(Map<String, dynamic> mapping) {
    final fixerDept = mapping['fixer_department'] as String;
    final reporterDepts = List<String>.from(mapping['reporter_departments'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEditDialog(context, fixerDept, reporterDepts),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(Icons.engineering_outlined,
                          size: 18, color: AppColors.accent),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fixer Team',
                              style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                          Text(fixerDept,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _confirmDelete(fixerDept),
                      icon: Icon(Icons.delete_outline, size: 18, color: AppColors.dangerText),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text('Handles Reporters From:',
                    style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: reporterDepts.map((dept) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface3,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border2, width: 0.5),
                      ),
                      child: Text(dept,
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    if (_allDepartments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No departments available'), backgroundColor: AppColors.dangerText),
      );
      return;
    }

    String? selectedFixer;
    final localSelectedReporters = <String>[];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Add Fixer-Reporter Team',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fixer Team (Department)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
                SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedFixer,
                      isExpanded: true,
                      hint: Text('Select fixer team', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                      items: _allDepartments
                          .where((d) => !_mappings.any((m) => m['fixer_department'] == d))
                          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      onChanged: (v) => setDlg(() => selectedFixer = v),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text('Reporter Departments',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
                SizedBox(height: 8),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _allDepartments.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                      itemBuilder: (ctx, i) {
                        final dept = _allDepartments[i];
                        final isSelected = localSelectedReporters.contains(dept);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setDlg(() {
                              if (v == true) {
                                localSelectedReporters.add(dept);
                              } else {
                                localSelectedReporters.remove(dept);
                              }
                            });
                          },
                          title: Text(dept, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.accent,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: selectedFixer == null || localSelectedReporters.isEmpty
                  ? null
                  : () async {
                      try {
                        await _service.createFixerReporter(
                          fixerDepartment: selectedFixer!,
                          reporterDepartments: localSelectedReporters,
                        );
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        _loadData();
                      } catch (e) {
                        if (dialogCtx.mounted) ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.dangerText));
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
              child: Text('Create', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, String fixerDept, List<String> currentReporters) async {
    if (_allDepartments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No departments available'), backgroundColor: AppColors.dangerText),
      );
      return;
    }

    final localSelectedReporters = List<String>.from(currentReporters);
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Edit $fixerDept',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reporter Departments',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
                SizedBox(height: 8),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _allDepartments.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                      itemBuilder: (ctx, i) {
                        final dept = _allDepartments[i];
                        final isSelected = localSelectedReporters.contains(dept);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setDlg(() {
                              if (v == true) {
                                localSelectedReporters.add(dept);
                              } else {
                                localSelectedReporters.remove(dept);
                              }
                            });
                          },
                          title: Text(dept, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.accent,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: loading || localSelectedReporters.isEmpty
                  ? null
                  : () async {
                      setDlg(() => loading = true);
                      try {
                        await _service.updateFixerReporter(
                          fixerDepartment: fixerDept,
                          reporterDepartments: localSelectedReporters,
                        );
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        _loadData();
                      } catch (e) {
                        setDlg(() => loading = false);
                        if (dialogCtx.mounted) ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.dangerText));
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
              child: loading
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                  : Text('Save', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String fixerDept) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete Mapping?'),
        content: Text('Are you sure you want to delete the mapping for "$fixerDept"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerText),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.deleteFixerReporter(fixerDept);
        _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.dangerText));
      }
    }
  }
}
