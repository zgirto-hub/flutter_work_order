// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

// Web-only JS interop
import 'webauthn_service_web.dart'
    if (dart.library.io) 'webauthn_service_stub.dart';

class WebAuthnService {
  // ── Check if this device supports Face ID / biometrics ───────────────────

  static Future<bool> isSupported() async {
    if (!kIsWeb) return false;
    try {
      return await checkWebAuthnSupport();
    } catch (_) {
      return false;
    }
  }

  // ── Check if user has Face ID registered ─────────────────────────────────

  static Future<bool> isRegistered(String email) async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/webauthn/status?email=$email'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['registered'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Register Face ID (called after normal login) ──────────────────────────

  static Future<void> register({
    required String email,
    String deviceName = 'My Device',
  }) async {
    // Step 1: Get options from backend
    final beginRes = await http.post(
      Uri.parse('${AppConfig.baseUrl}/webauthn/register-begin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (beginRes.statusCode != 200) {
      throw Exception('Failed to start registration: ${beginRes.body}');
    }

    final options = beginRes.body;

    // Step 2: Call browser WebAuthn API (Face ID prompt)
    final credentialJson = await callWebAuthnRegister(options);

    // Step 3: Send result to backend
    final completeRes = await http.post(
      Uri.parse('${AppConfig.baseUrl}/webauthn/register-complete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'credential': jsonDecode(credentialJson),
        'device_name': deviceName,
      }),
    );

    if (completeRes.statusCode != 200) {
      throw Exception('Registration failed: ${completeRes.body}');
    }
  }

  // ── Authenticate with Face ID ─────────────────────────────────────────────
  // Returns the Supabase magic link token on success

  static Future<String> authenticate(String email) async {
    // Step 1: Get challenge from backend
    final beginRes = await http.post(
      Uri.parse('${AppConfig.baseUrl}/webauthn/auth-begin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (beginRes.statusCode == 404) {
      throw Exception('No Face ID registered for this account');
    }
    if (beginRes.statusCode != 200) {
      throw Exception('Failed to start Face ID: ${beginRes.body}');
    }

    final options = beginRes.body;

    // Step 2: Call browser WebAuthn API (Face ID prompt)
    final credentialJson = await callWebAuthnAuthenticate(options);

    // Step 3: Verify with backend
    final completeRes = await http.post(
      Uri.parse('${AppConfig.baseUrl}/webauthn/auth-complete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'credential': jsonDecode(credentialJson),
      }),
    );

    if (completeRes.statusCode != 200) {
      throw Exception('Face ID verification failed: ${completeRes.body}');
    }

    final data = jsonDecode(completeRes.body);
    return data['token'] as String;
  }

  // ── Remove registered Face ID ─────────────────────────────────────────────

  static Future<void> removeCredential({
    required String email,
    required String credentialId,
  }) async {
    await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/webauthn/remove?email=$email&credential_id=$credentialId'),
    );
  }
}
