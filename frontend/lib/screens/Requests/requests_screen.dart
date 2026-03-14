import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/request_model.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import 'add_request_screen.dart';
import 'request_detail_screen.dart';

class RequestsScreen extends StatefulWidget {
  final String userRole;
  final VoidCallback? onChanged;
  const RequestsScreen({super.key, required this.userRole, this.onChanged});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final _service = RequestService();
  List<RequestModel> _requests = [];
  String _statusFilter = 'All';
  bool _loading = true;

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _service.fetchRequests(
      email: _email,
      userRole: widget.userRole,
    );
    if (!mounted) return;
    setState(() {
      _requests = data;
      _loading = false;
    });
    widget.onChanged?.call();
  }

  List<RequestModel> get _filtered {
    if (_statusFilter == 'All') return _requests;
    return _requests.where((r) => r.status == _statusFilter).toList();
  }

  Future<void> _openAdd() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddRequestScreen()),
    );
    if (added == true) await _load();
  }

  Future<void> _openDetail(RequestModel req) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(
          request: req,
          userRole: widget.userRole,
        ),
      ),
    );
    if (updated == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Requests',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilterChipRow(
                    filters: const ['All', 'Open', 'Closed'],
                    selected: _statusFilter,
                    onSelected: (s) => setState(() => _statusFilter = s),
                  ),
                ],
              ),
            ),

            const Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── List ────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: AppColors.bgSurface3,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _statusFilter == 'All'
                                    ? 'No requests yet'
                                    : 'No $_statusFilter requests',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accent,
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(14, 12, 14, 80),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) =>
                                _RequestCard(
                                  request: _filtered[i],
                                  onTap: () => _openDetail(_filtered[i]),
                                ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.userRole == 'requester'
          ? ClaudeFAB(onTap: _openAdd)
          : null,
    );
  }
}

// ── Request Card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final RequestModel request;
  final VoidCallback onTap;

  const _RequestCard({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOpen = request.status == 'Open';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: request.status),
              ],
            ),

            if (request.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],

            const SizedBox(height: 10),

            Row(
              children: [
                if (request.location.isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    request.location,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                const Icon(Icons.person_outline_rounded,
                    size: 12, color: AppColors.textTertiary),
                const SizedBox(width: 3),
                Text(
                  request.requesterName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(request.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOpen = status == 'Open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen ? AppColors.pendingBg : AppColors.closedBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isOpen ? AppColors.pendingText : AppColors.closedText,
        ),
      ),
    );
  }
}
