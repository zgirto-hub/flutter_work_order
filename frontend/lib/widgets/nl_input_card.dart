import 'package:flutter/material.dart';
import '../services/dictation_service.dart';
import '../theme/app_theme.dart';
import 'dictation_button.dart';

class NlInputCard extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String text, String language)? onGenerate;
  final bool isGenerating;
  final bool collapsible;

  const NlInputCard({
    super.key,
    required this.controller,
    this.onGenerate,
    this.isGenerating = false,
    this.collapsible = false,
  });

  @override
  State<NlInputCard> createState() => _NlInputCardState();
}

class _NlInputCardState extends State<NlInputCard> {
  String _language = 'en';
  bool _expanded = true;
  bool _speechAvailable = DictationService.webSpeechApiLikelyAvailable;

  @override
  void initState() {
    super.initState();
    DictationService().initialize().then((v) {
      if (mounted) {
        setState(() => _speechAvailable = v);
      }
    });
  }

  Widget _buildLanguageChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _language == value,
      onSelected: (selected) {
        if (selected) {
          setState(() => _language = value);
        }
      },
      selectedColor: AppColors.accent.withValues(alpha: 0.3),
      labelStyle: TextStyle(
        color: _language == value ? AppColors.accent : AppColors.textSecondary,
        fontSize: 12,
      ),
    );
  }

  Widget _buildCollapsed() {
    return ListTile(
      leading: const Icon(Icons.auto_awesome, size: 18),
      title: const Text("AI Work Order"),
      trailing: IconButton(
        icon: const Icon(Icons.expand_more),
        onPressed: () => setState(() => _expanded = true),
      ),
    );
  }

  Widget _buildExpanded() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18),
              const SizedBox(width: 8),
              const Text(
                "AI Work Order",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (widget.collapsible)
                IconButton(
                  icon: const Icon(Icons.expand_less),
                  onPressed: () => setState(() => _expanded = false),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            maxLines: 3,
            readOnly: widget.isGenerating,
            decoration: const InputDecoration(
              hintText: "Describe your work order in a sentence...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildLanguageChip('EN', 'en'),
              const SizedBox(width: 8),
              _buildLanguageChip('AR', 'ar'),
              const SizedBox(width: 8),
              if (_speechAvailable)
                DictationButton(
                  controller: widget.controller,
                  language: _language,
                  enabled: !widget.isGenerating,
                ),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  final canGenerate =
                      !widget.isGenerating && value.text.trim().isNotEmpty;
                  return ElevatedButton.icon(
                    icon: Icon(widget.isGenerating
                        ? Icons.hourglass_empty
                        : Icons.auto_awesome),
                    label: Text(
                        widget.isGenerating ? "Generating..." : "Generate"),
                    onPressed: canGenerate
                        ? () => widget.onGenerate
                            ?.call(widget.controller.text.trim(), _language)
                        : null,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsible) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        child: Card(
          elevation: 2,
          child: AnimatedCrossFade(
            firstChild: _buildExpanded(),
            secondChild: _buildCollapsed(),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Card(
        elevation: 2,
        child: _buildExpanded(),
      ),
    );
  }
}
