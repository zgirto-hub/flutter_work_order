import 'package:flutter/material.dart';
import '../../services/department_service.dart';
import '../../models/department.dart';
import '../../theme/app_theme.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  final _service = DepartmentService();
  List<Department> _departments = [];
  Map<String, int> _technicianCounts = {};
  Map<String, int> _workOrderCounts = {};
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
      final departments = await _service.fetchDepartments(isActive: true);
      
      // Load counts for all departments in parallel
      final technicianCounts = <String, int>{};
      final woCounts = <String, int>{};

      await Future.wait(departments.map((dept) async {
        final results = await Future.wait([
          _service.getTechnicianCount(dept.id),
          _service.getWorkOrderCount(dept.id),
        ]);
        technicianCounts[dept.id] = results[0];
        woCounts[dept.id] = results[1];
      }));
      
      setState(() {
        _departments = departments;
        _technicianCounts = technicianCounts;
        _workOrderCounts = woCounts;
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
            child: Text('Departments',
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
            Text(_error ?? 'Failed to load departments',
                style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadData,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_departments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business_outlined, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('No departments',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: Icon(Icons.add, size: 16),
              label: Text('Add Department'),
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
        itemCount: _departments.length,
        itemBuilder: (context, index) => _buildDepartmentCard(_departments[index]),
      ),
    );
  }

  Widget _buildDepartmentCard(Department department) {
    final techCount = _technicianCounts[department.id] ?? 0;
    final woCount = _workOrderCounts[department.id] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEditDialog(context, department),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.business_outlined,
                      size: 20, color: AppColors.accent),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(department.name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      SizedBox(height: 2),
                      Text(
                          '$techCount user${techCount == 1 ? '' : 's'} • $woCount work order${woCount == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _confirmDelete(department, techCount, woCount),
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: AppColors.dangerText),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: AppColors.bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text('Add Department',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Department Name',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
                SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter department name',
                      hintStyle: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setDlg(() {}),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: Text('Cancel')),
              ElevatedButton(
                onPressed: loading || nameCtrl.text.trim().isEmpty
                    ? null
                    : () async {
                        setDlg(() => loading = true);
                        try {
                          await _service.createDepartment(nameCtrl.text.trim());
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          _loadData();
                        } catch (e) {
                          setDlg(() => loading = false);
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: AppColors.dangerText));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                child: loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white))
                    : Text('Create', style: TextStyle(fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, Department department) async {
    final nameCtrl = TextEditingController(text: department.name);
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: AppColors.bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text('Edit Department',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Department Name',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
                SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter new name',
                      hintStyle: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setDlg(() {}),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: Text('Cancel')),
              ElevatedButton(
                onPressed: loading ||
                        nameCtrl.text.trim().isEmpty ||
                        nameCtrl.text.trim() == department.name
                    ? null
                    : () async {
                        setDlg(() => loading = true);
                        try {
                          await _service.updateDepartment(
                            department.id,
                            name: nameCtrl.text.trim(),
                          );
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          _loadData();
                        } catch (e) {
                          setDlg(() => loading = false);
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: AppColors.dangerText));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                child: loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white))
                    : Text('Update', style: TextStyle(fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(Department department, int techCount, int woCount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete Department?'),
        content: Text('Are you sure you want to delete "${department.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
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
        await _service.deleteDepartment(department.id);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.dangerText));
        }
      }
    }
  }
}
