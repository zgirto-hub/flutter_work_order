import 'package:flutter/material.dart';

import '../../services/asset_service.dart';
import '../../services/systems_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../system_status_screen.dart';
import 'widgets/add_asset_to_system_sheet.dart';

class SystemDetailScreen extends StatefulWidget {
  final String systemId;

  const SystemDetailScreen({super.key, required this.systemId});

  @override
  State<SystemDetailScreen> createState() => _SystemDetailScreenState();
}

class _SystemDetailScreenState extends State<SystemDetailScreen> {
  final _systemsService = SystemsService();
  final _assetService = AssetService();
  SystemDetail? _detail;
  bool _loading = true;
  String? _error;

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
      final detail = await _systemsService.fetchSystemDetail(widget.systemId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!,
                            style: TextStyle(color: AppColors.dangerText)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  )
                : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final detail = _detail!;
    final system = detail.system;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
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
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      system.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${detail.assetCount} assets · ${system.isActive ? 'Active' : 'Retired'}',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: AppColors.bgSurface,
                onSelected: _handleMenuAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'edit', child: Text('Edit System')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      system.hasContingency
                          ? 'Toggle Has Contingency'
                          : 'Enable Contingency',
                    ),
                  ),
                  PopupMenuItem(
                    value: system.isActive ? 'retire' : 'activate',
                    child: Text(system.isActive ? 'Retire' : 'Activate'),
                  ),
                  const PopupMenuItem(
                    value: 'status',
                    child: Text('View Status Reports'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(
                  label: system.isActive ? 'Active' : 'Retired',
                  backgroundColor: system.isActive
                      ? AppColors.closedBg
                      : AppColors.bgSurface3,
                  foregroundColor: system.isActive
                      ? AppColors.closedText
                      : AppColors.textSecondary,
                ),
                if (system.category != null && system.category!.isNotEmpty)
                  _Badge(
                    label: system.category!,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                    foregroundColor: AppColors.accent,
                  ),
                _Badge(
                  label: 'Sort ${system.sortOrder}',
                  backgroundColor: AppColors.bgSurface2,
                  foregroundColor: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SiteSection(
            title: 'Production',
            accentColor: const Color(0xFF15803D),
            detail: detail.production,
            onAdd: () => _showAddSheet('production'),
            onTapLink: (link, role) =>
                _showLinkActions(link, role, 'production'),
          ),
          if (detail.contingency != null) ...[
            const SizedBox(height: 14),
            _SiteSection(
              title: 'Contingency',
              accentColor: const Color(0xFFF59E0B),
              detail: detail.contingency!,
              onAdd: () => _showAddSheet('contingency'),
              onTapLink: (link, role) =>
                  _showLinkActions(link, role, 'contingency'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAddSheet(String site) async {
    final detail = _detail;
    if (detail == null) return;

    final siteDetail =
        site == 'production' ? detail.production : detail.contingency;
    if (siteDetail == null) return;
    final excludedIds = <String>{
      ...siteDetail.primary.map((link) => link.id),
      ...siteDetail.standby.map((link) => link.id),
      ...siteDetail.client.map((link) => link.id),
    };

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      builder: (_) => AddAssetToSystemSheet(
        systemId: detail.system.id,
        site: site,
        excludedAssetIds: excludedIds,
      ),
    );

    if (result == true) {
      _load();
    }
  }

  Future<void> _showLinkActions(
    SystemDetailLink link,
    String currentRole,
    String currentSite,
  ) async {
    final system = _detail?.system;
    if (system == null) return;

    String nextRole = currentRole;
    String nextSite = currentSite;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: nextRole,
                    decoration: const InputDecoration(
                      labelText: 'Change Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['primary', 'standby', 'client']
                        .map((role) =>
                            DropdownMenuItem(value: role, child: Text(role)))
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => nextRole = value ?? nextRole),
                  ),
                  if (system.hasContingency) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: nextSite,
                      decoration: const InputDecoration(
                        labelText: 'Change Site',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'production', child: Text('production')),
                        DropdownMenuItem(
                            value: 'contingency', child: Text('contingency')),
                      ],
                      onChanged: (value) =>
                          setSheetState(() => nextSite = value ?? nextSite),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style:
                          TextStyle(color: AppColors.dangerText, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Unlink asset'),
                                content: Text(
                                    'Remove ${link.name} from this system?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Unlink'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            if (!mounted) return;
                            try {
                              Navigator.pop(context);
                              await _assetService.deleteLink(link.linkId);
                              _load();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          },
                          child: const Text('Unlink'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (nextRole == currentRole &&
                                nextSite == currentSite) {
                              Navigator.pop(context);
                              return;
                            }
                            try {
                              await _assetService.updateLink(
                                link.linkId,
                                role: nextRole == currentRole ? null : nextRole,
                                site: nextSite == currentSite ? null : nextSite,
                              );
                              if (!mounted) return;
                              Navigator.pop(context);
                              _load();
                            } on AssetServiceException catch (e) {
                              setSheetState(() {
                                error = e.message;
                              });
                            } catch (e) {
                              setSheetState(() {
                                error = e.toString();
                              });
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleMenuAction(String value) async {
    switch (value) {
      case 'edit':
        await _showEditDialog();
        return;
      case 'toggle':
        await _toggleContingency();
        return;
      case 'retire':
        await _retireSystem();
        return;
      case 'activate':
        await _activateSystem();
        return;
      case 'status':
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SystemStatusScreen()),
        );
        return;
    }
  }

  Future<void> _showEditDialog() async {
    final system = _detail?.system;
    if (system == null) return;

    final nameController = TextEditingController(text: system.name);
    final categoryController =
        TextEditingController(text: system.category ?? '');
    final sortController =
        TextEditingController(text: system.sortOrder.toString());
    var hasContingency = system.hasContingency;
    String? inlineError;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit System'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name *'),
                  ),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  TextField(
                    controller: sortController,
                    decoration: const InputDecoration(labelText: 'Sort Order'),
                    keyboardType: TextInputType.number,
                  ),
                  SwitchListTile.adaptive(
                    value: hasContingency,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Has contingency site'),
                    onChanged: (value) =>
                        setDialogState(() => hasContingency = value),
                  ),
                  if (inlineError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        inlineError!,
                        style: TextStyle(
                            color: AppColors.dangerText, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _systemsService.updateSystem(
                      system.id,
                      name: nameController.text.trim(),
                      category: categoryController.text.trim().isEmpty
                          ? null
                          : categoryController.text.trim(),
                      sortOrder: int.tryParse(sortController.text.trim()),
                      hasContingency: hasContingency,
                    );
                    if (!mounted) return;
                    Navigator.pop(context);
                    _load();
                  } on SystemsServiceException catch (e) {
                    setDialogState(() {
                      inlineError = e.message;
                    });
                  } catch (e) {
                    setDialogState(() {
                      inlineError = e.toString();
                    });
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleContingency() async {
    final detail = _detail;
    if (detail == null) return;
    if (!detail.system.hasContingency) {
      try {
        await _systemsService.updateSystem(
          detail.system.id,
          hasContingency: true,
        );
        _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }

    final contingencyCount = detail.contingency?.assetCount ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable contingency'),
        content: Text(
          'Move $contingencyCount contingency assets to production? Some may be demoted to client when production already has a primary or standby.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move & Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _systemsService.disableContingency(detail.system.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Moved ${result['moved']}, demoted ${result['demoted']}',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _retireSystem() async {
    final detail = _detail;
    if (detail == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire system'),
        content: Text('Retire ${detail.system.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final result = await _systemsService.retireSystem(detail.system.id);
      if (!mounted) return;
      if (result['warning'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['warning'] as String)),
        );
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _activateSystem() async {
    final detail = _detail;
    if (detail == null) return;
    try {
      await _systemsService.activateSystem(detail.system.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class _SiteSection extends StatelessWidget {
  final String title;
  final Color accentColor;
  final SystemDetailSite detail;
  final VoidCallback onAdd;
  final void Function(SystemDetailLink link, String role) onTapLink;

  const _SiteSection({
    required this.title,
    required this.accentColor,
    required this.detail,
    required this.onAdd,
    required this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: accentColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _RoleGroup(
                  title: 'Primary',
                  role: 'primary',
                  links: detail.primary,
                  onTapLink: onTapLink,
                ),
                const SizedBox(height: 14),
                _RoleGroup(
                  title: 'Standby',
                  role: 'standby',
                  links: detail.standby,
                  onTapLink: onTapLink,
                ),
                const SizedBox(height: 14),
                _RoleGroup(
                  title: 'Client',
                  role: 'client',
                  links: detail.client,
                  onTapLink: onTapLink,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleGroup extends StatelessWidget {
  final String title;
  final String role;
  final List<SystemDetailLink> links;
  final void Function(SystemDetailLink link, String role) onTapLink;

  const _RoleGroup({
    required this.title,
    required this.role,
    required this.links,
    required this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (links.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('—', style: TextStyle(color: AppColors.textTertiary)),
          )
        else
          ...links.map(
            (link) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                onTap: () => onTapLink(link, role),
                title: Text(
                  link.name,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${link.type.replaceAll('_', ' ')} • ${link.location}',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                trailing: _Badge(
                  label: role,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                  foregroundColor: AppColors.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _Badge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
