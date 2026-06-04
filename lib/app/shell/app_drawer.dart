import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/navigation/nav_items.dart';
import '../../core/permissions/permissions_controller.dart';
import '../theme/app_theme.dart';

/// Navigation drawer listing only the destinations the user has permission
/// for (mirrors the web sidebar's effective-permission filtering).
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.currentRoute});

  final String currentRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final perms = ref.watch(permissionsControllerProvider);
    final profile = auth.profile;

    final items = kNavItems.where((i) => i.isVisible(perms)).toList();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.slate900, AppColors.slate800],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/focus-logo.png',
                        width: 40,
                        height: 40,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'FOCUS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    profile?.fullName.isNotEmpty == true
                        ? profile!.fullName
                        : (profile?.email ?? 'User'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (auth.role != null)
                    Text(
                      _roleLabel(auth),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            // Items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in items)
                    ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      selected: item.route == currentRoute,
                      selectedTileColor:
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                      onTap: () {
                        Navigator.of(context).pop(); // close drawer
                        if (item.route != currentRoute) context.go(item.route);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(authControllerProvider.notifier).signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(AppAuthState auth) {
    final role = auth.role?.name;
    return switch (role) {
      'vp' => 'Executive',
      'admin' => 'Admin',
      'supervisor' => 'Supervisor',
      'lineManager' => 'Line Manager',
      _ => 'Employee',
    };
  }
}
