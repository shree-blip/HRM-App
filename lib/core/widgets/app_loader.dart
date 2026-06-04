import 'package:flutter/material.dart';

/// Full-screen centered spinner — the mobile equivalent of the React
/// `PageLoader`.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
