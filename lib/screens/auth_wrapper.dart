import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

/// Decides which screen to show on app start: if a token is stored AND
/// still valid (not expired), skip straight to HomeScreen; otherwise clear
/// whatever's stored and show LoginScreen.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  /// Reads the `exp` claim out of a JWT's payload without verifying the
  /// signature — we don't need to verify it here, just check whether the
  /// server would still accept it. Any parsing failure is treated as
  /// expired, so a corrupted or unexpected token never lets someone in.
  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // Base64Url payload segments often come without padding; add it back
      // so base64Url.decode doesn't choke.
      var payload = parts[1];
      payload += '=' * ((4 - payload.length % 4) % 4);

      final decoded = utf8.decode(base64Url.decode(payload));
      final claims = jsonDecode(decoded) as Map<String, dynamic>;

      final exp = claims['exp'] as int?;
      if (exp == null) return true;

      final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expiryTime);
    } catch (e) {
      return true;
    }
  }

  Future<bool> _hasValidToken() async {
    final token = await ApiService().getToken();
    if (token == null) return false;

    if (_isTokenExpired(token)) {
      // Don't leave a dead token sitting in storage.
      await ApiService().logout();
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasValidToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isValid = snapshot.data ?? false;
        return isValid ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}