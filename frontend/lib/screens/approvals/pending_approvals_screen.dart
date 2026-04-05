import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config.dart';
import '../../theme/app_theme.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  List<Map<String, dynamic>> _workOrders = [];
  bool _loading = true;
  String? _error;
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadEmailAndData();
  }

  Future<void> _loadEmailAndData() async {
    _email = Supabase.instance.client.auth.currentUser?.email ?? '';
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/work-orders/pending-approvals?email=${Uri.encodeComponent(_email)}'),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _workOrders =
              List<Map<String, dynamic>>.from(data['work_orders'] ?? []);
          _loading = false;
        });
      } else if (res.statusCode == 403) {
        setState(() {
          _error = 'You do not have approval permissions';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load pending approvals';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _approve(String woId, String sigId) async {
    try {
      await http.patch(
        Uri.parse('${AppConfig.baseUrl}/work-orders/$woId/signatures/$sigId?user_email=${Uri.encodeComponent(_email)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'approved', 'use_saved': true}),
      );
      setState(() {
        _workOrders.removeWhere((wo) => wo['id'] == woId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Approved'), backgroundColor: AppColors.closedText),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reject(String woId, String sigId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject Work Order'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Rejection reason',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('Reject', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;

    try {
      await http.patch(
        Uri.parse('${AppConfig.baseUrl}/work-orders/$woId/signatures/$sigId?user_email=${Uri.encodeComponent(_email)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'rejected', 'rejection_reason': reason}),
      );
      setState(() {
        _workOrders.removeWhere((wo) => wo['id'] == woId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rejected'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pending Approvals'),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red),
                      SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Colors.red)),
                    ],
                  ),
                )
              : _workOrders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: AppColors.textTertiary),
                          SizedBox(height: 16),
                          Text('No pending approvals',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.builder(
                        padding: EdgeInsets.all(12),
                        itemCount: _workOrders.length,
                        itemBuilder: (ctx, i) {
                          final wo = _workOrders[i];
                          final woId = wo['id']?.toString() ?? '';
                          final sigId =
                              wo['pending_signature_id']?.toString() ?? '';
                          return _ApprovalCard(
                            workOrder: wo,
                            onApprove: () => _approve(woId, sigId),
                            onReject: () => _reject(woId, sigId),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final Map<String, dynamic> workOrder;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.workOrder,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final tech = workOrder['assigned_technician'] as Map<String, dynamic>?;

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    workOrder['job_no'] ?? '',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.pendingText.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Pending',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.pendingText,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              workOrder['title'] ?? '',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.business, size: 14, color: AppColors.textTertiary),
                SizedBox(width: 4),
                Text(
                  workOrder['department_name'] ?? '',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            if (tech != null) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: AppColors.textTertiary),
                  SizedBox(width: 4),
                  Text(
                    tech['full_name'] ?? '',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                  ),
                  child: Text('Reject'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.closedText,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
