import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/manual_assistant_service.dart';

class VerifiedAnswersTab extends StatefulWidget {
  final String userEmail;

  const VerifiedAnswersTab({
    super.key,
    required this.userEmail,
  });

  @override
  State<VerifiedAnswersTab> createState() => _VerifiedAnswersTabState();
}

class _VerifiedAnswersTabState extends State<VerifiedAnswersTab>
    with AutomaticKeepAliveClientMixin {
  final ManualAssistantService _service = ManualAssistantService();

  List<Map<String, dynamic>> _entries = [];
  int _totalCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _offset = 0;
  final int _limit = 50;
  int _currentRequestId = 0;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _offset = 0;
      _loadEntries();
    });
  }

  Future<void> _loadEntries({bool append = false}) async {
    final localRequestId = ++_currentRequestId;

    String? searchQuery;
    if (_searchController.text.isNotEmpty) {
      searchQuery = _searchController.text;
    }

    try {
      final result = await _service.getVerifiedAnswers(
        userEmail: widget.userEmail,
        search: searchQuery,
        limit: _limit,
        offset: append ? _offset : 0,
      );

      if (!mounted || localRequestId != _currentRequestId) return;

      setState(() {
        if (append) {
          _entries.addAll(List<Map<String, dynamic>>.from(result['items']));
          _offset = _entries.length;
        } else {
          _entries = List<Map<String, dynamic>>.from(result['items']);
          _offset = _entries.length;
          _totalCount = result['count'] as int;
        }
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || localRequestId != _currentRequestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  void _loadMore() {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
    });
    _loadEntries(append: true);
  }

  bool get _hasMore => _entries.length < _totalCount;

  Future<void> _refresh() async {
    _offset = 0;
    await _loadEntries();
  }

  void _showEditDialog(Map<String, dynamic> entry) {
    final questionCtrl =
        TextEditingController(text: entry['question_text'] as String? ?? '');
    final answerCtrl =
        TextEditingController(text: entry['validated_answer'] as String? ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Verified Answer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: questionCtrl,
                decoration: const InputDecoration(labelText: 'Question'),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: answerCtrl,
                decoration: const InputDecoration(labelText: 'Answer'),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _confirmDelete(entry);
            },
            tooltip: 'Delete',
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (questionCtrl.text.isEmpty || answerCtrl.text.isEmpty) return;
              Navigator.pop(context);
              await _saveEdit(entry, questionCtrl.text, answerCtrl.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEdit(Map<String, dynamic> entry, String questionText,
      String answerText) async {
    try {
      final result = await _service.updateVerifiedAnswer(
        qaId: entry['id'] as String,
        questionText: questionText,
        validatedAnswer: answerText,
        editorEmail: widget.userEmail,
      );

      if (mounted) {
        final index = _entries.indexWhere((e) => e['id'] == entry['id']);
        if (index != -1) {
          setState(() {
            _entries[index] = result;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verified answer updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().contains('timed out')
            ? 'Embedding timed out — please try again'
            : 'Failed to update: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  void _confirmDelete(Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Verified Answer?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry['question_text'] as String? ?? '',
              maxLines: 3,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            Text(
              'This action is permanent. The Q&A will no longer be used by the AI assistant.',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await _deleteEntry(entry);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    try {
      await _service.deleteVerifiedAnswer(
        qaId: entry['id'] as String,
        editorEmail: widget.userEmail,
      );

      if (mounted) {
        setState(() {
          _entries.removeWhere((e) => e['id'] == entry['id']);
          _totalCount--;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verified answer deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEntries,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search questions...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3),
          child: Row(
            children: [
              Text(
                '$_totalCount verified answers',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        if (_entries.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_outlined,
                      size: 64, color: Colors.green.shade300),
                  const SizedBox(height: 16),
                  Text(
                    _searchController.text.isNotEmpty
                        ? 'No matching answers found.'
                        : 'No verified answers yet.',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          )
        else
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _entries.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _entries.length && _hasMore) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: OutlinedButton(
                        onPressed: _loadingMore ? null : _loadMore,
                        child: _loadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Load More'),
                      ),
                    ),
                  );
                }

                final entry = _entries[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(
                      entry['question_text'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry['validated_answer'] as String? ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.thumb_up, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              '${entry['thumbs_up_count'] ?? 0}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.thumb_down, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              '${entry['thumbs_down_count'] ?? 0}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => _showEditDialog(entry),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
