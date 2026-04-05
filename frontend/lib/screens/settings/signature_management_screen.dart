import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/app_theme.dart';
import '../../config.dart';
import '../../services/signature_service.dart';
import '../../widgets/signature_canvas.dart';

class SignatureManagementScreen extends StatefulWidget {
  const SignatureManagementScreen({super.key});

  @override
  State<SignatureManagementScreen> createState() =>
      _SignatureManagementScreenState();
}

class _SignatureManagementScreenState extends State<SignatureManagementScreen> {
  final SignatureService _signatureService = SignatureService();
  String? _currentUserId;
  String? _savedSignaturePath;
  bool _loading = true;
  int _sigCacheBuster = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      final profileRes = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/users/me?email=${Uri.encodeComponent(user.email ?? '')}'),
      );
      if (profileRes.statusCode == 200) {
        final body = jsonDecode(profileRes.body) as Map<String, dynamic>;
        final profileData = (body['user'] as Map<String, dynamic>?) ?? {};
        final userId = profileData['id'] as String?;
        if (userId != null && userId.isNotEmpty) {
          _currentUserId = userId;
          final path = await _signatureService.fetchUserSignature(userId);
          if (mounted) setState(() => _savedSignaturePath = path);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _resolveFileUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    final base = AppConfig.baseUrl.replaceFirst('/api', '');
    return '$base$path?v=$_sigCacheBuster';
  }

  Future<void> _drawSignature() async {
    if (_currentUserId == null) return;
    final base64 = await SignatureCanvas.show(context);
    if (base64 == null || !mounted) return;
    await _saveSignature(base64Data: base64);
  }

  Future<void> _uploadSignature() async {
    if (_currentUserId == null || _loading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    if (file.bytes == null || file.bytes!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not read file data. Please try again.'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }
    await _saveSignature(fileBytes: file.bytes, fileName: file.name);
  }

  Future<void> _saveSignature(
      {String? base64Data, Uint8List? fileBytes, String? fileName}) async {
    if (_currentUserId == null) return;
    setState(() => _loading = true);
    try {
      final path = await _signatureService.saveUserSignature(
        userId: _currentUserId!,
        base64Data: base64Data,
        fileBytes: fileBytes,
        fileName: fileName,
      );
      if (mounted) {
        setState(() {
          _savedSignaturePath = path;
          _sigCacheBuster = DateTime.now().millisecondsSinceEpoch;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save signature: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _removeSignature() async {
    if (_currentUserId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Signature'),
        content:
            const Text('Are you sure you want to remove your saved signature?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await _signatureService.deleteUserSignature(_currentUserId!);
      if (mounted) setState(() => _savedSignaturePath = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to remove signature: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(9),
                        border:
                            Border.all(color: AppColors.border2, width: 0.5),
                      ),
                      child: Icon(Icons.arrow_back_rounded,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                  Text('My Signature',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3)),
                ],
              ),
              const SizedBox(height: 24),

              // Content
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                          strokeWidth: 2,
                        ),
                      )
                    : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final hasSignature =
        _savedSignaturePath != null && _savedSignaturePath!.isNotEmpty;

    return Column(
      children: [
        // Signature preview area
        Container(
          width: double.infinity,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: hasSignature
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _resolveFileUrl(_savedSignaturePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              size: 32, color: AppColors.textTertiary),
                          const SizedBox(height: 8),
                          Text('Preview unavailable',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw_outlined,
                          size: 36, color: AppColors.textTertiary),
                      const SizedBox(height: 8),
                      Text('No signature saved',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text('Draw or upload your signature below',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 24),

        // Action buttons
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.draw_outlined, size: 18),
            label: Text(hasSignature ? 'Draw New Signature' : 'Draw Signature'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _loading ? null : _drawSignature,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: const Text('Upload Image'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _loading ? null : _uploadSignature,
          ),
        ),
        if (hasSignature) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove Signature'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red, width: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _loading ? null : _removeSignature,
            ),
          ),
        ],
      ],
    );
  }
}
