import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/data/providers.dart';
import 'src/features/gifts/gift_service.dart';
import 'src/features/listen/audio_service_session.dart';
import 'src/features/listen/listen_audio.dart';
import 'src/features/notifications/push_service.dart';
import 'src/features/premium/premium_service.dart';
import 'src/tv/tv_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final prefs = await SharedPreferences.getInstance();
  final tv = await detectTv();
  // Listen mode's background playback and lock-screen controls.
  final listenSession = await AudioServiceListenSession.start();
  final container = ProviderContainer(
    // Errors are shown with a "Try again" button instead of silent retries.
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      tvDetectedProvider.overrideWithValue(tv),
      if (listenSession != null)
        listenMediaSessionProvider.overrideWithValue(listenSession),
    ],
  );
  // On iOS/Android, finish gifts that were paid for but didn't reach the
  // server last time (no-op on web).
  container.read(giftServiceProvider).start();
  container.read(premiumServiceProvider).start();
  // Push is optional: without Firebase config this does nothing. Signed in,
  // it asks for permission and registers the device; signing out removes it.
  final push = container.read(pushServiceProvider);
  container.listen<bool>(sessionProvider.select((s) => s.signedIn), (was, now) {
    if (now && was != true) push.onSignedIn();
  });
  push.start();
  runApp(
    UncontrolledProviderScope(container: container, child: const RebornApp()),
  );
}

/// The bundled fonts are under the SIL Open Font License; list them on the
/// licences page.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in const [
      ('Fraunces', 'assets/fonts/Fraunces-OFL.txt'),
      ('Figtree', 'assets/fonts/Figtree-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString(file));
    }
  });
}
