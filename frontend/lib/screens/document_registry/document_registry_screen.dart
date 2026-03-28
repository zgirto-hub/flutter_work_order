import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/form_fields.dart';
import '../../models/registry_entry.dart';
import '../../services/document_registry_service.dart';

class DocumentRegistryScreen extends StatefulWidget {
  const DocumentRegistryScreen({super.key});

  @override
  State<DocumentRegistryScreen> createState() => _DocumentRegistryScreenState();
}

class _DocumentRegistryScreenState extends State<DocumentRegistryScreen> {
  final _service = DocumentRegistryService();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  DateTime? _selectedDate;
  List<RegistryEntry> _allEntries = [];
  List<RegistryEntry> _filteredEntries = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _replied = false;
  RegistryEntry? _editingEntry;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _dateCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    try {
      final entries = await _service.fetchEntries();
      if (!mounted) return;
      setState(() {
        _allEntries = entries;
        _applySearch();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load entries')),
      );
    }
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filteredEntries = List.of(_allEntries);
    } else {
      _filteredEntries = _allEntries.where((e) {
        return e.documentName.toLowerCase().contains(q) ||
            e.documentNumber.toLowerCase().contains(q);
      }).toList();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.accent,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _startEditing(RegistryEntry entry) {
    setState(() {
      _editingEntry = entry;
      _nameCtrl.text = entry.documentName;
      _numberCtrl.text = entry.documentNumber;
      _dateCtrl.text = entry.date;
      _selectedDate = DateTime.tryParse(entry.date);
      _replied = entry.replied;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingEntry = null;
      _nameCtrl.clear();
      _numberCtrl.clear();
      _dateCtrl.clear();
      _selectedDate = null;
      _replied = false;
    });
  }

  Future<void> _submitEntry() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a date')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_editingEntry != null) {
        await _service.updateEntry(
          _editingEntry!.id,
          documentName: _nameCtrl.text.trim(),
          documentNumber: _numberCtrl.text.trim(),
          date: _dateCtrl.text.trim(),
          replied: _replied,
        );
      } else {
        await _service.createEntry(
          documentName: _nameCtrl.text.trim(),
          documentNumber: _numberCtrl.text.trim(),
          date: _dateCtrl.text.trim(),
          replied: _replied,
        );
      }
      _nameCtrl.clear();
      _numberCtrl.clear();
      _dateCtrl.clear();
      _selectedDate = null;
      _editingEntry = null;
      _replied = false;
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editingEntry != null ? 'Failed to update entry' : 'Failed to save entry')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteEntry(RegistryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Entry'),
        content: Text('Delete "${entry.documentName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.dangerText)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteEntry(entry.id);
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete entry')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Document Registry',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── Body ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Form ──
                    _buildForm(),

                    const SizedBox(height: 20),

                    // ── Search ──
                    _buildSearchBar(),

                    const SizedBox(height: 16),

                    // ── List ──
                    _buildEntryList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _editingEntry != null ? 'Edit Entry' : 'New Entry',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (_editingEntry != null)
                  GestureDetector(
                    onTap: _cancelEditing,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            ValidatedTextField(
              controller: _nameCtrl,
              label: 'Document Name',
              hint: 'Enter document name',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            ValidatedTextField(
              controller: _numberCtrl,
              label: 'Document Number',
              hint: 'Enter document number',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            GestureDetector(
              onTap: _pickDate,
              child: AbsorbPointer(
                child: ValidatedTextField(
                  controller: _dateCtrl,
                  label: 'Date',
                  hint: 'Select date',
                  suffixIcon: Icon(Icons.calendar_today_rounded,
                      size: 18, color: AppColors.textSecondary),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _replied,
                    onChanged: (v) => setState(() => _replied = v ?? false),
                    activeColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    side: BorderSide(color: AppColors.border2, width: 1.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Replied',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submitEntry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _editingEntry != null ? 'Save Changes' : 'Add Entry',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (_) => setState(() => _applySearch()),
      decoration: InputDecoration(
        hintText: 'Search by name or number...',
        hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.bgSurface,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border2, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border2, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
    );
  }

  Widget _buildEntryList() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 1.5),
        ),
      );
    }

    if (_filteredEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.inbox_rounded, size: 40, color: AppColors.textTertiary),
              const SizedBox(height: 8),
              Text(
                _searchCtrl.text.isNotEmpty ? 'No matching entries' : 'No entries yet',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredEntries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = _filteredEntries[index];
        return _buildEntryCard(entry);
      },
    );
  }

  Widget _buildEntryCard(RegistryEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFCFFAFE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.description_outlined, size: 18, color: const Color(0xFF0E7490)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.documentName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '#${entry.documentNumber}  •  ${entry.date}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: entry.replied
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.replied ? 'Yes' : 'No',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: entry.replied
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _startEditing(entry),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.edit_outlined, size: 17, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _deleteEntry(entry),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
