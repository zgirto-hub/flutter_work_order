import 'package:flutter/material.dart';
import '../../services/systems_service.dart';
import '../../models/system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';

class SystemsScreen extends StatefulWidget {
  const SystemsScreen({super.key});

  @override
  State<SystemsScreen> createState() => _SystemsScreenState();
}

class _SystemsScreenState extends State<SystemsScreen> {
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
      final systems = await _service.fetchSystems(
        activeOnly: !_showRetired,
        needsReview: _showNeedsReview,
      );
      setState(() {
        _systems = systems;
        _loading = false;
      });
    } catch (e) {
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
        child: Column(
          children: [
            _buildHeader(),
            _buildFilters(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.white),
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
            child: Text('Systems',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5)),
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
              onSelected: (v) {
                setState(() => _showRetired = v);
                _loadData();
              },
              selectedColor: AppColors.accent.withValues(alpha: 0.2),
              checkmarkColor: AppColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilterChip(
              label: const Text('Needs Review'),
              selected: _showNeedsReview,
              onSelected: (v) {
                setState(() => _showNeedsReview = v);
                _loadData();
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
    if (_systems.isEmpty) {
      return EmptyState(
        icon: Icons.dns_outlined,
        title: 'No Systems',
        subtitle: 'Add a system to get started',
        action: ElevatedButton(
          onPressed: _showAddDialog,
          child: const Text('Add System'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _systems.length,
      itemBuilder: (context, index) {
        final system = _systems[index];
        return _buildSystemCard(system);
      },
    );
  }

  Widget _buildSystemCard(System system) {
    final isActive = system.isActive;
    final hasReview = system.needsReview;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.bgSurface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          system.name,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            decoration: isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (system.category != null)
              Text(
                system.category!,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            Text(
              'Sort: ${system.sortOrder}',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasReview)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.pendingBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Review',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.pendingText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.closedBg
                    : AppColors.textTertiary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isActive ? 'Active' : 'Retired',
                style: TextStyle(
                  fontSize: 10,
                  color:
                      isActive ? AppColors.closedText : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditDialog(system);
                } else if (value == 'retire' && isActive) {
                  _showRetireDialog(system);
                } else if (value == 'activate' && !isActive) {
                  _activateSystem(system.id);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (isActive)
                  const PopupMenuItem(value: 'retire', child: Text('Retire')),
                if (!isActive)
                  const PopupMenuItem(
                      value: 'activate', child: Text('Activate')),
              ],
            ),
          ],
        ),
        onTap: () => _showEditDialog(system),
      ),
    );
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final categoryController = TextEditingController();
    final sortOrderController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add System'),
        content: Column(
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
              controller: sortOrderController,
              decoration: const InputDecoration(labelText: 'Sort Order'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name is required')),
                );
                return;
              }
              try {
                await _service.createSystem(
                  name: nameController.text.trim(),
                  category: categoryController.text.trim().isEmpty
                      ? null
                      : categoryController.text.trim(),
                  sortOrder: sortOrderController.text.isEmpty
                      ? null
                      : int.tryParse(sortOrderController.text),
                );
                Navigator.pop(context);
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(System system) {
    final nameController = TextEditingController(text: system.name);
    final categoryController =
        TextEditingController(text: system.category ?? '');
    final sortOrderController =
        TextEditingController(text: system.sortOrder.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit System'),
        content: Column(
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
              controller: sortOrderController,
              decoration: const InputDecoration(labelText: 'Sort Order'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name is required')),
                );
                return;
              }
              try {
                await _service.updateSystem(
                  system.id,
                  name: nameController.text.trim(),
                  category: categoryController.text.trim().isEmpty
                      ? null
                      : categoryController.text.trim(),
                  sortOrder: sortOrderController.text.isEmpty
                      ? null
                      : int.tryParse(sortOrderController.text),
                );
                Navigator.pop(context);
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showRetireDialog(System system) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire System'),
        content: Text('Are you sure you want to retire "${system.name}"? '
            'It will no longer appear in selection dropdowns but existing records will be preserved.'),
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
    if (confirm != true || !mounted) return;

    try {
      final result = await _service.retireSystem(system.id);
      if (!mounted) return;

      if (result.containsKey('warning')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['warning'] as String)),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _activateSystem(String id) async {
    try {
      await _service.activateSystem(id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}
