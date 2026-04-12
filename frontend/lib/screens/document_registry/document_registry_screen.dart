import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../../widgets/form_fields.dart';
import '../../models/registry_entry.dart';
import '../../services/document_registry_service.dart';
import '../../config.dart';

class DocumentRegistryScreen extends StatefulWidget {
  const DocumentRegistryScreen({super.key});

  @override
  State<DocumentRegistryScreen> createState() => _DocumentRegistryScreenState();
}

class _DocumentRegistryScreenState extends State<DocumentRegistryScreen>
    with WidgetsBindingObserver {
  final _service = DocumentRegistryService();
  final _searchCtrl = TextEditingController();

  List<RegistryEntry> _allEntries = [];
  List<RegistryEntry> _filteredEntries = [];
  bool _isLoading = true;
  int? _expandedIndex;
  Key _historyKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadEntries();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _loadEntries();
    }
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    try {
      final entries = await _service.fetchEntries();
      if (!mounted) return;
      setState(() {
        _allEntries = entries;
        _applySearch();
        _expandedIndex = null;
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

  void _onEntrySaved() {
    setState(() => _historyKey = UniqueKey());
    _loadEntries();
  }

  void _openForm({RegistryEntry? entry}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RegistryFormScreen(
          editEntry: entry,
          onEntrySaved: _onEntrySaved,
        ),
      ),
    );
  }

  Future<void> _attachFile(RegistryEntry entry) async {
    final file = await _service.pickAttachment();
    if (file == null) return;

    try {
      final ok = await _service.uploadAttachment(entry.id, file);
      if (ok) {
        await _loadEntries();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload file')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload file')),
      );
    }
  }

  Future<void> _openAttachment(RegistryEntry entry) async {
    if (entry.fileUrl == null) return;
    final url = '${AppConfig.downloadUrl}${entry.fileUrl}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _removeAttachment(RegistryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(
          'Remove Attachment',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        content: Text(
          'Remove "${entry.fileName ?? 'attachment'}" from this entry?',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: TextStyle(
                    color: AppColors.dangerText, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteAttachment(entry.id);
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove attachment')),
      );
    }
  }

  Future<void> _deleteEntry(RegistryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(
          'Delete Entry',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        content: Text(
          'Delete "${entry.documentName}"?',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: TextStyle(
                    color: AppColors.dangerText, fontWeight: FontWeight.w600)),
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
      floatingActionButton: ClaudeFAB(
        onTap: () => _openForm(),
        tooltip: 'New entry',
        semanticsLabel: 'Create new registry entry',
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (ModalRoute.of(context)?.isFirst == false) ...[
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border:
                              Border.all(color: AppColors.border2, width: 0.5),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      'Document Registry',
                      style: TextStyle(
                        fontSize: 16,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {
                  _applySearch();
                  _expandedIndex = null;
                }),
                decoration: InputDecoration(
                  hintText: 'Search by name or number...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: AppColors.textTertiary),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.bgSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: AppColors.border2, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: AppColors.border2, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.accent, width: 2),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : _filteredEntries.isEmpty
                      ? EmptyState(
                          icon: Icons.description_outlined,
                          title: _searchCtrl.text.isNotEmpty
                              ? 'No Matching Entries'
                              : 'No Entries Yet',
                          subtitle: _searchCtrl.text.isNotEmpty
                              ? 'Try a different search term'
                              : 'Document entries you create will appear here',
                        )
                      : RefreshIndicator(
                          color: AppColors.accent,
                          onRefresh: _loadEntries,
                          child: ListView.builder(
                            key: _historyKey,
                            padding: const EdgeInsets.all(12),
                            itemCount: _filteredEntries.length,
                            itemBuilder: (ctx, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _RegistryEntryCard(
                                entry: _filteredEntries[i],
                                expanded: _expandedIndex == i,
                                onTap: () => setState(() {
                                  _expandedIndex =
                                      _expandedIndex == i ? null : i;
                                }),
                                onEdit: () =>
                                    _openForm(entry: _filteredEntries[i]),
                                onAttach: () =>
                                    _attachFile(_filteredEntries[i]),
                                onDelete: () =>
                                    _deleteEntry(_filteredEntries[i]),
                                onOpenAttachment: () =>
                                    _openAttachment(_filteredEntries[i]),
                                onRemoveAttachment: () =>
                                    _removeAttachment(_filteredEntries[i]),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistryEntryCard extends StatefulWidget {
  final RegistryEntry entry;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onAttach;
  final VoidCallback onDelete;
  final VoidCallback onOpenAttachment;
  final VoidCallback onRemoveAttachment;

  const _RegistryEntryCard({
    required this.entry,
    required this.expanded,
    required this.onTap,
    required this.onEdit,
    required this.onAttach,
    required this.onDelete,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
  });

  @override
  State<_RegistryEntryCard> createState() => _RegistryEntryCardState();
}

class _RegistryEntryCardState extends State<_RegistryEntryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.expanded ? 1.0 : 0.0,
  );

  late final Animation<double> _size =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<double> _chevron =
      Tween<double>(begin: 0.0, end: 0.5).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic),
  );

  @override
  void didUpdateWidget(_RegistryEntryCard old) {
    super.didUpdateWidget(old);
    if (old.expanded != widget.expanded) {
      widget.expanded ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.expanded ? AppColors.border2 : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCFFAFE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: Color(0xFF0E7490),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.entry.documentName,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '#${widget.entry.documentNumber}  ·  ${widget.entry.date}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: widget.entry.replied
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.entry.replied ? 'Replied' : 'Pending',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: widget.entry.replied
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
                  RotationTransition(
                    turns: _chevron,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            SizeTransition(
              sizeFactor: _size,
              axisAlignment: -1,
              child: FadeTransition(
                opacity: _fade,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('Created by', widget.entry.createdBy),
                      _detailRow('Created', widget.entry.createdAt ?? '—'),
                      if (widget.entry.hasAttachment) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: widget.onOpenAttachment,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.border2, width: 0.5),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.insert_drive_file_outlined,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.entry.fileName ?? 'Attachment',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.accent,
                                      decoration: TextDecoration.underline,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: widget.onRemoveAttachment,
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: widget.onAttach,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.bgSurface,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                    color: AppColors.border2, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attach_file_rounded,
                                      size: 13, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Attach',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: widget.onEdit,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.bgSurface,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                    color: AppColors.border2, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_outlined,
                                      size: 13, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Edit',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: widget.onDelete,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.bgSurface,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                    color: AppColors.dangerText
                                        .withValues(alpha: 0.3),
                                    width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.delete_outline_rounded,
                                      size: 13, color: AppColors.dangerText),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Delete',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.dangerText,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistryFormScreen extends StatefulWidget {
  final RegistryEntry? editEntry;
  final VoidCallback onEntrySaved;

  const _RegistryFormScreen({
    this.editEntry,
    required this.onEntrySaved,
  });

  @override
  State<_RegistryFormScreen> createState() => _RegistryFormScreenState();
}

class _RegistryFormScreenState extends State<_RegistryFormScreen> {
  final _service = DocumentRegistryService();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  DateTime? _selectedDate;
  bool _replied = false;
  bool _isSaving = false;
  bool _isExtracting = false;
  PlatformFile? _pendingAttachment;

  bool get _isEditing => widget.editEntry != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text = widget.editEntry!.documentName;
      _numberCtrl.text = widget.editEntry!.documentNumber;
      _dateCtrl.text = widget.editEntry!.date;
      _selectedDate = DateTime.tryParse(widget.editEntry!.date);
      _replied = widget.editEntry!.replied;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
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

  Future<void> _extractFromPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() => _isExtracting = true);

    try {
      final fields = await _service.extractFieldsFromPdf(file);
      if (!mounted) return;

      setState(() {
        if (fields?['document_name'] != null) {
          _nameCtrl.text = fields!['document_name'];
        }
        if (fields?['document_number'] != null) {
          _numberCtrl.text = fields!['document_number'];
        }
        if (fields?['date'] != null) {
          _dateCtrl.text = fields!['date'];
          _selectedDate = DateTime.tryParse(fields['date']);
        }
        _pendingAttachment = file;
        _isExtracting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fields extracted from PDF')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExtracting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to extract fields from PDF')),
      );
    }
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
      if (_isEditing) {
        await _service.updateEntry(
          widget.editEntry!.id,
          documentName: _nameCtrl.text.trim(),
          documentNumber: _numberCtrl.text.trim(),
          date: _dateCtrl.text.trim(),
          replied: _replied,
        );
      } else {
        final entryId = await _service.createEntry(
          documentName: _nameCtrl.text.trim(),
          documentNumber: _numberCtrl.text.trim(),
          date: _dateCtrl.text.trim(),
          replied: _replied,
        );
        if (_pendingAttachment != null && entryId != null) {
          await _service.uploadAttachment(entryId, _pendingAttachment!);
        }
      }
      widget.onEntrySaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isEditing
                ? 'Failed to update entry'
                : 'Failed to save entry')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      widget.onEntrySaved();
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(9),
                        border:
                            Border.all(color: AppColors.border2, width: 0.5),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Entry' : 'Create Document Entry',
                      style: TextStyle(
                        fontSize: 16,
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isEditing) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: _isExtracting ? null : _extractFromPdf,
                            icon: _isExtracting
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accent,
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf_rounded,
                                    size: 18),
                            label: Text(
                              _isExtracting
                                  ? 'Extracting...'
                                  : 'Extract from PDF',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: BorderSide(
                                  color: AppColors.accent, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        if (_pendingAttachment != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.attach_file_rounded,
                                    size: 14, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _pendingAttachment!.name,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _pendingAttachment = null),
                                  child: Icon(Icons.close_rounded,
                                      size: 14, color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],
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
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
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
                              onChanged: (v) =>
                                  setState(() => _replied = v ?? false),
                              activeColor: AppColors.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              side: BorderSide(
                                  color: AppColors.border2, width: 1.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Replied',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textPrimary),
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
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEditing ? 'Save Changes' : 'Add Entry',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
