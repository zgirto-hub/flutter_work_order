import 'package:flutter/material.dart';
import '../../services/department_service.dart';
import '../../theme/app_theme.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  final DepartmentService _service = DepartmentService();
  
  List<Map<String, dynamic>> _departments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final depts = await _service.getDepartments();
      if (!mounted) return;
      setState(() {
        _departments = depts;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Add Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Department name',
            hintStyle: TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.bgSurface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _createDepartment(name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(String id, String currentName) async {
    final controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Edit Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Department name',
            hintStyle: TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.bgSurface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _updateDepartment(id, name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'Are you sure you want to delete "$name"?\n\nThis cannot be undone.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dangerText,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteDepartment(id);
    }
  }

  Future<void> _createDepartment(String name) async {
    try {
      await _service.createDepartment(name);
      await _loadDepartments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Department added'),
            backgroundColor: AppColors.closedText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _updateDepartment(String id, String name) async {
    try {
      await _service.updateDepartment(id, name);
      await _loadDepartments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Department updated'),
            backgroundColor: AppColors.closedText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _deleteDepartment(String id) async {
    try {
      await _service.deleteDepartment(id);
      await _loadDepartments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Department deleted'),
            backgroundColor: AppColors.closedText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manage Departments',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: AppColors.accent),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: AppColors.dangerText),
                      SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDepartments,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _departments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.business_outlined, size: 64, color: AppColors.textTertiary),
                          SizedBox(height: 16),
                          Text('No departments found', style: TextStyle(color: AppColors.textSecondary)),
                          SizedBox(height: 8),
                          TextButton.icon(
                            icon: Icon(Icons.add),
                            label: Text('Add Department'),
                            onPressed: _showAddDialog,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDepartments,
                      color: AppColors.accent,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _departments.length,
                        itemBuilder: (context, index) {
                          final dept = _departments[index];
                          final name = dept['name'] as String;
                          final id = dept['id'] as String;
                          
                          return Container(
                            margin: EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.accentBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.business, color: AppColors.accent, size: 20),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.textTertiary),
                                    onPressed: () => _showEditDialog(id, name),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 20, color: AppColors.dangerText),
                                    onPressed: () => _showDeleteDialog(id, name),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
