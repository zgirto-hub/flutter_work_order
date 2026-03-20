import 'package:flutter/material.dart';
import '../../services/fixer_reporter_service.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';

class FixerReportersScreen extends StatefulWidget {
  const FixerReportersScreen({super.key});

  @override
  State<FixerReportersScreen> createState() => _FixerReportersScreenState();
}

class _FixerReportersScreenState extends State<FixerReportersScreen> {
  final _service = FixerReporterService();
  List<Map<String, dynamic>> _mappings = [];
  List<AppUser> _fixers = [];
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
        _service.fetchFixerDepartments(),
        _service.fetchFixers(),
      ]);
      setState(() {
        _mappings = (results[0] as List).cast<Map<String, dynamic>>();
        _fixers = (results[1] as List).cast<AppUser>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, List<String>> get _groupedByFixer {
    final Map<String, List<String>> grouped = {};
    for (final mapping in _mappings) {
      final fixerEmail = mapping['users']?['email'] ?? '';
      final dept = mapping['department'] as String? ?? '';
      if (fixerEmail.isNotEmpty && dept.isNotEmpty) {
        grouped.putIfAbsent(fixerEmail, () => []).add(dept);
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
            child: Text('Fixer Departments',
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

    final grouped = _groupedByFixer;
    
    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.engineering_outlined, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('No fixer-department mappings',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddDialog(context),
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
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final email = grouped.keys.elementAt(index);
          final depts = grouped[email]!;
          return _buildFixerCard(email, depts);
        },
      ),
    );
  }

  Widget _buildFixerCard(String fixerEmail, List<String> departments) {
    final fixer = _fixers.firstWhere(
      (f) => f.email == fixerEmail,
      orElse: () => AppUser(id: '', email: fixerEmail, userType: UserType.fixer),
    );
    final name = fixer.fullName ?? fixerEmail.split('@').first;

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
          onTap: () => _showEditDialog(context, fixerEmail, departments),
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
                      child: Text(
                        name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          Text(fixerEmail,
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
                      child: Text('FIXER',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.accent)),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text('Assigned Departments:',
                    style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: departments.map((dept) {
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

  Future<void> _showAddDialog(BuildContext context) async {
    if (_fixers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fixers available. Create a fixer user first.'), backgroundColor: AppColors.dangerText),
      );
      return;
    }

    AppUser? selectedFixer;
    final selectedDepts = <String>[];
    final allDepts = ['Operations', 'ATC', 'Finance', 'NOTAM', 'MET', 'IT-Support', 'Helpdesk', 'General'];
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Add Fixer Department',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fixer',
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
                    child: DropdownButton<AppUser>(
                      value: selectedFixer,
                      isExpanded: true,
                      hint: Text('Select fixer', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                      items: _fixers.map((f) {
                        final name = f.fullName ?? f.email.split('@').first;
                        return DropdownMenuItem(value: f, child: Text(name));
                      }).toList(),
                      onChanged: (v) => setDlg(() => selectedFixer = v),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text('Departments',
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
                      itemCount: allDepts.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                      itemBuilder: (ctx, i) {
                        final dept = allDepts[i];
                        final isSelected = selectedDepts.contains(dept);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setDlg(() {
                              if (v == true) {
                                selectedDepts.add(dept);
                              } else {
                                selectedDepts.remove(dept);
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
              onPressed: selectedFixer == null || selectedDepts.isEmpty || loading
                  ? null
                  : () async {
                      setDlg(() => loading = true);
                      try {
                        await _service.setFixerDepartments(selectedFixer!.id, selectedDepts);
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
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, String fixerEmail, List<String> currentDepts) async {
    final fixer = _fixers.firstWhere(
      (f) => f.email == fixerEmail,
      orElse: () => AppUser(id: '', email: fixerEmail, userType: UserType.fixer),
    );
    final allDepts = ['Operations', 'ATC', 'Finance', 'NOTAM', 'MET', 'IT-Support', 'Helpdesk', 'General'];
    final selectedDepts = List<String>.from(currentDepts);
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Edit ${fixer.fullName ?? fixerEmail}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Departments',
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
                      itemCount: allDepts.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                      itemBuilder: (ctx, i) {
                        final dept = allDepts[i];
                        final isSelected = selectedDepts.contains(dept);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setDlg(() {
                              if (v == true) {
                                selectedDepts.add(dept);
                              } else {
                                selectedDepts.remove(dept);
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
            TextButton(
              onPressed: () async {
                setDlg(() => loading = true);
                try {
                  await _service.setFixerDepartments(fixer.id, []);
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
                        await _service.setFixerDepartments(fixer.id, selectedDepts);
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
