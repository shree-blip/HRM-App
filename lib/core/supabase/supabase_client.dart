import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'secure_local_storage.dart';

/// Initializes the Supabase client against the SAME project the React app
/// uses. Must be awaited once, before `runApp`.
///
/// Uses the PKCE auth flow (recommended for mobile) and stores the session
/// in encrypted secure storage.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: SecureLocalStorage(),
    ),
  );
}

/// Shorthand accessor for the initialized client.
SupabaseClient get supabase => Supabase.instance.client;
