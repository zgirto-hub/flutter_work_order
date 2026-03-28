import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ValidatedTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? Function(String?)? validator;
  final bool validateOnChange;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLines;
  final int? maxLength;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final void Function(String)? onChanged;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;

  const ValidatedTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.validator,
    this.validateOnChange = true,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  @override
  State<ValidatedTextField> createState() => _ValidatedTextFieldState();
}

class _ValidatedTextFieldState extends State<ValidatedTextField> {
  String? _errorText;
  late FocusNode _focusNode;
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _hasInteracted) {
      _validate();
    }
  }

  void _validate() {
    if (widget.validator != null) {
      setState(() {
        _errorText = widget.validator!(widget.controller?.text);
      });
    }
  }

  void _onChanged(String value) {
    setState(() {
      _hasInteracted = true;
    });

    if (widget.validateOnChange && _hasInteracted) {
      _validate();
    }

    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: widget.keyboardType,
          obscureText: widget.obscureText,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          onChanged: _onChanged,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.suffixIcon,
            errorText: _errorText,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            filled: true,
            fillColor: AppColors.bgSurface,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.dangerText, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.dangerText, width: 2),
            ),
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.error_outline, size: 14, color: AppColors.dangerText),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.dangerText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
