import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/device_timezone.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

const kGoalChoices = [1, 2, 3, 5, 7, 10, 15, 20, 30, 50];

const kNotifyKinds = [
  ('daily', 'Daily idea', 'One idea a day, after 8am your time'),
  ('replies', 'Replies', 'When someone replies to your comment'),
  ('follows', 'New followers', 'When someone follows you'),
  ('circles', 'Circles', 'New messages in your book circles'),
];

/// Saves reading settings with PATCH /v1/me, updates the signed-in user
/// and, when the goal or timezone changed, the streak. Errors go to
/// [messenger].
Future<void> saveReadingSettings(
  WidgetRef ref,
  ScaffoldMessengerState messenger, {
  int? dailyGoal,
  Map<String, bool>? notify,
  String? timezone,
}) async {
  try {
    final user = await ref
        .read(repositoryProvider)
        .updateMe(dailyGoal: dailyGoal, notify: notify, timezone: timezone);
    await ref.read(sessionProvider.notifier).setUser(user);
    if (dailyGoal != null || timezone != null) {
      ref.invalidate(streakProvider);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
  }
}

/// The daily goal choices, with [goal] among them.
List<int> goalChoices(int goal) => {...kGoalChoices, goal}.toList()..sort();

/// A sheet to pick the daily goal (the same choices as in Settings), saved
/// right away.
Future<void> showGoalPicker(BuildContext context, WidgetRef ref) async {
  final goal = ref.read(sessionProvider).user?.dailyGoal;
  final messenger = ScaffoldMessenger.of(context);
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('goal-picker'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(
                'Daily goal',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Ideas to read each day to keep your streak',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final n in goalChoices(goal ?? 3))
              ListTile(
                key: ValueKey('goal-$n'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(n == 1 ? '1 idea a day' : '$n ideas a day'),
                trailing: n == goal ? const Icon(Icons.check) : null,
                selected: n == goal,
                onTap: () => Navigator.of(context).pop(n),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked != null && picked != goal) {
    await saveReadingSettings(ref, messenger, dailyGoal: picked);
  }
}

/// Daily goal, push notification switches and timezone. Each change is saved
/// right away with PATCH /v1/me.
class ReadingSettings extends ConsumerStatefulWidget {
  const ReadingSettings({super.key});

  @override
  ConsumerState<ReadingSettings> createState() => _ReadingSettingsState();
}

class _ReadingSettingsState extends ConsumerState<ReadingSettings> {
  String? _deviceTz;

  @override
  void initState() {
    super.initState();
    ref.read(deviceTimezoneProvider)().then((tz) {
      if (mounted) setState(() => _deviceTz = tz);
    });
  }

  Future<void> _save({
    int? dailyGoal,
    Map<String, bool>? notify,
    String? timezone,
  }) => saveReadingSettings(
    ref,
    ScaffoldMessenger.of(context),
    dailyGoal: dailyGoal,
    notify: notify,
    timezone: timezone,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(sessionProvider).user;
    if (user == null) return const SizedBox.shrink();
    final goal = user.dailyGoal;
    final choices = goalChoices(goal);
    final tz = user.timezone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Reading', style: theme.textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Daily goal'),
          subtitle: const Text('Ideas to read each day to keep your streak'),
          trailing: DropdownButton<int>(
            key: const ValueKey('daily-goal'),
            value: goal,
            items: [
              for (final n in choices)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (n) {
              if (n != null && n != goal) _save(dailyGoal: n);
            },
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: const Text('Timezone'),
          subtitle: Text(tz.isEmpty ? 'Not set' : tz),
          trailing: _deviceTz != null && _deviceTz != tz
              ? TextButton(
                  onPressed: () => _save(timezone: _deviceTz),
                  child: Text('Use $_deviceTz'),
                )
              : null,
        ),
        const SizedBox(height: 8),
        Text('Notifications', style: theme.textTheme.titleMedium),
        for (final (kind, title, subtitle) in kNotifyKinds)
          SwitchListTile(
            key: ValueKey('notify-$kind'),
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            subtitle: Text(subtitle),
            value: user.notifies(kind),
            onChanged: (on) => _save(notify: {kind: on}),
          ),
      ],
    );
  }
}
