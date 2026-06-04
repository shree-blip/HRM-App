import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase auth session in the platform secure store
/// (Keychain on iOS, EncryptedSharedPreferences on Android) instead of
/// plain SharedPreferences.
///
/// This is the mobile equivalent of the React app's `localStorage`-backed
/// session, but encrypted at rest — satisfying the "secure local session
/// handling" requirement.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage();

  static const _sessionKey = 'focus_hrm.supabase.session';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);
}
