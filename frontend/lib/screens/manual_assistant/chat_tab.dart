import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/manual.dart';
import '../../models/manual_qa_answer.dart';
import '../../services/manual_assistant_service.dart';
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

class _ChatTabState extends State<ChatTab> {
  final ManualAssistantService _service = ManualAssistantService();
  final TextEditingController _questionController = TextEditingController();
  final List<ChatMessage> _messages = [];
  List<Manual> _manuals = [];
  String? _selectedManualId;
  bool _loading = false;
  bool _manualsLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadManuals();
  }

  Future<void> _loadManuals() async {
    try {
      final result = await _service.listManuals();
      setState(() {
        _manuals = result['manuals'] as List<Manual>;
        _manualsLoading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _loadError = e.toString();
          _manualsLoading = false;
        });
    }
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    final manualIdFilter = _selectedManualId;

    setState(() {
      _messages.add(ChatMessage(question: question, loading: true));
      _questionController.clear();
      _loading = true;
    });

    try {
      final email =
          Supabase.instance.client.auth.currentUser?.email ?? '';
      final answer = await _service.askQuestion(question, manualIdFilter,
          userEmail: email);
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(question: question, answer: answer));
        _loading = false;
      });
    } on ManualAskException catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(
          question: question,
          error: e.message,
        ));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(
          question: question,
          error: 'An error occurred. Please try again.',
        ));
        _loading = false;
      });
    }
  }

  bool get _canSend => !_loading && _manuals.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter dropdown
        if (_manuals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<String?>(
              value: _selectedManualId,
              hint: const Text('All manuals'),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All manuals'),
                ),
                ..._manuals.map((m) => DropdownMenuItem<String?>(
                      value: m.id,
                      child: Text(m.title),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedManualId = value;
                });
              },
            ),
          ),
        // Messages
        Expanded(
          child: _manualsLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_loadError!,
                              style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _loadManuals,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _manuals.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'No manuals uploaded yet. Visit the Manuals tab to upload one.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            if (msg.loading) {
                              return const ListTile(
                                title: Text('Thinking...'),
                                leading: CircularProgressIndicator(),
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
                              return AnswerCard(answer: msg.answer!);
                            }
                            return ListTile(
                              title: Text(msg.question),
                              subtitle: const Text('Question'),
                            );
                          },
                        ),
        ),
        // Input
        if (_manuals.isNotEmpty)
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
