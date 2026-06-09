import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
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

/// Live notifications for the current user (list + realtime INSERT/UPDATE/DELETE).
class NotificationsController extends Notifier<NotificationsState> {
  RealtimeChannel? _channel;

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
    } catch (_) {
      state = const NotificationsState(items: [], loading: false);
    }
    _subscribe(uid);
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
