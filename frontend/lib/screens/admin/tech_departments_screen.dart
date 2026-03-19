import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/it_department_service.dart';
import '../../services/department_service.dart';
import '../../services/it_team_service.dart';
import '../../config.dart';
import '../../theme/app_theme.dart';

class TechDepartmentsScreen extends StatefulWidget {
  const TechDepartmentsScreen({super.key});

  @override
  State<TechDepartmentsScreen> createState() => _TechDepartmentsScreenState();
}

class _TechDepartmentsScreenState extends State<TechDepartmentsScreen> {
  final DepartmentService _departmentService = DepartmentService(); // ← Add this line
  List<String> _departments = [];
  bool _isLoading = false;
  
  // ... rest of your code
  final ItDepartmentService _service = ItDepartmentService();
  final DepartmentService _deptService = DepartmentService();
  final ItTeamService _itTeamService = ItTeamService();
  
  List<Map<String, dynamic>> _techs = [];
  
  List<String> _itTeams = [];
  Map<String, List<String>> _itTeamReporters = {};
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
    // Load all IT department reporters mappings
    final mappingsResult = await _service.getAllMappings();
    final mappings = mappingsResult['mappings'] as List? ?? [];
    
    // Build map of IT team -> reporter departments
    final Map<String, List<String>> reporters = {};
    for (var m in mappings) {
      final itDept = m['it_department'] as String;
      final reporter = m['reporter_department'] as String;
      reporters.putIfAbsent(itDept, () => []);
      reporters[itDept]!.add(reporter);
    }
    
    // Load departments from API - FIXED
    final deptNames = await _departmentService.fetchDepartments();
    // deptNames is already List<String> = ["IT", "HR", "Sales", etc.]
    
    // Load IT teams from API - CHECK WHAT getItTeams() RETURNS
    final itTeamNames = await _itTeamService.getItTeams();
    // If getItTeams returns List<String>, use directly
    // If it returns List<Map>, you need: 
    // final itTeamsResult = await _itTeamService.getItTeams();
    // final itTeamNames = itTeamsResult.map((t) => t['name'] as String).toList();
    
    // Load all techs from employees
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/employees?tech=true'),
    );
    
    List<Map<String, dynamic>> techs = [];
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final employees = data['employees'] as List? ?? [];
      techs = employees
          .where((e) => (e['user_type'] == 'tech' || e['user_type'] == 'admin'))
          .cast<Map<String, dynamic>>()
          .toList();
    }

    if (!mounted) return;
    
    setState(() {
      _techs = techs;
      _departments = deptNames..sort();
      _itTeams = List<String>.from(itTeamNames)..sort();
      _itTeamReporters = reporters;
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

  Future<void> _updateItTeam(String email, String itTeam) async {
    try {
      await _service.updateEmployeeItTeam(email, itTeam);
      await _loadData(); // Refresh after update
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('IT team updated'),
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
            content: Text('Failed to update IT team: $e'),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _toggleReporter(String itTeam, String reporter, bool add) async {
    try {
      if (add) {
        await _service.assignReporter(itTeam, reporter);
        setState(() {
          _itTeamReporters.putIfAbsent(itTeam, () => []);
          if (!_itTeamReporters[itTeam]!.contains(reporter)) {
            _itTeamReporters[itTeam]!.add(reporter);
          }
        });
      } else {
        await _service.removeReporter(itTeam, reporter);
        setState(() {
          _itTeamReporters[itTeam]?.remove(reporter);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  List<String> _getReporterDepartments(String itTeam) {
    return _itTeamReporters[itTeam] ?? [];
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
          'IT Team Assignments',
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: AppColors.dangerText),
                      SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _techs.isEmpty
                  ? Center(
                      child: Text(
                        'No tech users found',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: AppColors.accent,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _techs.length,
                        itemBuilder: (context, index) {
                          final tech = _techs[index];
                          return _TechCard(
                            tech: tech,
                            departments: _departments,
                            itTeams: _itTeams,
                            reporterDepartments: _getReporterDepartments(tech['it_team'] ?? ''),
                            onItTeamChanged: (team) => _updateItTeam(tech['email'] ?? '', team),
                            onReporterToggled: (reporter, add) {
                              final itTeam = tech['it_team'] ?? '';
                              if (itTeam.isNotEmpty) {
                                _toggleReporter(itTeam, reporter, add);
                              }
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

class _TechCard extends StatelessWidget {
  final Map<String, dynamic> tech;
  final List<String> departments;
  final List<String> itTeams;
  final List<String> reporterDepartments;
  final Function(String) onItTeamChanged;
  final Function(String, bool) onReporterToggled;

  const _TechCard({
    required this.tech,
    required this.departments,
    required this.itTeams,
    required this.reporterDepartments,
    required this.onItTeamChanged,
    required this.onReporterToggled,
  });

  @override
  Widget build(BuildContext context) {
    final email = tech['email'] ?? tech['full_name'] ?? 'Unknown';
    final name = tech['full_name'] ?? email;
    final itTeam = tech['it_team'] ?? '';

    // Filter out the IT team's own department from reporters
    final reporterOptions = departments
        .where((d) => d != itTeam)
        .toList();

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      color: AppColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.accentBg,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            
            // IT Team dropdown
            Text(
              'IT Team:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButton<String>(
                value: itTeams.contains(itTeam) ? itTeam : null,
                hint: Text('Select IT Team', style: TextStyle(color: AppColors.textTertiary)),
                isExpanded: true,
                underline: SizedBox(),
                dropdownColor: AppColors.bgSurface,
                items: itTeams
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) onItTeamChanged(value);
                },
              ),
            ),
            
            if (itTeam.isNotEmpty) ...[
              SizedBox(height: 16),
              Text(
                '$itTeam Reports Issues From:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reporterOptions.map((dept) {
                  final isChecked = reporterDepartments.contains(dept);
                  return FilterChip(
                    label: Text(dept),
                    selected: isChecked,
                    onSelected: (selected) => onReporterToggled(dept, selected),
                    selectedColor: AppColors.accentBg,
                    checkmarkColor: AppColors.accent,
                    backgroundColor: AppColors.bgSurface2,
                    labelStyle: TextStyle(
                      color: isChecked ? AppColors.accent : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                      color: isChecked ? AppColors.accent : AppColors.border,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
