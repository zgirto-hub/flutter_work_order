import 'package:flutter/material.dart';
import '../services/dictation_service.dart';
import '../theme/app_theme.dart';

class DictationButton extends StatefulWidget {
  final TextEditingController controller;
  final String language;
  final bool enabled;

  const DictationButton({
    super.key,
    required this.controller,
    required this.language,
    this.enabled = true,
  });

  @override
  State<DictationButton> createState() => _DictationButtonState();
}

class _DictationButtonState extends State<DictationButton>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isAvailable = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.reverse();
      } else if (status == AnimationStatus.dismissed && _isRecording) {
        _pulseController.forward();
      }
    });
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _isAvailable = await DictationService().initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_isRecording) {
      DictationService().stopListening();
    }
    _pulseController.dispose();
    super.dispose();
  }

  String _getLocaleId() {
    return widget.language == 'ar' ? 'ar-SA' : 'en-US';
  }

  Future<void> _toggleRecording() async {
    if (!widget.enabled || !_isAvailable) return;

    final service = DictationService();

    if (_isRecording) {
      await service.stopListening();
      if (mounted) {
        setState(() => _isRecording = false);
      }
      _pulseController.stop();
      _pulseController.reset();
    } else {
      final fieldId = widget.controller.hashCode.toString();

      await service.startListening(
        localeId: _getLocaleId(),
        fieldId: fieldId,
        onResult: (recognizedWords) {
          if (!mounted) return;
          final currentText = widget.controller.text.trim();
          if (currentText.isEmpty) {
            widget.controller.text = recognizedWords;
          } else {
            widget.controller.text = '$currentText $recognizedWords';
          }
        },
        onError: (errorMsg) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMsg),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
          ));
          setState(() => _isRecording = false);
          _pulseController.stop();
          _pulseController.reset();
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isRecording = false);
          _pulseController.stop();
          _pulseController.reset();
        },
      );

      if (mounted) {
        setState(() => _isRecording = true);
        _pulseController.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAvailable) {
      return const SizedBox.shrink();
    }

    return IconButton(
      onPressed: widget.enabled ? _toggleRecording : null,
      icon: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isRecording ? _pulseAnimation.value : 1.0,
            child: Icon(
              _isRecording ? Icons.mic_off : Icons.mic,
              color: _isRecording
                  ? AppColors.dangerText
                  : widget.enabled
                      ? AppColors.accent
                      : AppColors.textTertiary,
            ),
          );
        },
      ),
      tooltip: _isRecording ? 'Stop recording' : 'Start dictation',
    );
  }
}
