import 'package:flutter/material.dart';
import '../../services/manual_assistant_service.dart';
import '../../services/document_service.dart';
import 'widgets/qa_candidate_card.dart';
import 'widgets/usage_suggestion_card.dart';
import 'widgets/stale_entry_card.dart';

class TrainAiTab extends StatefulWidget {
  final String userEmail;
  final ManualAssistantService service;

  const TrainAiTab({
    super.key,
    required this.userEmail,
    required this.service,
  });

  @override
  State<TrainAiTab> createState() => _TrainAiTabState();
}

class _TrainAiTabState extends State<TrainAiTab> {
  int _selectedSection = 0;
  int _staleCount = 0;
  final List<String> _sessionHistory = [];

  @override
  void initState() {
    super.initState();
    _loadStaleCount();
  }

  Future<void> _loadStaleCount() async {
    try {
      final result = await widget.service.getStaleCacheEntries(
        userEmail: widget.userEmail,
      );
      if (mounted) {
        setState(() {
          _staleCount = (result['total'] as int?) ?? 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<int>(
            segments: [
              const ButtonSegment(value: 0, label: Text('From Manuals')),
              const ButtonSegment(value: 1, label: Text('From Real Usage')),
              ButtonSegment(
                value: 2,
                label: _staleCount > 0
                    ? Badge(
                        label: Text('$_staleCount'),
                        child: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Text('Needs Review'),
                        ),
                      )
                    : const Text('Needs Review'),
              ),
            ],
            selected: {_selectedSection},
            onSelectionChanged: (Set<int> selection) {
              setState(() => _selectedSection = selection.first);
            },
          ),
        ),
        Expanded(
          child: _buildSectionBody(),
        ),
      ],
    );
  }

  Widget _buildSectionBody() {
    switch (_selectedSection) {
      case 0:
        return _FromManualsSection(
          userEmail: widget.userEmail,
          service: widget.service,
          sessionHistory: _sessionHistory,
          onHistoryChanged: () => setState(() {}),
        );
      case 1:
        return _FromRealUsageSection(
          userEmail: widget.userEmail,
          service: widget.service,
        );
      case 2:
        return _NeedsReviewSection(
          userEmail: widget.userEmail,
          service: widget.service,
          onRefresh: _loadStaleCount,
        );
      default:
        return const Center(child: Text('Section A'));
    }
  }
}

class _FromManualsSection extends StatefulWidget {
  final String userEmail;
  final ManualAssistantService service;
  final List<String> sessionHistory;
  final VoidCallback onHistoryChanged;

  const _FromManualsSection({
    required this.userEmail,
    required this.service,
    required this.sessionHistory,
    required this.onHistoryChanged,
  });

  @override
  State<_FromManualsSection> createState() => _FromManualsSectionState();
}

class _FromManualsSectionState extends State<_FromManualsSection> {
  final DocumentService _docService = DocumentService();
  List<Map<String, dynamic>> _manuals = [];
  int _totalDocsCount = 0;
  String? _loadError;
  String? _selectedManualId;
  String? _selectedManualTitle;
  bool _loadingManuals = true;
  bool _generating = false;
  bool _saving = false;
  int _generatedCount = 0;

  List<Map<String, dynamic>> _candidates = [];
  Set<int> _approvedIndices = {};
  int _skippedCached = 0;

  @override
  void initState() {
    super.initState();
    _loadManuals();
  }

  Future<void> _loadManuals() async {
    setState(() {
      _loadingManuals = true;
      _loadError = null;
    });
    try {
      // Train AI reads from knowledge_documents (spec 072 retired the legacy
      // `manuals` table). Only show documents that finished indexing.
      final docs = await _docService.listDocuments(widget.userEmail);
      final ready = docs.where((d) => d['status'] == 'ready').toList();
      if (mounted) {
        setState(() {
          _manuals = ready;
          _totalDocsCount = docs.length;
          _loadingManuals = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loadingManuals = false;
        });
      }
    }
  }

  Future<void> _generateCandidates() async {
    if (_selectedManualId == null) return;
    setState(() {
      _generating = true;
      _generatedCount = 0;
      _candidates = [];
      _approvedIndices.clear();
    });

    try {
      final result = await widget.service.generateQACandidates(
        manualId: _selectedManualId!,
        userEmail: widget.userEmail,
      );
      final candidates = (result['candidates'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _candidates = candidates;
          _generatedCount = candidates.length;
          _skippedCached = (result['skipped_cached'] as int?) ?? 0;
          _generating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation failed: $e')),
        );
      }
    }
  }

