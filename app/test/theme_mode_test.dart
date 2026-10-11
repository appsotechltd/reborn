import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/app.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/router.dart';
import 'package:reborn/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _darkBg = Color(0xFF14110E);
const _lightBg = Color(0xFFF1EFEA);

/// The whole app, offline-free: every request 404s, which is fine for theming.
Future<SharedPreferences> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({'onboarding.done': true, ...prefs});
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('{}', 404)),
        ),
      ],
      child: const RebornApp(),
    ),
  );
  await tester.pumpAndSettle();
  return sp;
}

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));

void _platform(WidgetTester tester, Brightness b) {
  tester.platformDispatcher.platformBrightnessTestValue = b;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

void main() {
  testWidgets('System (the default) follows the platform brightness', (
    tester,
  ) async {
    _platform(tester, Brightness.dark);
    await _pumpApp(tester);
    expect(_theme(tester).brightness, Brightness.dark);
    expect(_theme(tester).scaffoldBackgroundColor, _darkBg);

    // The phone switches to light: the app follows.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(_theme(tester).brightness, Brightness.light);
    expect(_theme(tester).scaffoldBackgroundColor, _lightBg);
  });

  testWidgets('a stored Light choice wins over a dark phone', (tester) async {
    _platform(tester, Brightness.dark);
    await _pumpApp(tester, prefs: {ThemeModeController.prefsKey: 'light'});
    expect(_theme(tester).brightness, Brightness.light);
  });

  testWidgets('a stored Dark choice wins over a light phone', (tester) async {
    _platform(tester, Brightness.light);
    await _pumpApp(tester, prefs: {ThemeModeController.prefsKey: 'dark'});
    expect(_theme(tester).brightness, Brightness.dark);
    expect(_theme(tester).scaffoldBackgroundColor, _darkBg);
  });

  testWidgets('an unknown stored value falls back to System', (tester) async {
    _platform(tester, Brightness.dark);
    await _pumpApp(tester, prefs: {ThemeModeController.prefsKey: 'sepia'});
    expect(_theme(tester).brightness, Brightness.dark);
  });

  testWidgets('Settings switches the mode, applies it and saves it', (
    tester,
  ) async {
    _platform(tester, Brightness.light);
    final prefs = await _pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RebornApp)),
    );
    container.read(routerProvider).push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(_theme(tester).brightness, Brightness.dark);
    expect(prefs.getString(ThemeModeController.prefsKey), 'dark');

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(_theme(tester).brightness, Brightness.light);
    expect(prefs.getString(ThemeModeController.prefsKey), isNull);
  });

  test('amber text is the deep tone in light mode, buttons match', () {
    final light = lightTheme.extension<Candlelight>()!;
    final dark = darkTheme.extension<Candlelight>()!;
    expect(light.amberText, const Color(0xFF9A5B0E));
    expect(dark.amberText, const Color(0xFFE9A23B));
    expect(lightTheme.colorScheme.primary, const Color(0xFF9A5B0E));
    for (final t in [lightTheme, darkTheme]) {
      final style = t.filledButtonTheme.style!;
      expect(style.backgroundColor!.resolve({}), const Color(0xFFE9A23B));
      expect(style.foregroundColor!.resolve({}), const Color(0xFF1A1209));
      expect(t.textTheme.headlineSmall!.fontFamily, 'Fraunces');
      expect(t.textTheme.bodyMedium!.fontFamily, 'Figtree');
    }
  });
}
