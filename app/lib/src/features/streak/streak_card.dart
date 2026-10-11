import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../settings/reading_settings.dart';

/// Current streak, today's ideas against the daily goal, and the last 7
/// days. Shown on the timeline and profile when signed in.
class StreakCard extends ConsumerWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) return const SizedBox.shrink();
    final streak = ref.watch(streakProvider).value;
    if (streak == null) return const SizedBox.shrink();
    return StreakView(
      streak: streak,
      onChangeGoal: () => showGoalPicker(context, ref),
    );
  }
}

class StreakView extends StatelessWidget {
  const StreakView({super.key, required this.streak, this.onChangeGoal});
  final Streak streak;

  /// Opens the daily goal picker; no "Change goal" button without it.
  final VoidCallback? onChangeGoal;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = streak;
    final goal = s.goal <= 0 ? 1 : s.goal;
    final progress = (s.today / goal).clamp(0.0, 1.0);
    return Padding(
      key: const ValueKey('streak-card'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          // The Change goal button's own padding takes up the top.
          padding: onChangeGoal == null
              ? const EdgeInsets.all(16)
              : const EdgeInsets.fromLTRB(16, 9, 16, 16),
          child: Row(
            children: [
              Column(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    color: s.current > 0
                        ? Candlelight.of(context).react
                        : scheme.outline,
                    size: 32,
                  ),
                  Text('${s.current}', style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: s.current == 1
                                  ? '1-day streak'
                                  : '${s.current}-day streak',
                              children: [
                                // The best run, when it's longer than this one.
                                if (s.longest > s.current)
                                  TextSpan(
                                    text: ' · best ${s.longest}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                            key: const ValueKey('streak-title'),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (onChangeGoal != null)
                          TextButton(
                            key: const ValueKey('change-goal'),
                            onPressed: onChangeGoal,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.padded,
                              visualDensity: VisualDensity.compact,
                              textStyle: theme.textTheme.labelMedium,
                            ),
                            child: const Text('Change goal'),
                          ),
                      ],
                    ),
                    Text(streakTodayText(s), style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final d in s.lastDays) _Day(day: d, goal: goal),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day, required this.goal});
  final DayCount day;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = DateTime.tryParse(day.day);
    final label = date == null
        ? ''
        : StreakView._weekdays[(date.weekday - 1) % 7];
    final met = day.ideas >= goal;
    return Tooltip(
      message: '${day.day}: ${day.ideas} ideas',
      child: Column(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: met
                  ? scheme.primary
                  : (day.ideas > 0
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// The line under the streak headline. Once the goal is met the count is
/// no longer framed as "N of goal", which read oddly past the goal
/// ("31 of 3"); it mirrors the web wording.
String streakTodayText(Streak s) => s.goalMet
    ? 'Goal met · ${s.today} ${s.today == 1 ? 'idea' : 'ideas'} today '
          '(goal ${s.goal})'
    : '${s.today} of ${s.goal} ideas today';
