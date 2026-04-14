import 'package:flutter/material.dart';

import '../../../models/asset.dart';
import '../../../services/asset_service.dart';
import '../../../theme/app_theme.dart';

class AddAssetToSystemSheet extends StatefulWidget {
  final String systemId;
  final String site;
  final Set<String> excludedAssetIds;

  const AddAssetToSystemSheet({
    super.key,
    required this.systemId,
    required this.site,
    required this.excludedAssetIds,
  });

  @override
  State<AddAssetToSystemSheet> createState() => _AddAssetToSystemSheetState();
}

class _AddAssetToSystemSheetState extends State<AddAssetToSystemSheet> {
  final _service = AssetService();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _createNew = false;
  String _role = 'client';
  String? _selectedAssetId;
  String? _selectedType;
  String? _error;
  List<Asset> _assets = [];

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    try {
      final assets = await _service.fetchAssets();
      if (!mounted) return;
      setState(() {
        _assets = assets
            .where((asset) => !widget.excludedAssetIds.contains(asset.id))
            .toList();
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Asset',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Site: ${widget.site == 'production' ? 'Production' : 'Contingency'}',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                      value: false, label: Text('Pick Existing')),
                  ButtonSegment<bool>(value: true, label: Text('Create New')),
                ],
                selected: {_createNew},
                onSelectionChanged: (selection) {
                  setState(() {
                    _createNew = selection.first;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: Asset.linkRoles
                    .map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(role),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _role = value ?? 'client'),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_createNew)
                _buildCreateMode()
              else
                _buildExistingMode(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.dangerText, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving || _loading ? null : _save,
                      child: Text(_createNew ? 'Create & Link' : 'Link Asset'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExistingMode() {
    if (_assets.isEmpty) {
      return Text(
        'No unlinked assets are available for this site.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedAssetId,
      decoration: const InputDecoration(
        labelText: 'Existing Asset',
        border: OutlineInputBorder(),
      ),
      items: _assets
          .map(
            (asset) => DropdownMenuItem(
              value: asset.id,
              child: Text('${asset.name} • ${asset.location}'),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _selectedAssetId = value),
    );
  }

  Widget _buildCreateMode() {
    return Column(
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Name *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedType,
          decoration: const InputDecoration(
            labelText: 'Type *',
            border: OutlineInputBorder(),
          ),
          items: Asset.assetTypes
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(Asset.displayType(type)),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedType = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(
            labelText: 'Location *',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      String assetId;
      if (_createNew) {
        if (_nameController.text.trim().isEmpty ||
            _locationController.text.trim().isEmpty ||
            _selectedType == null) {
          throw AssetServiceException('Name, type, and location are required');
        }
        final asset = await _service.createAsset(
          name: _nameController.text.trim(),
          type: _selectedType!,
          location: _locationController.text.trim(),
        );
        assetId = asset.id;
      } else {
        if (_selectedAssetId == null) {
          throw AssetServiceException('Select an asset to continue');
        }
        assetId = _selectedAssetId!;
      }

      await _service.addLink(
        assetId,
        systemId: widget.systemId,
        role: _role,
        site: widget.site,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on AssetServiceException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}
