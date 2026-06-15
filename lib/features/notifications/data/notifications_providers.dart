import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/notifications/local_notifications.dart';
import '../../../core/supabase/supabase_client.dart';
import 'notification_models.dart';
import 'notifications_repository.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((_) => NotificationsRepository());

class NotificationsState {
  const NotificationsState({this.items = const [], this.loading = true});
  final List<NotificationItem> items;
  final bool loading;
  int get unreadCount => items.where((n) => !n.isRead).length;

  NotificationsState copyWith({List<NotificationItem>? items, bool? loading}) =>
      NotificationsState(items: items ?? this.items, loading: loading ?? this.loading);
}

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, NotificationsState>(NotificationsController.new);

/// Live notifications for the current user (list + realtime + poll fallback).
class NotificationsController extends Notifier<NotificationsState> {
  RealtimeChannel? _channel;
  Timer? _poll;
  bool _primed = false; // suppress tray spam for the initial backlog
  // Row ids already emitted to the tray — single dedup point for BOTH the
  // realtime fast-path and the poll fallback, so a row never double-fires.
  final Set<String> _trayShown = {};

  @override
  NotificationsState build() {
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    ref.onDispose(_teardown);
    if (uid == null) {
      _teardown();
      return const NotificationsState(items: [], loading: false);
    }
    Future.microtask(() => _load(uid));
    return const NotificationsState(loading: true);
  }

  Future<void> _load(String uid) async {
    try {
      final items = await ref.read(notificationsRepositoryProvider).fetch();
      state = NotificationsState(items: items, loading: false);
      // Seed the dedup set with the existing backlog so opening the app never
      // replays old notifications into the tray.
      _trayShown.addAll(items.map((n) => n.id));
    } catch (_) {
      state = const NotificationsState(items: [], loading: false);
    }
    _subscribe(uid);
    _primed = true;
    // Poll fallback: this Lovable-managed Supabase project does not publish
    // the notifications table for realtime, so the realtime insert above may
    // never fire. Polling every 20s while the app is alive diffs new rows and
    // mirrors them to the tray. No backend/schema change. Realtime stays as a
    // faster path when available; _trayShown dedups the two.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (ref.read(authControllerProvider).user?.id == null) return;
    try {
      final items = await ref.read(notificationsRepositoryProvider).fetch();
      final knownIds = state.items.map((n) => n.id).toSet();
      // Fresh rows (not already in state) get mirrored to the tray.
      for (final n in items) {
        if (!knownIds.contains(n.id)) _emitTray(n);
      }
      state = state.copyWith(items: items, loading: false);
    } catch (_) {}
  }

  /// Show a tray notification once per unread row. Shared by realtime + poll;
  /// the stable id also lets the OS de-dupe if both fire. Mirrors every unread
  /// row so the tray and the in-app bell stay a single source of truth (the
  /// notifications table has no category column to filter on — `type` is only
  /// a severity enum — so per-category muting is left to the OS channel).
  void _emitTray(NotificationItem n) {
    if (!_primed || n.isRead) return;
    if (_trayShown.contains(n.id)) return;
    _trayShown.add(n.id);
    LocalNotifications.instance.show(
      id: notificationIdFrom(n.id),
      title: n.title,
      body: n.message,
      link: n.link,
    );
  }

  void _subscribe(String uid) {
    if (_channel != null) return;
    _channel = supabase.channel('notifications-realtime-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) {
          final n = NotificationItem.fromMap(payload.newRecord);
          if (state.items.any((x) => x.id == n.id)) return;
          state = state.copyWith(items: [n, ...state.items]);
          // Mirror to the phone tray (Phase 2a). _emitTray dedups against the
          // poll fallback so a row never fires twice.
          _emitTray(n);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) {
          final n = NotificationItem.fromMap(payload.newRecord);
          state = state.copyWith(items: [for (final x in state.items) if (x.id == n.id) n else x]);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) {
          final id = payload.oldRecord['id'];
          state = state.copyWith(items: state.items.where((x) => x.id != id).toList());
        },
      )
      ..subscribe();
  }

  Future<void> markAsRead(String id) async {
    final cur = state.items.firstWhere((n) => n.id == id, orElse: () => const NotificationItem(id: '', userId: '', title: '', message: ''));
    if (cur.id.isEmpty || cur.isRead) return;
    state = state.copyWith(items: [for (final n in state.items) if (n.id == id) n.copyWith(isRead: true, readAt: DateTime.now().toUtc()) else n]);
    try {
      await ref.read(notificationsRepositoryProvider).markAsRead(id);
    } catch (_) {
      state = state.copyWith(items: [for (final n in state.items) if (n.id == id) n.copyWith(isRead: false) else n]);
    }
  }

  Future<void> markAllAsRead() async {
    if (state.unreadCount == 0) return;
    final prev = state.items;
    state = state.copyWith(items: [for (final n in state.items) n.copyWith(isRead: true, readAt: n.readAt ?? DateTime.now().toUtc())]);
    try {
      await ref.read(notificationsRepositoryProvider).markAllAsRead();
    } catch (_) {
      state = state.copyWith(items: prev);
    }
  }

  Future<void> refresh() async {
    final uid = ref.read(authControllerProvider).user?.id;
    if (uid != null) {
      final items = await ref.read(notificationsRepositoryProvider).fetch();
      state = state.copyWith(items: items, loading: false);
    }
  }

  void _teardown() {
    _poll?.cancel();
    _poll = null;
    _primed = false;
    _trayShown.clear();
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }
}

/// Unread count for the header bell.
final unreadNotificationsProvider = Provider<int>((ref) {
  return ref.watch(notificationsControllerProvider.select((s) => s.unreadCount));
});
