import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// The reader's System / Light / Dark choice, saved on this device.
/// Defaults to [ThemeMode.dark] (Moses, 2026-10-15); System follows the
/// phone's setting. The header's sun/moon button and Settings share it.
class ThemeModeController extends Notifier<ThemeMode> {
  static const prefsKey = 'appearance.theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(prefsKey);
    return ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.dark,
    );
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    // System is stored too: with no choice saved the app is dark.
    await ref.read(sharedPreferencesProvider).setString(prefsKey, mode.name);
  }

  /// The header's toggle: to the other mode from what is on screen now.
  Future<void> toggle(Brightness showing) =>
      set(showing == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
