import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/notifications/local_notifications.dart';
import '../features/notifications/data/notifications_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class HrmApp extends ConsumerStatefulWidget {
  const HrmApp({super.key});

  @override
  ConsumerState<HrmApp> createState() => _HrmAppState();
}

class _HrmAppState extends ConsumerState<HrmApp> {
  bool _permissionAsked = false;

  /// Request OS notification permission once per session, whether the user was
  /// already signed in at cold start or signs in later.
  void _ensurePermission(String? uid) {
    if (uid == null || _permissionAsked) return;
    _permissionAsked = true;
    LocalNotifications.instance.requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Tray-tap routing: open the relevant screen via the notification link.
    LocalNotifications.instance.onTap = (link) {
      if (link.isNotEmpty) router.go(link);
    };

    // Login transition (e.g. after sign-in on a fresh install).
    ref.listen<String?>(authControllerProvider.select((s) => s.user?.id),
        (prev, uid) {
      if (uid != null) {
        ref.read(notificationsControllerProvider);
        _ensurePermission(uid);
      } else {
        _permissionAsked = false;
      }
    });

    // Already-signed-in at cold start: keep the notifications subscription
    // mounted app-wide AND request permission on first frame (the listen above
    // does not fire when the session is restored, not freshly changed).
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    if (uid != null) {
      ref.watch(notificationsControllerProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePermission(uid));
    }

    return MaterialApp.router(
      title: 'Focus HRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
