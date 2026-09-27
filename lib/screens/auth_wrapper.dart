import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

/// Decides which screen to show on app start: if a token is already
/// stored, skip straight to HomeScreen; otherwise show LoginScreen.
///
/// Note: this only checks whether a token EXISTS, not whether it's
/// still valid. An expired token will still pass this check — proper
/// expiry handling comes later as global 401 handling.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();

    return FutureBuilder<String?>(
      future: apiService.getToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final hasToken = snapshot.data != null;
        return hasToken ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}