  Future<void> _saveAllApproved() async {
    if (_approvedIndices.isEmpty) return;
    setState(() => _saving = true);

    int savedCount = 0;
    int totalEnglish = 0;
    int totalArabic = 0;
    int failCount = 0;
    String? lastError;

    for (final idx in _approvedIndices.toList()) {
      final candidate = _candidates[idx];
      try {
        final result = await widget.service.saveTrainedEntry(
          question: candidate['question'] as String,
          answer: candidate['answer'] as String,
          editorEmail: widget.userEmail,
          sourceManualId: _selectedManualId,
        );
        savedCount++;
        totalEnglish += (result['englishCount'] as int?) ?? 4;
        totalArabic += (result['arabicCount'] as int?) ?? 3;
      } catch (e) {
        failCount++;
        lastError = e.toString();
      }
    }

    if (mounted) {
      final totalEmbeddings = savedCount + totalEnglish + totalArabic;
      setState(() {
        _saving = false;
        _candidates = [];
        _approvedIndices.clear();
      });

      final manualName = _selectedManualTitle ?? 'Manual';
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      if (savedCount > 0) {
        widget.sessionHistory.add(
          '$manualName — $savedCount pairs saved · $totalEmbeddings embeddings · $ts',
        );
        if (widget.sessionHistory.length > 20) {
          widget.sessionHistory.removeAt(0);
        }
        widget.onHistoryChanged();
      }

      final failDetail = failCount > 0 && lastError != null
          ? ' · $failCount failed — $lastError'
          : (failCount > 0 ? ' · $failCount failed' : '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$savedCount Q&A pairs saved · $totalEmbeddings embeddings created '
            '($totalEnglish English + $totalArabic Arabic)$failDetail',
          ),
          duration: Duration(seconds: failCount > 0 ? 10 : 5),
          backgroundColor: failCount > 0
              ? Theme.of(context).colorScheme.errorContainer
              : null,
        ),
      );
    }
  }

  void _rejectCandidate(int index) {
    setState(() {
      _candidates.removeAt(index);
      _approvedIndices = _approvedIndices
          .map((i) => i > index ? i - 1 : i)
          .toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _loadingManuals
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        initialValue: _selectedManualId,
                        decoration: const InputDecoration(
                          labelText: 'Select a manual',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _manuals.map((m) {
                          return DropdownMenuItem<String>(
                            value: m['id'] as String,
                            child: Text(
                              (m['display_name'] as String?) ?? 'Untitled',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedManualId = val;
                            _selectedManualTitle = _manuals
                                .firstWhere((m) => m['id'] == val)['display_name']
                                as String?;
                          });
                        },
                      ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed:
                    (_selectedManualId != null && !_generating && !_saving)
                        ? _generateCandidates
                        : null,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate Q&A'),
              ),
            ],
          ),
        ),
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Failed to load documents: $_loadError',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadManuals,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        if (_loadError == null && !_loadingManuals && _manuals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _totalDocsCount == 0
                          ? 'No documents uploaded yet. Upload a document in the Documents tab first.'
                          : 'No documents are ready for training. $_totalDocsCount document(s) found but none have status=ready. Check the Documents tab.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_generating)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text('Generating candidates... $_generatedCount / 20'),
              ],
            ),
          ),
        if (_skippedCached > 0 && !_generating)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '$_skippedCached chunks skipped (already cached)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        Expanded(
          child: _candidates.isEmpty && !_generating
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_outlined,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Select a manual above to generate Q&A candidates',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: _candidates.length,
                  itemBuilder: (context, index) {
                    final c = _candidates[index];
                    return QaCandidateCard(
                      question: c['question'] as String? ?? '',
                      answer: c['answer'] as String? ?? '',
                      sourceTitle: c['source_title'] as String? ?? '',
                      isApproved: _approvedIndices.contains(index),
                      onApprove: () {
                        setState(() {
                          if (_approvedIndices.contains(index)) {
                            _approvedIndices.remove(index);
                          } else {
                            _approvedIndices.add(index);
                          }
                        });
                      },
                      onReject: () => _rejectCandidate(index),
                      onEdit: (newQ, newA) {
                        setState(() {
                          _candidates[index] = {
                            ..._candidates[index],
                            'question': newQ,
                            'answer': newA,
                          };
                        });
                      },
                    );
                  },
                ),
        ),
        // Session history
        if (widget.sessionHistory.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.green.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.sessionHistory
                  .map((h) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                h,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        // Sticky bottom bar
        if (_candidates.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_approvedIndices.length} approved',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                ElevatedButton.icon(
                  onPressed: (_approvedIndices.isNotEmpty && !_saving)
                      ? _saveAllApproved
                      : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Save All Approved'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FromRealUsageSection extends StatefulWidget {
  final String userEmail;
  final ManualAssistantService service;

  const _FromRealUsageSection({
    required this.userEmail,
    required this.service,
  });

  @override
  State<_FromRealUsageSection> createState() => _FromRealUsageSectionState();
}

class _FromRealUsageSectionState extends State<_FromRealUsageSection> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  bool _approvingAll = false;
  final Set<int> _loadingIndices = {};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _loading = true);
    try {
      final list = await widget.service.getRealUsageSuggestions(
        userEmail: widget.userEmail,
      );
      if (mounted) setState(() { _suggestions = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToCache(int index, {String? question, String? answer}) async {
    final s = _suggestions[index];
    setState(() => _loadingIndices.add(index));
    try {
      await widget.service.saveTrainedEntry(
        question: question ?? s['question'] as String,
        answer: answer ?? s['answer'] as String,
        editorEmail: widget.userEmail,
      );
      if (mounted) {
        setState(() {
          _loadingIndices.remove(index);
          _suggestions.removeAt(index);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to cache with variants')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingIndices.remove(index));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _approveAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve All'),
        content: Text(
          'Add all ${_suggestions.length} suggestions to the cache with paraphrase variants?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve All')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _approvingAll = true);
    int saved = 0;
    int failed = 0;
    for (int i = _suggestions.length - 1; i >= 0; i--) {
      final s = _suggestions[i];
      try {
        await widget.service.saveTrainedEntry(
          question: s['question'] as String,
          answer: s['answer'] as String,
          editorEmail: widget.userEmail,
        );
        saved++;
        if (mounted) setState(() => _suggestions.removeAt(i));
      } catch (e) {
        failed++;
      }
    }
    if (mounted) {
      setState(() => _approvingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$saved added to cache${failed > 0 ? ' · $failed failed' : ''}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_suggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No suggestions yet. As technicians use the AI\nassistant, highly-rated answers will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Questions technicians asked that got good ratings — not yet in the cache',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSuggestions,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final s = _suggestions[index];
                return UsageSuggestionCard(
                  question: s['question'] as String? ?? '',
                  answer: s['answer'] as String? ?? '',
                  ratingCount: (s['rating_count'] as int?) ?? 0,
                  lastAskedAt: s['last_asked_at'] as String? ?? '',
                  isLoading: _loadingIndices.contains(index),
                  onAddToCache: () => _addToCache(index),
                  onEditThenAdd: (newQ, newA) =>
                      _addToCache(index, question: newQ, answer: newA),
                  onDismiss: () {
                    setState(() => _suggestions.removeAt(index));
                  },
                );
              },
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_suggestions.isNotEmpty && !_approvingAll)
                  ? _approveAll
                  : null,
              icon: _approvingAll
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.done_all, size: 18),
              label: const Text('Approve All'),
            ),
          ),
        ),
      ],
    );
  }
}

