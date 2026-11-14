import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` with the already-loaded instance, so reads are synchronous.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden in main()'),
);
