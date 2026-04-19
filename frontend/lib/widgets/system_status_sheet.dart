import 'package:flutter/material.dart';
import '../models/system_status_report.dart';
import '../services/system_status_service.dart';
import '../theme/app_theme.dart';

class SystemStatusSheet extends StatefulWidget {
  final SystemStatus system;
  final VoidCallback onReportSystemIssue;
  final void Function(SystemStatusReport report) onShowIssueDetails;
  final void Function(SystemStatusReport report) onEditIssue;
  final void Function(SystemStatusReport report) onResolveIssue;
  final void Function(SystemStatusReport report) onDeleteIssue;
  final void Function(SystemStatusReport report) onReportAssetIssue;
  final VoidCallback onChange;

  const SystemStatusSheet({
    super.key,
    required this.system,
    required this.onReportSystemIssue,
    required this.onShowIssueDetails,
    required this.onEditIssue,
    required this.onResolveIssue,
    required this.onDeleteIssue,
    required this.onReportAssetIssue,
    required this.onChange,
  });

  @override
  State<SystemStatusSheet> createState() => _SystemStatusSheetState();
}

class _SystemStatusSheetState extends State<SystemStatusSheet> {
  final _service = SystemStatusService();
  bool _loading = true;
  String? _error;
  SystemAssetsResponse? _response;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchSystemAssets(systemId: widget.system.systemId);
      if (!mounted) return;
      setState(() {
        _response = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIssue = widget.system.hasIssue;
    final statusColor =
        isIssue ? const Color(0xFFB91C1C) : const Color(0xFF15803D);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8F1),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.system.systemName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SystemLevelSection(
                system: widget.system,
                onReportIssue: widget.onReportSystemIssue,
                onShowDetails: widget.onShowIssueDetails,
                onEdit: widget.onEditIssue,
                onResolve: widget.onResolveIssue,
                onDelete: widget.onDeleteIssue,
              ),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Assets',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _AssetErrorState(error: _error!, onRetry: _load)
                      : _response!.assets.isEmpty
                          ? _EmptyAssetState()
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: _response!.assets.length,
                              itemBuilder: (ctx, i) {
                                final asset = _response!.assets[i];
                                return _AssetRow(
                                  entry: asset,
                                  onTap: () {
                                    if (asset.activeReport != null) {
                                      widget.onShowIssueDetails(asset.activeReport!);
                                    } else {
                                      widget.onReportAssetIssue(asset);
                                    }
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemLevelSection extends StatelessWidget {
  final SystemStatus system;
  final VoidCallback onReportIssue;
  final void Function(SystemStatusReport) onShowDetails;
  final void Function(SystemStatusReport) onEdit;
  final void Function(SystemStatusReport) onResolve;
  final void Function(SystemStatusReport) onDelete;

  const _SystemLevelSection({
    required this.system,
    required this.onReportIssue,
    required this.onShowDetails,
    required this.onEdit,
    required this.onResolve,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (system.activeReport != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IssueDetailCard(
            label: 'System-level issue',
            report: system.activeReport!,
            onShowDetails: () => onShowDetails(system.activeReport!),
            onEdit: () => onEdit(system.activeReport!),
            onResolve: () => onResolve(system.activeReport!),
            onDelete: () => onDelete(system.activeReport!),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onReportIssue,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFB91C1C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'Report System Issue',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _IssueDetailCard extends StatelessWidget {
  final String label;
  final SystemStatusReport report;
  final VoidCallback onShowDetails;
  final VoidCallback onEdit;
  final VoidCallback onResolve;
  final VoidCallback onDelete;

  const _IssueDetailCard({
    required this.label,
    required this.report,
    required this.onShowDetails,
    required this.onEdit,
    required this.onResolve,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFB91C1C),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB91C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _detailRow('Date', report.reportDate),
          if (report.notes.isNotEmpty) _detailRow('Notes', report.notes),
          _detailRow(
            'Reported by',
            report.reportedByName.isNotEmpty
                ? report.reportedByName
                : report.reportedBy,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Delete', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFB91C1C)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  onPressed: onResolve,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Resolve',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final AssetStatusEntry entry;
  final VoidCallback onTap;

  const _AssetRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIssue = entry.hasIssue;
    final statusColor =
        isIssue ? const Color(0xFFB91C1C) : const Color(0xFF15803D);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border2, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.assetName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${entry.role} · ${entry.site}',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _AssetErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Couldn't load assets",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _EmptyAssetState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          'No assets linked. Link assets in Infrastructure.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