class _NeedsReviewSection extends StatefulWidget {
  final String userEmail;
  final ManualAssistantService service;
  final VoidCallback onRefresh;

  const _NeedsReviewSection({
    required this.userEmail,
    required this.service,
    required this.onRefresh,
  });

  @override
  State<_NeedsReviewSection> createState() => _NeedsReviewSectionState();
}

class _NeedsReviewSectionState extends State<_NeedsReviewSection> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  final Set<int> _loadingIndices = {};

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    try {
      final result = await widget.service.getStaleCacheEntries(
        userEmail: widget.userEmail,
      );
      final list = (result['stale_entries'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      if (mounted) setState(() { _entries = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(int index, {String? updatedQ, String? updatedA}) async {
    final entry = _entries[index];
    setState(() => _loadingIndices.add(index));
    try {
      await widget.service.markCacheReviewed(
        qaId: entry['qa_id'] as String,
        action: 'confirm',
        userEmail: widget.userEmail,
        updatedQuestion: updatedQ,
        updatedAnswer: updatedA,
      );
      if (mounted) {
        setState(() {
          _loadingIndices.remove(index);
          _entries.removeAt(index);
        });
        widget.onRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry confirmed as valid')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingIndices.remove(index));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _remove(int index) async {
    final entry = _entries[index];
    setState(() => _loadingIndices.add(index));
    try {
      await widget.service.markCacheReviewed(
        qaId: entry['qa_id'] as String,
        action: 'delete',
        userEmail: widget.userEmail,
      );
      if (mounted) {
        setState(() {
          _loadingIndices.remove(index);
          _entries.removeAt(index);
        });
        widget.onRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry and variants removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingIndices.remove(index));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 48, color: Colors.green.shade400),
            const SizedBox(height: 12),
            Text(
              'All cached answers are up to date',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final e = _entries[index];
        return StaleEntryCard(
          qaId: e['qa_id'] as String? ?? '',
          question: e['question'] as String? ?? '',
          answer: e['answer'] as String? ?? '',
          manualTitle: e['manual_title'] as String? ?? 'Unknown',
          daysSinceUpdate: (e['days_since_update'] as int?) ?? 0,
          isLoading: _loadingIndices.contains(index),
          onConfirm: () => _confirm(index),
          onEditConfirm: (newQ, newA) =>
              _confirm(index, updatedQ: newQ, updatedA: newA),
          onRemove: () => _remove(index),
        );
      },
    );
  }
}
