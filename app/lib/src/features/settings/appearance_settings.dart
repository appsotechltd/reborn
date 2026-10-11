import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';

/// System / Light / Dark. Saved on this device; System follows the phone.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  static const _choices = [
    (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Appearance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          mode == ThemeMode.system
              ? "Follows your phone's light or dark setting."
              : 'Always ${mode.name}, whatever your phone uses.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          key: const ValueKey('theme-mode'),
          showSelectedIcon: false,
          segments: [
            for (final (value, label, icon) in _choices)
              ButtonSegment(
                value: value,
                label: Text(label),
                icon: Icon(icon, size: 18),
              ),
          ],
          selected: {mode},
          onSelectionChanged: (s) =>
              ref.read(themeModeProvider.notifier).set(s.first),
        ),
      ],
    );
  }
}
