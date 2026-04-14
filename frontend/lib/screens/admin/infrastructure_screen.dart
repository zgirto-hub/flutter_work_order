import 'package:flutter/material.dart';

import '../../models/system.dart';
import '../../services/systems_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import 'system_detail_screen.dart';

class InfrastructureScreen extends StatefulWidget {
  const InfrastructureScreen({super.key});

  @override
  State<InfrastructureScreen> createState() => _InfrastructureScreenState();
}

class _InfrastructureScreenState extends State<InfrastructureScreen> {
  final _service = SystemsService();
  List<System> _systems = [];
  bool _loading = true;
  String? _error;
  bool _showRetired = false;
  bool _showNeedsReview = false;

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
      final systems = await _service.fetchSystems(activeOnly: !_showRetired);
      if (!mounted) return;
      setState(() {
        _systems = systems;
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

  List<System> get _filteredSystems {
    var systems = _systems;
    if (_showNeedsReview) {
      systems = systems.where((system) => system.needsReview).toList();
    }
    return systems;
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
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
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          Expanded(
            child: Text(
              'Infrastructure',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
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
            child: FilterChip(
              label: const Text('Show Retired'),
              selected: _showRetired,
              onSelected: (value) {
                setState(() => _showRetired = value);
                _loadData();
              },
              selectedColor: AppColors.accent.withValues(alpha: 0.18),
              checkmarkColor: AppColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilterChip(
              label: const Text('Needs Review'),
              selected: _showNeedsReview,
              onSelected: (value) {
                setState(() => _showNeedsReview = value);
              },
              selectedColor: AppColors.pendingBg,
              checkmarkColor: AppColors.pendingText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: AppColors.dangerText)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_filteredSystems.isEmpty) {
      return EmptyState(
        icon: Icons.hub_outlined,
        title: 'No systems found',
        subtitle: 'Create a system or adjust the current filters.',
        action: ElevatedButton(
          onPressed: _showCreateDialog,
          child: const Text('Create System'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredSystems.length,
        itemBuilder: (context, index) => _SystemCard(
          system: _filteredSystems[index],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SystemDetailScreen(systemId: _filteredSystems[index].id),
              ),
            );
            _loadData();
          },
        ),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _SystemEditorDialog(service: _service),
    );
    if (result == true) {
      _loadData();
    }
  }
}

class _SystemCard extends StatelessWidget {
  final System system;
  final VoidCallback onTap;

  const _SystemCard({required this.system, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
        color: AppColors.bgSurface,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 5,
                height: 104,
                decoration: BoxDecoration(
                  color: system.needsReview
                      ? AppColors.pendingText
                      : AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              system.name,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                decoration: system.isActive
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                          _Pill(
                            label: system.isActive ? 'Active' : 'Retired',
                            backgroundColor: system.isActive
                                ? AppColors.closedBg
                                : AppColors.bgSurface3,
                            foregroundColor: system.isActive
                                ? AppColors.closedText
                                : AppColors.textSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (system.category != null &&
                              system.category!.isNotEmpty)
                            _Pill(
                              label: system.category!,
                              backgroundColor:
                                  AppColors.accent.withValues(alpha: 0.12),
                              foregroundColor: AppColors.accent,
                            ),
                          if (system.needsReview)
                            _Pill(
                              label: 'Needs Review',
                              backgroundColor: AppColors.pendingBg,
                              foregroundColor: AppColors.pendingText,
                            ),
                          _Pill(
                            label: system.hasContingency
                                ? 'Prod + Cont'
                                : 'Prod only',
                            backgroundColor: AppColors.bgSurface2,
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.devices_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Assets available in detail view',
                            // TODO(spec-061): replace with API-provided asset_count once GET /systems returns it.
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemEditorDialog extends StatefulWidget {
  final SystemsService service;

  const _SystemEditorDialog({required this.service});

  @override
  State<_SystemEditorDialog> createState() => _SystemEditorDialogState();
}

class _SystemEditorDialogState extends State<_SystemEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _sortOrderController;
  late bool _hasContingency;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _categoryController = TextEditingController();
    _sortOrderController = TextEditingController();
    _hasContingency = false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create System'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            TextField(
              controller: _sortOrderController,
              decoration: const InputDecoration(labelText: 'Sort Order'),
              keyboardType: TextInputType.number,
            ),
            SwitchListTile.adaptive(
              value: _hasContingency,
              contentPadding: EdgeInsets.zero,
              title: const Text('Has contingency site'),
              onChanged: (value) => setState(() => _hasContingency = value),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppColors.dangerText, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.createSystem(
        name: _nameController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
        sortOrder: _sortOrderController.text.trim().isEmpty
            ? null
            : int.tryParse(_sortOrderController.text.trim()),
        hasContingency: _hasContingency,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _Pill({
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
