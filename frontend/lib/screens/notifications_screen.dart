import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import 'Work_Orders/add_work_order.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService();
  final WorkOrderService _woService = WorkOrderService();

  bool _loading = true;
  bool _markingAll = false;
  bool _clearingAll = false;
  bool _navigatingToWorkOrder = false;
  List<AppNotification> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _service.fetchNotifications(unreadOnly: false, limit: 100);
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    await _service.markAllRead();
    if (!mounted) return;
    setState(() {
      _markingAll = false;
      _items = _items
          .map((n) => n.isUnread
              ? AppNotification(
                  id: n.id,
                  userEmail: n.userEmail,
                  kind: n.kind,
                  title: n.title,
                  body: n.body,
                  data: n.data,
                  sourceType: n.sourceType,
                  sourceId: n.sourceId,
                  readAt: DateTime.now(),
                  createdAt: n.createdAt,
                )
              : n)
          .toList();
    });
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty || _clearingAll) return;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('Clear all notifications'),
            content: Text(
              'This will remove all notifications from your inbox.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Clear all',
                  style: TextStyle(color: AppColors.dangerText),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    setState(() => _clearingAll = true);
    try {
      await _service.clearAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear notifications: $e'),
          backgroundColor: AppColors.dangerText,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _clearingAll = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _items = [];
      _clearingAll = false;
      _markingAll = false;
    });
  }

  Future<void> _openNotification(AppNotification n) async {
    if (_navigatingToWorkOrder) return;
    _navigatingToWorkOrder = true;

    try {
      if (n.isUnread) {
        await _service.markRead(n.id);
        if (mounted) {
          setState(() {
            _items = _items
                .map((x) => x.id == n.id
                    ? AppNotification(
                        id: x.id,
                        userEmail: x.userEmail,
                        kind: x.kind,
                        title: x.title,
                        body: x.body,
                        data: x.data,
                        sourceType: x.sourceType,
                        sourceId: x.sourceId,
                        readAt: DateTime.now(),
                        createdAt: x.createdAt,
                      )
                    : x)
                .toList();
          });
        }
      }

      final workOrderId = (n.data['work_order_id'] ?? '').toString();
      if (workOrderId.isEmpty) return;

      final wo = await _woService.fetchWorkOrderById(workOrderId);
      if (!mounted) return;
      if (wo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Related work order not found'),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddWorkOrderScreen(workOrder: wo, initialTab: 1),
        ),
      );
    } finally {
      _navigatingToWorkOrder = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((n) => n.isUnread).length;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: AppColors.border2, width: 0.5),
                      ),
                      child: Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    TextButton(
                      onPressed: _markingAll || _clearingAll ? null : _markAllRead,
                      child: _markingAll
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.textSecondary,
                              ),
                            )
                          : const Text('Mark all read'),
                    ),
                  if (_items.isNotEmpty)
                    TextButton(
                      onPressed: _clearingAll || _markingAll ? null : _clearAll,
                      child: _clearingAll
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.textSecondary,
                              ),
                            )
                          : Text(
                              'Clear all',
                              style: TextStyle(color: AppColors.dangerText),
                            ),
                    ),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                            'No notifications',
                            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accent,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final n = _items[i];
                              return GestureDetector(
                                onTap: () => _openNotification(n),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.bgSurface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: n.isUnread ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(top: 6, right: 10),
                                        decoration: BoxDecoration(
                                          color: n.isUnread ? AppColors.accent : Colors.transparent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              n.title,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              n.body,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                                height: 1.4,
                                              ),
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
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
