import 'package:flutter/material.dart';
import '../../services/asset_service.dart';
import '../../models/asset.dart';
import '../../theme/app_theme.dart';
import 'asset_edit_screen.dart';

class AssetRegistryScreen extends StatefulWidget {
  const AssetRegistryScreen({super.key});

  @override
  State<AssetRegistryScreen> createState() => _AssetRegistryScreenState();
}

class _AssetRegistryScreenState extends State<AssetRegistryScreen> {
  final _service = AssetService();
  List<Asset> _assets = [];
  List<Asset> _filteredAssets = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  String? _error;
  bool _showSearch = false;
  final _searchController = TextEditingController();
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assets = await _service.fetchAssets();
      List<Map<String, dynamic>> suggestions = [];
      try {
        suggestions = await _service.fetchSuggestions();
      } catch (_) {
        // Suggestions are supplementary — don't block asset list
      }
      setState(() {
        _assets = assets;
        _suggestions = suggestions;
        _applyFilters();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    var filtered = _assets.toList();
    if (_selectedType != null) {
      filtered = filtered.where((a) => a.type == _selectedType).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered =
          filtered.where((a) => a.name.toLowerCase().contains(query)).toList();
    }
    _filteredAssets = filtered;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _applyFilters();
    });
  }

  void _onTypeFilterChanged(String? type) {
    setState(() {
      _selectedType = type;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilterRow(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAsset,
        icon: const Icon(Icons.add),
        label: const Text('Add Asset'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
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
              child: Icon(Icons.arrow_back, color: AppColors.textPrimary),
            ),
          if (Navigator.canPop(context)) const SizedBox(width: 12),
          Expanded(
            child: _showSearch
                ? TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by name...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      isDense: true,
                    ),
                  )
                : Text(
                    'Asset Registry',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _applyFilters();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _selectedType,
              decoration: InputDecoration(
                labelText: 'Filter by Type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Types')),
                ...Asset.assetTypes.map((t) => DropdownMenuItem(
                    value: t, child: Text(Asset.displayType(t)))),
              ],
              onChanged: _onTypeFilterChanged,
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
            ElevatedButton(
              onPressed: _loadAssets,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAssets,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_suggestions.isNotEmpty) _buildSuggestionsSection(),
          if (_filteredAssets.isEmpty && _suggestions.isEmpty)
            _buildEmptyState()
          else
            ..._filteredAssets.map((asset) => _buildAssetCard(asset)),
        ],
      ),
    );
  }

  Widget _buildSuggestionsSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Suggested Assets',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Unregistered equipment with recurring alerts',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ..._suggestions.map((s) => _buildSuggestionCard(s)),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(Map<String, dynamic> suggestion) {
    final name = suggestion['equipment_id'] as String? ?? '';
    final alertCount = suggestion['alert_count'] as int? ?? 0;
    final faultTypes = (suggestion['fault_types'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final inferredType = suggestion['inferred_type'] as String?;
    final displayName = name.length > 50 ? '${name.substring(0, 47)}...' : name;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$alertCount alert${alertCount != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (faultTypes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  ...faultTypes.take(3).map((ft) {
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.bgPrimary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ft,
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                    );
                  }),
                  if (faultTypes.length > 3)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.bgPrimary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+${faultTypes.length - 3} more',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ],
            if (inferredType != null) ...[
              const SizedBox(height: 8),
              Text(
                'Likely: $inferredType',
                style: TextStyle(fontSize: 12, color: AppColors.accent),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _dismissSuggestion(suggestion),
                  child: Text(
                    'Dismiss',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _acceptSuggestion(suggestion),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Add', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No assets registered yet',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetCard(Asset asset) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _editAsset(asset),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      asset.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      Asset.displayType(asset.type),
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    asset.location,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              if (asset.systemLinks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.devices_outlined,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${asset.systemLinks.length} system(s)',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addAsset() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AssetEditScreen()),
    );
    if (result == true) {
      _loadAssets();
    }
  }

  Future<void> _editAsset(Asset asset) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AssetEditScreen(asset: asset)),
    );
    if (result == true) {
      _loadAssets();
    }
  }

  Future<void> _acceptSuggestion(Map<String, dynamic> suggestion) async {
    final name = suggestion['equipment_id'] as String? ?? '';
    final inferredType = suggestion['inferred_type'] as String?;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AssetEditScreen(
          prefillName: name,
          prefillType: inferredType,
        ),
      ),
    );
    if (result == true) {
      _loadAssets();
    }
  }

  Future<void> _dismissSuggestion(Map<String, dynamic> suggestion) async {
    final equipmentId = suggestion['equipment_id'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss Suggestion'),
        content: Text(
            'Dismiss "$equipmentId"? This equipment will no longer appear in suggestions, even if new alerts are created.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerText),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.dismissSuggestion(equipmentId);
      setState(() {
        _suggestions.removeWhere(
            (s) => s['equipment_id'] == suggestion['equipment_id']);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suggestion dismissed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }
}
