import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/ai_insights_service.dart';

class AiInsightsCard extends StatefulWidget {
  final String email;
  final String userRole;

  const AiInsightsCard({
    super.key,
    required this.email,
    required this.userRole,
  });

  @override
  State<AiInsightsCard> createState() => _AiInsightsCardState();
}

class _AiInsightsCardState extends State<AiInsightsCard> {
  String? _insightText;
  bool _loading = false;
  DateTime? _generatedAt;
  String _selectedType = 'overview';
  String _selectedLanguage = 'en';
  int _dateRangeDays = 30;
  String? _error;

  Future<void> _generateInsight() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AiInsightsService().getInsight(
        insightType: _selectedType,
        email: widget.email,
        userRole: widget.userRole,
        dateRangeDays: _dateRangeDays,
        language: _selectedLanguage,
      );
      if (!mounted) return;
      setState(() {
        _insightText = result['insight'] as String;
        _generatedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Widget _buildTypeChip(String label, String value) {
    final selected = _selectedType == value;
    return GestureDetector(
      onTap: () {
        if (_selectedType != value) {
          setState(() { _selectedType = value; });
          _generateInsight();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageChip(String label, String value) {
    final selected = _selectedLanguage == value;
    return GestureDetector(
      onTap: () {
        if (_selectedLanguage != value) {
          setState(() { _selectedLanguage = value; });
          _generateInsight();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRangeChip(String label, int value) {
    final selected = _dateRangeDays == value;
    return GestureDetector(
      onTap: () {
        if (_dateRangeDays != value) {
          setState(() { _dateRangeDays = value; });
          _generateInsight();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Generated just now';
    if (diff.inMinutes < 60) return 'Generated ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Generated ${diff.inHours}h ago';
    return 'Generated ${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Text(
                'AI Insights',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                onPressed: _loading ? null : _generateInsight,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Type selector row
          Row(
            children: [
              _buildTypeChip('Overview', 'overview'),
              const SizedBox(width: 8),
              _buildTypeChip('Systems', 'system_status'),
              const SizedBox(width: 8),
              _buildTypeChip('Trends', 'trends'),
            ],
          ),

          const SizedBox(height: 8),

          // Language toggle and date range row
          Row(
            children: [
              _buildLanguageChip('EN', 'en'),
              const SizedBox(width: 6),
              _buildLanguageChip('AR', 'ar'),
              const SizedBox(width: 16),
              _buildRangeChip('7d', 7),
              const SizedBox(width: 6),
              _buildRangeChip('14d', 14),
              const SizedBox(width: 6),
              _buildRangeChip('30d', 30),
              const SizedBox(width: 6),
              _buildRangeChip('90d', 90),
            ],
          ),

          const SizedBox(height: 12),

          // Body
          if (_loading)
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
            )
          else if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: AppColors.dangerText, fontSize: 13),
            )
          else if (_insightText != null)
            Text(
              _insightText!,
              textDirection: _selectedLanguage == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            )
          else
            Text(
              'Tap refresh to generate insights',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),

          // Footer
          if (_generatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _relativeTime(_generatedAt!),
                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
