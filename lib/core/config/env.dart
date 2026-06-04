import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized, typed access to environment configuration.
///
/// Values come from the bundled `.env` file (gitignored). We deliberately
/// only ever read the publishable / anon key here — the service_role key
/// must never ship inside a mobile app.
class Env {
  const Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String _require(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing "$key" in .env. Copy .env.example to .env and fill it in.',
      );
    }
    return value;
  }
}
