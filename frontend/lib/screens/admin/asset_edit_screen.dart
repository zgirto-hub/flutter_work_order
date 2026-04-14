import 'package:flutter/material.dart';
import '../../services/asset_service.dart';
import '../../models/asset.dart';
import '../../theme/app_theme.dart';

class AssetEditScreen extends StatefulWidget {
  final Asset? asset;
  final String? prefillName;
  final String? prefillType;

  const AssetEditScreen({
    super.key,
    this.asset,
    this.prefillName,
    this.prefillType,
  });

  @override
  State<AssetEditScreen> createState() => _AssetEditScreenState();
}

class _AssetEditScreenState extends State<AssetEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = AssetService();
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  late TextEditingController _notesController;
  String? _selectedType;
  bool _loading = false;
  Asset? _currentAsset;

  bool get isEditMode => widget.asset != null || _currentAsset != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: widget.asset?.name ?? widget.prefillName ?? '');
    _locationController =
        TextEditingController(text: widget.asset?.location ?? '');
    _notesController = TextEditingController(text: widget.asset?.notes ?? '');
    _selectedType = widget.asset?.type;
    if (_selectedType == null && widget.prefillType != null) {
      if (Asset.assetTypes.contains(widget.prefillType)) {
        _selectedType = widget.prefillType;
      }
    }
    _currentAsset = widget.asset;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _reloadAsset() async {
    if (_currentAsset == null) return;
    try {
      final assets = await _service.fetchAssets();
      final updated =
          assets.where((a) => a.id == _currentAsset!.id).firstOrNull;
      if (updated != null && mounted) {
        setState(() => _currentAsset = updated);
      }
    } catch (e) {
      // ignore reload errors
    }
  }

  Future<void> _saveAsset() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select an asset type')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (isEditMode && _currentAsset != null) {
        await _service.updateAsset(
          _currentAsset!.id,
          name: _nameController.text.trim(),
          type: _selectedType,
          location: _locationController.text.trim(),
          notes: _notesController.text.trim(),
        );
        if (mounted) Navigator.pop(context, true);
      } else {
        final saved = await _service.createAsset(
          name: _nameController.text.trim(),
          type: _selectedType!,
          location: _locationController.text.trim(),
          notes: _notesController.text.trim(),
        );
        if (mounted) {
          setState(() => _currentAsset = saved);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Asset created. You can now add system associations.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAsset() async {
    if (_currentAsset == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Asset'),
        content: Text(
            'Are you sure you want to delete "${_currentAsset!.name}"? This will also remove all system links.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerText),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _service.deleteAsset(_currentAsset!.id);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addLink() async {
    if (_currentAsset == null) return;

    String? selectedSystem;
    String? selectedRole;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add System Link',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return Asset.systemSuggestions;
                  }
                  return Asset.systemSuggestions.where(
                    (s) => s
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()),
                  );
                },
                onSelected: (value) => selectedSystem = value,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'System *',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => selectedSystem = v,
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role *',
                  border: OutlineInputBorder(),
                ),
                items: Asset.linkRoles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setSheetState(() => selectedRole = v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (selectedSystem == null || selectedRole == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text('Please fill all fields')),
                          );
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white),
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (result != true) return;
    if (selectedSystem == null || selectedRole == null) return;

    setState(() => _loading = true);
    try {
      await _service.addLink(_currentAsset!.id,
          system: selectedSystem!, role: selectedRole!);
      await _reloadAsset();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeLink(AssetSystemLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Link'),
        content: Text('Remove link to ${link.system} as ${link.role}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerText),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _service.removeLink(link.id);
      await _reloadAsset();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(
            isEditMode && _currentAsset != null ? 'Edit Asset' : 'Add Asset'),
        backgroundColor: AppColors.bgSurface,
        actions: [
          if (_currentAsset != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteAsset,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Asset Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Type *',
                border: OutlineInputBorder(),
              ),
              items: Asset.assetTypes
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(Asset.displayType(t))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedType = v),
              validator: (v) => v == null ? 'Type is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Location is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _saveAsset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEditMode && _currentAsset != null
                        ? 'Save Changes'
                        : 'Create Asset'),
              ),
            ),
            if (_currentAsset != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('System Associations',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  TextButton.icon(
                    onPressed: _addLink,
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_currentAsset!.systemLinks.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'No system associations. Tap "Add" to link this asset to a system.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...(_currentAsset!.systemLinks.map((link) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(Icons.devices_outlined,
                            color: AppColors.accent),
                        title: Text(link.system),
                        subtitle: Text(link.role,
                            style: TextStyle(color: AppColors.textSecondary)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: AppColors.dangerText),
                          onPressed: () => _removeLink(link),
                        ),
                      ),
                    ))),
            ] else ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Save the asset first, then add system associations.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
