import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local/tray notification service (Phase 2a). Shows a system notification for
/// each new `notifications` row picked up by NotificationsController (realtime
/// when the table is published, otherwise a poll fallback) — the table stays
/// the single source of truth, so the in-app bell and the tray never diverge
/// or duplicate. No Firebase/FCM (Phase 2b), so killed-app delivery is out of
/// scope by design.
class LocalNotifications {
  LocalNotifications._();
  static final instance = LocalNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called with a notification's `link` (e.g. "/leave") when the user taps a
  /// tray notification. Wired to the router in app startup.
  void Function(String link)? onTap;

  static const _channel = AndroidNotificationChannel(
    'hrm_default',
    'HRM Updates',
    description: 'Leave, attendance, documents, announcements and more.',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final link = resp.payload;
        if (link != null && link.isNotEmpty) onTap?.call(link);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _ready = true;
  }

  /// Ask for OS permission cleanly (Android 13+ POST_NOTIFICATIONS / iOS).
  /// Safe to call repeatedly; the OS only prompts once.
  Future<void> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Show one tray notification. [id] should be derived from the notifications
  /// row id so the same row can never produce two tray entries.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? link,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: link,
      );
    } catch (e) {
      debugPrint('[local-notif] show failed: $e');
    }
  }
}

/// Stable 31-bit notification id from a row id (Android requires a 32-bit int).
int notificationIdFrom(String rowId) => rowId.hashCode & 0x7fffffff;
