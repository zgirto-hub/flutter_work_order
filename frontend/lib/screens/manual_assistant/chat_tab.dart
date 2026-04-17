import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';
import '../../models/manual_qa_answer.dart';
import '../../models/manual_source.dart';
import '../../services/manual_assistant_service.dart';
import '../../services/ai_provider_service.dart';
import '../../widgets/ai_provider_chip.dart';
import 'widgets/answer_card.dart';

class ChatMessage {
  final String question;
  final ManualQaAnswer? answer;
  final bool loading;
  final String? error;

  ChatMessage({
    required this.question,
    this.answer,
    this.loading = false,
    this.error,
  });
}

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ManualAssistantService _service = ManualAssistantService();
  final AiProviderService _providerService = AiProviderService();
  final TextEditingController _questionController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _history =
      []; // conversation memory (Layer 3)
  String? _sessionSummary;
  List<Map<String, dynamic>> _models = [];
  String? _selectedModel;
  bool _loading = false;
  bool _streaming = false;
  http.Client? _activeClient;
  String _partialAnswer = '';
  String _providerDisplayName = 'Local (Ollama)';
  String? _lastResponseProviderDisplayName;
  bool _fallbackUsed = false;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    try {
      final resp = await _providerService.listProviders();
      if (mounted) {
        setState(() {
          final activeProvider = resp.providers.firstWhere(
            (p) => p.key == resp.active,
            orElse: () => resp.providers.first,
          );
          _providerDisplayName = activeProvider.displayName;
        });
      }
    } catch (e) {
      // Use default
    }
  }

  Future<void> _loadModels() async {
    final models = await _service.listModels();
    if (mounted) setState(() => _models = models);
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(question: question, loading: true));
      _questionController.clear();
      _loading = true;
      _streaming = true;
      _partialAnswer = '';
    });

    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';

      final stream = _service.askQuestionStream(question, null,
          userEmail: email,
          model: _selectedModel,
          history: _history,
          sessionSummary: _sessionSummary);

      await for (final event in stream) {
        if (event.token != null) {
          setState(() {
            _partialAnswer += event.token!;
          });
        } else if (event.metadata != null) {
          final metadata = event.metadata!;
          final answer = ManualQaAnswer(
            answer: _partialAnswer,
            sources: (metadata['sources'] as List<dynamic>?)
                    ?.map((s) => ManualSource(
                          manualId: s['manual_id'] ?? s['document_id'] ?? '',
                          manualTitle:
                              s['manual_title'] ?? s['display_name'] ?? '',
                          chunkIndex: 0,
                          sourcePage: s['source_page'] ?? s['page_number'],
                          contentPreview:
                              s['content'] ?? s['section_title'] ?? '',
                          displayName: s['display_name'],
                          sectionTitle: s['section_title'],
                          pageNumber: s['page_number'],
                          score: (s['score'] as num?)?.toDouble(),
                        ))
                    .toList() ??
                [],
            grounded: metadata['grounded'] ?? false,
            isVerified: metadata['is_verified'] ?? false,
            providerDisplayName:
                metadata['provider_display_name'] ?? 'Local (Ollama)',
            fallbackUsed: metadata['fallback_used'] ?? false,
            sessionSummary: metadata['session_summary'],
            searchQuery: metadata['search_query'],
          );

          if (answer.sessionSummary != null) {
            _sessionSummary = answer.sessionSummary;
          }

          _history.add({'question': question, 'answer': _partialAnswer});

          setState(() {
            _messages.removeLast();
            _messages.add(ChatMessage(question: question, answer: answer));
            _streaming = false;
            _loading = false;
            _lastResponseProviderDisplayName = answer.providerDisplayName;
            _fallbackUsed = answer.fallbackUsed == true;
          });
        } else if (event.error != null) {
          setState(() {
            _messages.removeLast();
            _messages.add(ChatMessage(
              question: question,
              answer: ManualQaAnswer(
                answer: _partialAnswer.isNotEmpty
                    ? _partialAnswer
                    : 'Connection lost',
                sources: [],
                grounded: false,
              ),
              error: event.error,
            ));
            _streaming = false;
            _loading = false;
          });
        }
      }
    } on ManualAskException catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(
          question: question,
          error: e.message,
        ));
        _streaming = false;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(
          question: question,
          error: 'An error occurred. Please try again.',
        ));
        _streaming = false;
        _loading = false;
      });
    }
  }

  void _cancelStream() {
    _activeClient?.close();
    setState(() {
      _streaming = false;
      _loading = false;
    });
  }

  bool get _canSend => !_loading && !_streaming;

  Future<void> _handleRate(
      String questionText, ManualQaAnswer answer, String rating) async {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final sourceChunks = answer.sources
        .map((s) => {
              'manual_title': s.manualTitle,
              'source_page': s.sourcePage,
              'content': s.contentPreview,
            })
        .toList();

    try {
      await _service.rateAnswer(
        questionText: answer.searchQuery ?? questionText,
        answerText: answer.answer,
        sourceChunks: sourceChunks,
        rating: rating,
        raterEmail: email,
        manualId: null,
        modelUsed: answer.model,
        validatedQaId: answer.verifiedSource?.validatedQaId,
        sessionSummary: _sessionSummary,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit rating'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        if (_models.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                const Spacer(),
                SizedBox(
                  width: 160,
                  child: DropdownButton<String?>(
                    value: _selectedModel,
                    hint: const Text('Default model',
                        style: TextStyle(fontSize: 12)),
                    isExpanded: true,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodyMedium?.color),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Default model'),
                      ),
                      ..._models.map((m) => DropdownMenuItem<String?>(
                            value: m['name'] as String,
                            child: Text(
                              '${m['name']} (${m['size_gb']}G)',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedModel = value);
                    },
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ask the AI Assistant',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              AiProviderChip(
                providerDisplayName: _lastResponseProviderDisplayName != null
                    ? _lastResponseProviderDisplayName!
                    : _providerDisplayName,
                fallbackUsed: _fallbackUsed,
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                if (msg.loading) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(48, 8, 8, 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(msg.question,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                      const ListTile(
                        title:
                            Text('Thinking...', style: TextStyle(fontSize: 13)),
                        leading: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  );
                }
                if (msg.error != null) {
                  return ListTile(
                    title: Text(msg.error!,
                        style: const TextStyle(color: Colors.red)),
                    subtitle: Text(msg.question),
                    trailing: TextButton(
                      onPressed: () {
                        setState(() {
                          _messages.removeAt(index);
                        });
                      },
                      child: const Text('Dismiss'),
                    ),
                  );
                }
                if (msg.answer != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Question bubble
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(48, 8, 8, 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            msg.question,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      // Answer card
                      AnswerCard(
                        answer: msg.answer!,
                        questionText: msg.question,
                        onRate: (rating) => _handleRate(
                          msg.question,
                          msg.answer!,
                          rating,
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        // Input
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  decoration: const InputDecoration(
                    hintText: 'Ask a question...',
                    border: OutlineInputBorder(),
                  ),
                  enabled: _canSend,
                  onSubmitted: (_) => _sendQuestion(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _canSend ? _sendQuestion : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
