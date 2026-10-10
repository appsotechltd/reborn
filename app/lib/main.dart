import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/data/providers.dart';
import 'src/features/gifts/gift_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    // Errors are shown with a "Try again" button instead of silent retries.
    retry: (_, _) => null,
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // On iOS/Android, finish gifts that were paid for but didn't reach the
  // server last time (no-op on web).
  container.read(giftServiceProvider).start();
  runApp(
    UncontrolledProviderScope(container: container, child: const RebornApp()),
  );
}
