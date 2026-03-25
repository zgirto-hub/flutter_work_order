import 'package:flutter/material.dart';
import '../../services/department_route_service.dart';
import '../../services/department_service.dart';
import '../../models/department.dart';
import '../../theme/app_theme.dart';

class DepartmentRoutesScreen extends StatefulWidget {
  const DepartmentRoutesScreen({super.key});

  @override
  State<DepartmentRoutesScreen> createState() => _DepartmentRoutesScreenState();
}

class _DepartmentRoutesScreenState extends State<DepartmentRoutesScreen> {
  final _routeService = DepartmentRouteService();
  final _departmentService = DepartmentService();
  List<Map<String, dynamic>> _routes = [];
  List<Department> _departments = [];
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
        _routeService.fetchAllRoutes(),
        _departmentService.fetchDepartments(isActive: true),
      ]);
      setState(() {
        _routes = (results[0] as List).cast<Map<String, dynamic>>();
        _departments = (results[1] as List).cast<Department>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Group routes by source department: { sourceDeptId: [targetDeptId, ...] }
  Map<String, List<Map<String, String>>> get _groupedBySource {
    final Map<String, List<Map<String, String>>> grouped = {};
    for (final route in _routes) {
      final sourceId = route['source_department_id'] as String? ?? '';
      final sourceName = route['source_department_name'] as String? ?? '';
      final targetId = route['target_department_id'] as String? ?? '';
      final targetName = route['target_department_name'] as String? ?? '';
      if (sourceId.isNotEmpty && targetId.isNotEmpty) {
        grouped.putIfAbsent(sourceId, () => []).add({
          'source_name': sourceName,
          'target_id': targetId,
          'target_name': targetName,
        });
      }
    }
    return grouped;
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
            child: Text('Department Routing',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3)),
          ),
          IconButton(
            onPressed: () => _showAddDialog(context),
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
            Text('Failed to load routing rules', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadData,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    final grouped = _groupedBySource;

    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.alt_route_outlined, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('No routing rules configured',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            SizedBox(height: 4),
            Text('Add rules to control which departments can send WOs where',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: Icon(Icons.add, size: 16),
              label: Text('Add Routing Rule'),
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
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final sourceId = grouped.keys.elementAt(index);
          final targets = grouped[sourceId]!;
          final sourceName = targets.first['source_name'] ?? sourceId;
          return _buildRouteCard(sourceId, sourceName, targets);
        },
      ),
    );
  }

  Widget _buildRouteCard(String sourceId, String sourceName, List<Map<String, String>> targets) {
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
          onTap: () => _showEditDialog(context, sourceId, sourceName, targets),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 18, color: AppColors.accent),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sourceName,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          Text('Can send WOs to:',
                              style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${targets.length} target${targets.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.accent)),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: targets.map((t) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface3,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border2, width: 0.5),
                      ),
                      child: Text(t['target_name'] ?? '',
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

  Future<void> _showAddDialog(BuildContext context) async {
    if (_departments.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Need at least 2 departments to create routing rules.'), backgroundColor: AppColors.dangerText),
      );
      return;
    }

    Department? selectedSource;
    final selectedTargetIds = <String>[];
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final availableTargets = _departments.where((d) => d.id != selectedSource?.id).toList();
          return AlertDialog(
            backgroundColor: AppColors.bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text('Add Routing Rule',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Source Department',
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
                      child: DropdownButton<Department>(
                        value: selectedSource,
                        isExpanded: true,
                        hint: Text('Select source department', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                        items: _departments.map((d) {
                          return DropdownMenuItem(value: d, child: Text(d.name));
                        }).toList(),
                        onChanged: (v) => setDlg(() {
                          selectedSource = v;
                          selectedTargetIds.clear();
                        }),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('Target Departments',
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
                        itemCount: availableTargets.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                        itemBuilder: (ctx, i) {
                          final dept = availableTargets[i];
                          final isSelected = selectedTargetIds.contains(dept.id);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (v) {
                              setDlg(() {
                                if (v == true) {
                                  selectedTargetIds.add(dept.id);
                                } else {
                                  selectedTargetIds.remove(dept.id);
                                }
                              });
                            },
                            title: Text(dept.name, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
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
                onPressed: selectedSource == null || selectedTargetIds.isEmpty || loading
                    ? null
                    : () async {
                        setDlg(() => loading = true);
                        try {
                          await _routeService.setTargetDepartments(selectedSource!.id, selectedTargetIds);
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
                    : Text('Add', style: TextStyle(fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, String sourceId, String sourceName, List<Map<String, String>> currentTargets) async {
    final availableTargets = _departments.where((d) => d.id != sourceId).toList();
    final selectedTargetIds = currentTargets.map((t) => t['target_id']!).toList();
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Edit $sourceName Routes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Target Departments',
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
                      itemCount: availableTargets.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                      itemBuilder: (ctx, i) {
                        final dept = availableTargets[i];
                        final isSelected = selectedTargetIds.contains(dept.id);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setDlg(() {
                              if (v == true) {
                                selectedTargetIds.add(dept.id);
                              } else {
                                selectedTargetIds.remove(dept.id);
                              }
                            });
                          },
                          title: Text(dept.name, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
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
            TextButton(
              onPressed: () async {
                setDlg(() => loading = true);
                try {
                  await _routeService.setTargetDepartments(sourceId, []);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  _loadData();
                } catch (e) {
                  setDlg(() => loading = false);
                }
              },
              child: Text('Remove All', style: TextStyle(color: AppColors.dangerText)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      setDlg(() => loading = true);
                      try {
                        await _routeService.setTargetDepartments(sourceId, selectedTargetIds);
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
}
