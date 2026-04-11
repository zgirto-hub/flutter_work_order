import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../../models/activity_log_entry.dart';
import '../../services/activity_log_service.dart';
import '../../theme/app_theme.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _service = ActivityLogService();
  final _scrollController = ScrollController();
  List<ActivityLogEntry> _logs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _filter = 'all';
  static const _pageSize = 50;

  static const _filters = [
    ('all', 'All'),
    ('work_order', 'Work orders'),
    ('file', 'Files'),
    ('auth', 'Auth'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasMore = true;
    });
    try {
      final logs = await _service.fetchLogs(
        category: _filter == 'all' ? null : _filter,
        limit: _pageSize,
        offset: 0,
      );
      if (mounted) {
        setState(() {
          _logs = logs;
          _hasMore = logs.length >= _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to load: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final logs = await _service.fetchLogs(
        category: _filter == 'all' ? null : _filter,
        limit: _pageSize,
        offset: _logs.length,
      );
      if (mounted) {
        setState(() {
          _logs.addAll(logs);
          _hasMore = logs.length >= _pageSize;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    // Group logs by date label
    final grouped = groupBy<ActivityLogEntry, String>(
      _logs, (e) => e.formattedDate,
    );

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (ModalRoute.of(context)?.isFirst == false) ...[
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface2,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: AppColors.border2, width: 0.5),
                            ),
                            child: Icon(Icons.arrow_back_rounded,
                                size: 16, color: AppColors.textSecondary),
                          ),
                        ),
                        SizedBox(width: 12),
                      ],
                      Text('Activity log',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3)),
                    ],
                  ),
                  SizedBox(height: 10),
                  // Filter chips
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _filters.map((f) {
                        final isActive = _filter == f.$1;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _filter = f.$1);
                            _load();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.accent
                                  : AppColors.bgSurface2,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive
                                    ? AppColors.accent
                                    : AppColors.border2,
                                width: 0.5,
                              ),
                            ),
                            child: Text(f.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isActive
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                )),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(height: 10),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── Body ──────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2))
                  : _logs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_rounded,
                                  size: 44, color: AppColors.bgSurface3),
                              SizedBox(height: 12),
                              Text('No activity found',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textTertiary)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accent,
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                            children: [
                              ...grouped.entries.map((entry) {
                                final dayLogs = entry.value;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 10, top: 8),
                                      child: Row(
                                        children: [
                                          Expanded(child: Divider(
                                              height: 1, thickness: 0.5,
                                              color: AppColors.border2)),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.bgSurface2,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: AppColors.border2,
                                                    width: 0.5),
                                              ),
                                              child: Text(entry.key,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors
                                                          .textSecondary)),
                                            ),
                                          ),
                                          Expanded(child: Divider(
                                              height: 1, thickness: 0.5,
                                              color: AppColors.border2)),
                                        ],
                                      ),
                                    ),
                                    ...dayLogs.map((log) =>
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: _ActivityLogCard(entry: log),
                                        )),
                                    SizedBox(height: 4),
                                  ],
                                );
                              }),
                              if (_loadingMore)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              if (!_hasMore && _logs.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: Text('No more activity',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textTertiary)),
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}


// ── Activity log card widget ──────────────────────────────────────────────────

class _ActivityLogCard extends StatelessWidget {
  final ActivityLogEntry entry;

  const _ActivityLogCard({required this.entry});

  IconData get _icon {
    switch (entry.action) {
      case 'deleted':    return Icons.delete_outline_rounded;
      case 'uploaded':   return Icons.upload_file_outlined;
      case 'shared':     return Icons.share_outlined;
      case 'closed':     return Icons.check_circle_outline_rounded;
      case 'signed_in':  return Icons.login_rounded;
      case 'signed_out': return Icons.logout_rounded;
      case 'created':    return Icons.add_circle_outline_rounded;
      case 'pdf_exported': return Icons.picture_as_pdf_outlined;
      case 'update_checked': return Icons.system_update_outlined;
      default:           return Icons.edit_outlined;
    }
  }

  Color get _iconBg {
    switch (entry.action) {
      case 'deleted':    return const Color(0xFFFCEBEB);
      case 'uploaded':   return AppColors.accentBg;
      case 'shared':     return const Color(0xFFE8F0FB);
      case 'closed':     return const Color(0xFFDCFCE7);
      case 'signed_in':  return AppColors.bgSurface2;
      case 'signed_out': return AppColors.bgSurface2;
      case 'created':    return const Color(0xFFEAF3DE);
      default:           return const Color(0xFFE8F0FB);
    }
  }

  Color get _iconFg {
    switch (entry.action) {
      case 'deleted':    return const Color(0xFFA32D2D);
      case 'uploaded':   return AppColors.accent;
      case 'shared':     return const Color(0xFF185FA5);
      case 'closed':     return AppColors.closedText;
      case 'signed_in':  return AppColors.textSecondary;
      case 'signed_out': return AppColors.textSecondary;
      case 'created':    return const Color(0xFF3B6D11);
      default:           return const Color(0xFF185FA5);
    }
  }

  Color get _categoryBg {
    switch (entry.category) {
      case 'work_order': return const Color(0xFFE8F0FB);
      case 'document':   return AppColors.accentBg;
      case 'folder':     return AppColors.bgSurface2;
      default:           return AppColors.bgSurface2;
    }
  }

  Color get _categoryFg {
    switch (entry.category) {
      case 'work_order': return const Color(0xFF185FA5);
      case 'document':   return const Color(0xFF993C1D);
      case 'folder':     return AppColors.textSecondary;
      default:           return AppColors.textSecondary;
    }
  }

  String get _categoryLabel => entry.category.replaceAll('_', ' ');

  Color get _avatarBg {
    const colors = [
      Color(0xFFEEEDFE), Color(0xFFE1F5EE),
      Color(0xFFF5EBE6), Color(0xFFE8F0FB),
    ];
    return colors[entry.userName.hashCode.abs() % colors.length];
  }

  Color get _avatarFg {
    const colors = [
      Color(0xFF3C3489), Color(0xFF085041),
      Color(0xFF993C1D), Color(0xFF0C447C),
    ];
    return colors[entry.userName.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, size: 18, color: _iconFg),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: user + time
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _avatarBg,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(entry.initials,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: _avatarFg)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(entry.userName,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                      Text(entry.formattedTime,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Description
                  Text(entry.description,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary)),
                  // Target / detail
                  if (entry.targetLabel != null &&
                      entry.targetLabel!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        entry.targetLabel,
                        if (entry.detail != null && entry.detail!.isNotEmpty)
                          entry.detail,
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Category badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _categoryBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_categoryLabel,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: _categoryFg)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
