import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/user_service.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _userService = UserService();
  List<AppUser> _users = [];
  Map<String, String> _departments = {}; // name → id
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _filterRole = 'all';

  // T013: Approval role state
  int? selectedApprovalLevel;
  List<String> selectedApprovalDepts = [];

  String _approvalLevelToString(int? level) {
    if (level == null) return 'none';
    if (level == 1) return 'supervisor';
    if (level == 2) return 'superintendent';
    return 'none';
  }

  int? _stringToApprovalLevel(String? value) {
    if (value == 'supervisor') return 1;
    if (value == 'superintendent') return 2;
    return null;
  }

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
        _userService.fetchUsers(),
        _userService.fetchDepartmentsWithIds(),
      ]);
      setState(() {
        _users = results[0] as List<AppUser>;
        _departments = results[1] as Map<String, String>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<AppUser> get _filteredUsers {
    return _users.where((user) {
      final matchesSearch = _searchQuery.isEmpty ||
          user.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (user.fullName ?? '')
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      final matchesRole =
          _filterRole == 'all' || user.userTypeString == _filterRole;
      return matchesSearch && matchesRole;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilters(),
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
            child: Text('User Management',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3)),
          ),
          IconButton(
            onPressed: () => _showCreateUserDialog(context),
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(9),
              ),
              child:
                  Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: AppColors.textTertiary),
                  prefixIcon: Icon(Icons.search,
                      size: 16, color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterRole,
                icon: Icon(Icons.expand_more,
                    size: 18, color: AppColors.textTertiary),
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                dropdownColor: AppColors.bgSurface,
                items: [
                  DropdownMenuItem(value: 'all', child: Text('All roles')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(
                      value: 'technician', child: Text('Technician')),
                  DropdownMenuItem(value: 'reporter', child: Text('Reporter')),
                ],
                onChanged: (v) => setState(() => _filterRole = v ?? 'all'),
              ),
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
            Text('Failed to load users',
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
    if (_filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('No users found',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filteredUsers.length,
        itemBuilder: (context, index) => _buildUserCard(_filteredUsers[index]),
      ),
    );
  }

  Widget _buildUserCard(AppUser user) {
    final initials = (user.fullName ?? user.email.split('@').first)
        .substring(0, 1)
        .toUpperCase();
    final roleColor = switch (user.userType) {
      UserType.admin => AppColors.accent,
      UserType.technician => AppColors.pendingText,
      _ => AppColors.closedText,
    };
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
          onTap: () => _showUserDetailsDialog(context, user),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: roleColor.withValues(alpha: 0.15),
                  child: Text(initials,
                      style: TextStyle(
                          color: roleColor, fontWeight: FontWeight.w600)),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName ?? 'Unknown',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      SizedBox(height: 2),
                      Text(user.email,
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(user.userTypeString.toUpperCase(),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: roleColor)),
                    ),
                    if (user.approvalLevel != null) ...[
                      SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: user.approvalLevel == 1
                              ? Color(0xFFFEF3C7)
                              : Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          user.approvalLevel == 1
                              ? 'Supervisor'
                              : 'Superintendent',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: user.approvalLevel == 1
                                ? Color(0xFFD97706)
                                : Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                    if (user.departments.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(user.departments.first,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.textTertiary)),
                    ],
                  ],
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    size: 16, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateUserDialog(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    String selectedRole = 'reporter';
    String? selectedDept;
    bool loading = false;
    bool obscurePass = true;
    bool obscureConfirmPass = true;
    String? passwordError;

    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Create User',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildField('Email', emailCtrl, TextInputType.emailAddress),
                SizedBox(height: 12),
                _buildField('Password', passCtrl, TextInputType.visiblePassword,
                    obscure: true,
                    obscureState: obscurePass,
                    onToggleObscure: () =>
                        setDlg(() => obscurePass = !obscurePass)),
                SizedBox(height: 12),
                _buildField('Confirm Password', confirmPassCtrl,
                    TextInputType.visiblePassword,
                    obscure: true,
                    obscureState: obscureConfirmPass,
                    onToggleObscure: () =>
                        setDlg(() => obscureConfirmPass = !obscureConfirmPass)),
                if (passwordError != null) ...[
                  SizedBox(height: 4),
                  Text(passwordError!,
                      style:
                          TextStyle(fontSize: 11, color: AppColors.dangerText)),
                ],
                SizedBox(height: 12),
                _buildField('Full Name', nameCtrl, TextInputType.name),
                SizedBox(height: 12),
                _buildField('Mobile', mobileCtrl, TextInputType.phone),
                SizedBox(height: 12),
                Text('Role',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
                SizedBox(height: 6),
                Row(
                  children: ['reporter', 'technician', 'admin'].map((role) {
                    final isSel = selectedRole == role;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setDlg(() => selectedRole = role),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin:
                              EdgeInsets.only(right: role != 'admin' ? 6 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                isSel ? AppColors.accent : AppColors.bgSurface2,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: isSel
                                    ? AppColors.accent
                                    : AppColors.border2,
                                width: 0.5),
                          ),
                          child: Center(
                              child: Text(
                                  role[0].toUpperCase() + role.substring(1),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isSel
                                          ? Colors.white
                                          : AppColors.textSecondary))),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                Text('Department',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
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
                      value: selectedDept,
                      isExpanded: true,
                      hint: Text('Select department',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textTertiary)),
                      items: _departments.keys
                          .map((name) =>
                              DropdownMenuItem(value: name, child: Text(name)))
                          .toList(),
                      onChanged: (v) => setDlg(() => selectedDept = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx, false),
                child: Text('Cancel')),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (emailCtrl.text.isEmpty ||
                          passCtrl.text.isEmpty ||
                          nameCtrl.text.isEmpty) return;
                      if (passCtrl.text != confirmPassCtrl.text) {
                        setDlg(() => passwordError = 'Passwords do not match');
                        return;
                      }
                      setDlg(() {
                        passwordError = null;
                        loading = true;
                      });
                      try {
                        final deptId = selectedDept != null
                            ? _departments[selectedDept]
                            : null;
                        await _userService.createUser(
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text,
                          userType: selectedRole,
                          fullName: nameCtrl.text.trim(),
                          mobile: mobileCtrl.text.trim(),
                          departmentId: deptId,
                        );
                        if (mounted) Navigator.pop(ctx, true);
                        _loadData();
                      } catch (e) {
                        setDlg(() => loading = false);
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppColors.dangerText));
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white),
              child: loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white))
                  : Text('Create', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
      String label, TextEditingController ctrl, TextInputType type,
      {bool obscure = false,
      bool? obscureState,
      VoidCallback? onToggleObscure}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary)),
        SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: TextField(
            controller: ctrl,
            obscureText: obscureState ?? obscure,
            keyboardType: type,
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: onToggleObscure != null
                  ? IconButton(
                      icon: Icon(
                        (obscureState ?? obscure)
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                      onPressed: onToggleObscure,
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showResetPasswordDialog(
      BuildContext context, AppUser user) async {
    final passCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool loading = false;
    bool obscurePass = true;
    bool obscureConfirmPass = true;
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Reset Password',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set a new password for ${user.fullName ?? user.email}',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              SizedBox(height: 16),
              _buildField(
                  'New Password', passCtrl, TextInputType.visiblePassword,
                  obscure: true,
                  obscureState: obscurePass,
                  onToggleObscure: () =>
                      setDlg(() => obscurePass = !obscurePass)),
              SizedBox(height: 12),
              _buildField('Confirm Password', confirmPassCtrl,
                  TextInputType.visiblePassword,
                  obscure: true,
                  obscureState: obscureConfirmPass,
                  onToggleObscure: () =>
                      setDlg(() => obscureConfirmPass = !obscureConfirmPass)),
              if (errorText != null) ...[
                SizedBox(height: 8),
                Text(errorText!,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.dangerText)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: Text('Cancel')),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (passCtrl.text.isEmpty) {
                        setDlg(() => errorText = 'Password cannot be empty');
                        return;
                      }
                      if (passCtrl.text.length < 6) {
                        setDlg(() => errorText =
                            'Password must be at least 6 characters');
                        return;
                      }
                      if (passCtrl.text != confirmPassCtrl.text) {
                        setDlg(() => errorText = 'Passwords do not match');
                        return;
                      }
                      setDlg(() {
                        errorText = null;
                        loading = true;
                      });
                      try {
                        await _userService.resetPassword(
                          userId: user.id,
                          newPassword: passCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Password reset successfully'),
                                backgroundColor: AppColors.closedText),
                          );
                        }
                      } catch (e) {
                        setDlg(() {
                          errorText = e.toString();
                          loading = false;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white),
              child: loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white))
                  : Text('Reset', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUserDetailsDialog(
      BuildContext context, AppUser user) async {
    final nameCtrl = TextEditingController(text: user.fullName);
    final mobileCtrl = TextEditingController(text: user.mobile);
    String selectedRole = user.userTypeString;
    String? selectedDept =
        user.departments.isNotEmpty ? user.departments.first : null;
    List<String>? selectedScreens = user.allowedScreens;
    bool loading = false;
    bool deleting = false;

    // T013: Initialize approval role state from user
    int? initialApprovalLevel = user.approvalLevel;
    List<String> initialApprovalDepts = [];

    // If user is supervisor, we need to fetch their departments
    if (user.approvalLevel == 1) {
      try {
        final depts = await _userService.getTechnicianDepartments(user.id);
        initialApprovalDepts = depts;
      } catch (_) {
        initialApprovalDepts = [];
      }
    }

    int? selectedApprovalLevel = initialApprovalLevel;
    List<String> selectedApprovalDepts = List.from(initialApprovalDepts);

    const screenOptions = [
      ('files', 'Files'),
      ('reports', 'Reports'),
      ('calendar', 'Calendar'),
      ('doc_registry', 'Doc Registry'),
      ('payment_cert', 'Payment Cert'),
      ('system_status', 'System Status'),
      ('activity_log', 'Activity Log'),
      ('notifications', 'Notifications'),
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Text('User Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (user.isActive
                          ? AppColors.closedText
                          : AppColors.dangerText)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(user.isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: user.isActive
                            ? AppColors.closedText
                            : AppColors.dangerText)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
                SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(user.email,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
                SizedBox(height: 12),
                _buildField('Full Name', nameCtrl, TextInputType.name),
                SizedBox(height: 12),
                _buildField('Mobile', mobileCtrl, TextInputType.phone),
                SizedBox(height: 12),
                Text('Role',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
                SizedBox(height: 6),
                Row(
                  children: ['reporter', 'technician', 'admin'].map((role) {
                    final isSel = selectedRole == role;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setDlg(() => selectedRole = role),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin:
                              EdgeInsets.only(right: role != 'admin' ? 6 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                isSel ? AppColors.accent : AppColors.bgSurface2,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: isSel
                                    ? AppColors.accent
                                    : AppColors.border2,
                                width: 0.5),
                          ),
                          child: Center(
                              child: Text(
                                  role[0].toUpperCase() + role.substring(1),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isSel
                                          ? Colors.white
                                          : AppColors.textSecondary))),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 12),
                Text('Department',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
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
                      value: selectedDept,
                      isExpanded: true,
                      hint: Text('Select department',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textTertiary)),
                      items: _departments.keys
                          .map((name) =>
                              DropdownMenuItem(value: name, child: Text(name)))
                          .toList(),
                      onChanged: (v) => setDlg(() => selectedDept = v),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                // T013: Approval Role Section
                Text('Approval Role',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary)),
                SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final isOwnUser = Supabase
                            .instance.client.auth.currentUser?.email
                            ?.toLowerCase() ==
                        user.email.toLowerCase();
                    if (isOwnUser) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          user.approvalLevel != null
                              ? (user.approvalLevel == 1
                                  ? 'Supervisor'
                                  : user.approvalLevel == 2
                                      ? 'Superintendent'
                                      : 'None')
                              : 'None',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface2,
                            borderRadius: BorderRadius.circular(9),
                            border:
                                Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _approvalLevelToString(selectedApprovalLevel),
                              isExpanded: true,
                              items: [
                                DropdownMenuItem(
                                    value: 'none', child: Text('None')),
                                DropdownMenuItem(
                                    value: 'supervisor',
                                    child: Text('Supervisor')),
                                DropdownMenuItem(
                                    value: 'superintendent',
                                    child: Text('Superintendent')),
                              ],
                              onChanged: (v) => setDlg(() {
                                selectedApprovalLevel =
                                    _stringToApprovalLevel(v);
                                if (selectedApprovalLevel == 1) {
                                  selectedApprovalDepts = [];
                                }
                              }),
                            ),
                          ),
                        ),
                        if (selectedApprovalLevel == 1) ...[
                          SizedBox(height: 8),
                          Text('Supervisor Departments',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textTertiary)),
                          SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _departments.keys.map((deptName) {
                              final isSel = selectedApprovalDepts
                                  .contains(_departments[deptName]);
                              return FilterChip(
                                label: Text(deptName,
                                    style: TextStyle(fontSize: 11)),
                                selected: isSel,
                                onSelected: (selected) {
                                  setDlg(() {
                                    final deptId = _departments[deptName];
                                    if (deptId != null) {
                                      if (selected) {
                                        selectedApprovalDepts = [
                                          ...selectedApprovalDepts,
                                          deptId
                                        ];
                                      } else {
                                        selectedApprovalDepts =
                                            selectedApprovalDepts
                                                .where((id) => id != deptId)
                                                .toList();
                                      }
                                    }
                                  });
                                },
                                selectedColor:
                                    AppColors.accent.withValues(alpha: 0.2),
                                checkmarkColor: AppColors.accent,
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Text('Screen Access',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textTertiary)),
                    Spacer(),
                    if (selectedScreens != null)
                      GestureDetector(
                        onTap: () => setDlg(() => selectedScreens = null),
                        child: Text('Reset to all',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.accent)),
                      ),
                  ],
                ),
                SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Column(
                    children: screenOptions.map((entry) {
                      final key = entry.$1;
                      final label = entry.$2;
                      final isOn = selectedScreens == null ||
                          selectedScreens!.contains(key);
                      return _ScreenToggleRow(
                        label: label,
                        value: isOn,
                        onChanged: (val) => setDlg(() {
                          if (selectedScreens == null) {
                            selectedScreens = screenOptions
                                .map((e) => e.$1)
                                .where((k) => k != key)
                                .toList();
                          } else if (val) {
                            selectedScreens = [...selectedScreens!, key];
                          } else {
                            selectedScreens = selectedScreens!
                                .where((k) => k != key)
                                .toList();
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (user.isActive)
              TextButton(
                onPressed: loading
                    ? null
                    : () async {
                        final confirm = await showDialog<bool>(
                          context: ctx,
                          builder: (_) => AlertDialog(
                            backgroundColor: AppColors.bgSurface,
                            title: Text('Deactivate User?'),
                            content: Text(
                                'This will prevent the user from signing in.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.dangerText),
                                child: Text('Deactivate'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          setDlg(() => deleting = true);
                          try {
                            await _userService.deactivateUser(user.id);
                            if (mounted) Navigator.pop(ctx);
                            _loadData();
                          } catch (e) {
                            setDlg(() => deleting = false);
                          }
                        }
                      },
                child: deleting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5))
                    : Text('Deactivate',
                        style: TextStyle(color: AppColors.dangerText)),
              )
            else
              TextButton(
                onPressed: loading
                    ? null
                    : () async {
                        setDlg(() => loading = true);
                        try {
                          await _userService.activateUser(user.id);
                          if (mounted) Navigator.pop(ctx);
                          _loadData();
                        } catch (e) {
                          setDlg(() => loading = false);
                        }
                      },
                child: Text('Activate',
                    style: TextStyle(color: AppColors.closedText)),
              ),
            TextButton(
              onPressed: loading
                  ? null
                  : () => _showResetPasswordDialog(context, user),
              child: Text('Reset Password',
                  style: TextStyle(color: AppColors.pendingText)),
            ),
            TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx, false),
                child: Text('Cancel')),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      setDlg(() => loading = true);
                      try {
                        final deptId = selectedDept != null
                            ? _departments[selectedDept]
                            : null;
                        await _userService.changeUserRole(
                          userId: user.id,
                          userType: selectedRole,
                        );
                        await _userService.updateUser(
                          userId: user.id,
                          fullName: nameCtrl.text.trim(),
                          mobile: mobileCtrl.text.trim(),
                          departmentId: deptId,
                        );
                        await _userService.updateScreenPermissions(
                            user.id, selectedScreens);
                        // T013: Update approval role
                        await _userService.updateApprovalRole(
                          userId: user.id,
                          approvalLevel: selectedApprovalLevel,
                          departmentIds: selectedApprovalLevel == 1
                              ? selectedApprovalDepts
                              : [],
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadData();
                      } catch (e) {
                        setDlg(() => loading = false);
                        if (ctx.mounted)
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppColors.dangerText));
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white),
              child: loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white))
                  : Text('Save', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ScreenToggleRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
