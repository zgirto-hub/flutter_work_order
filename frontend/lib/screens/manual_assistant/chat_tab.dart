import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../models/manual_qa_answer.dart';
import '../../services/manual_assistant_service.dart';
import '../../services/ai_provider_service.dart';
import '../../widgets/ai_provider_chip.dart';
import 'widgets/answer_card.dart';
import 'widgets/feedback_reason_sheet.dart';

class ChatMessage {
  final String question;
  final ManualQaAnswer? answer;
  final bool loading;
  final String? error;
  final String? ratingId;

  ChatMessage({
    required this.question,
    this.answer,
    this.loading = false,
    this.error,
    this.ratingId,
  });

  ChatMessage copyWith({String? ratingId}) {
    return ChatMessage(
      question: question,
      answer: answer,
      loading: loading,
      error: error,
      ratingId: ratingId ?? this.ratingId,
    );
  }
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
          _partialAnswer += event.token!;
          // Show progressive text as tokens arrive
          final partialQaAnswer = ManualQaAnswer(
            answer: _partialAnswer,
            sources: [],
            grounded: false,
          );
          setState(() {
            _messages.removeLast();
            _messages.add(ChatMessage(
              question: question,
              answer: partialQaAnswer,
            ));
          });
        } else if (event.metadata != null) {
          final metadata = event.metadata!;
          // Inject the streamed answer text into the metadata, then use
          // fromJson which correctly parses all fields (latencyBreakdown,
          // manualsConsulted, retrievalInfo, verifiedSource, etc.)
          metadata['answer'] = _partialAnswer;
          final answer = ManualQaAnswer.fromJson(metadata);

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
      if (!_streaming && !_loading) return; // cancelled — already cleaned up
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
      if (!_streaming && !_loading) return; // cancelled — already cleaned up
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
    final question = _messages.isNotEmpty ? _messages.last.question : '';
    final partialAnswer = ManualQaAnswer(
      answer: _partialAnswer.isNotEmpty ? _partialAnswer : 'Cancelled',
      sources: [],
      grounded: false,
    );
    _service.cancelStream();
    setState(() {
      if (_messages.isNotEmpty && _messages.last.loading) {
        _messages.removeLast();
      }
      _messages.add(ChatMessage(
        question: question,
        answer: partialAnswer,
      ));
      _streaming = false;
      _loading = false;
    });
  }

  bool get _canSend => !_loading && !_streaming;

  Future<void> _handleRate(
      String questionText, ManualQaAnswer answer, String rating, int messageIndex) async {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final sourceChunks = answer.sources
        .map((s) => {
              'manual_title': s.manualTitle,
              'source_page': s.sourcePage,
              'content': s.contentPreview,
            })
        .toList();

    try {
      final ratingId = await _service.rateAnswer(
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

      setState(() {
        _messages[messageIndex] = _messages[messageIndex].copyWith(ratingId: ratingId);
      });

      if (rating == 'negative' && mounted) {
        if (!mounted) return;
        final result = await FeedbackReasonSheet.show(context);
        if (result != null) {
          try {
            await _service.saveFeedback(
              ratingId: ratingId,
              feedbackReason: result.reason,
              userEmail: email,
              feedbackComment: result.comment,
            );
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not save feedback'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final hintKey = 'rating_undo_hint_shown_$email';
      if (!prefs.containsKey(hintKey)) {
        await prefs.setBool(hintKey, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tap the thumb again to remove your rating.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
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

  Future<void> _handleUnrate(int messageIndex) async {
    final msg = _messages[messageIndex];
    final ratingId = msg.ratingId;
    if (ratingId == null) return;

    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final previousRatingId = ratingId;

    setState(() {
      _messages[messageIndex] = msg.copyWith(ratingId: null);
    });

    try {
      await _service.deleteRating(ratingId: ratingId, userEmail: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rating removed.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _messages[messageIndex] = msg.copyWith(ratingId: previousRatingId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove rating — please try again.'),
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
                        ratingId: msg.ratingId,
                        isStreaming:
                            _streaming && index == _messages.length - 1,
                        onRate: (rating) => _handleRate(
                          msg.question,
                          msg.answer!,
                          rating,
                          index,
                        ),
                        onUnrate: () => _handleUnrate(index),
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
                  enabled: !_loading,
                  onSubmitted: (_) => _sendQuestion(),
                ),
              ),
              const SizedBox(width: 8),
              _streaming
                  ? IconButton(
                      onPressed: _cancelStream,
                      icon: const Icon(Icons.stop),
                      color: Colors.red,
                      tooltip: 'Stop streaming',
                    )
                  : IconButton(
                      onPressed: _canSend ? _sendQuestion : null,
                      icon: const Icon(Icons.send),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_streaming) {
      _service.cancelStream();
    }
    _questionController.dispose();
    super.dispose();
  }
}
