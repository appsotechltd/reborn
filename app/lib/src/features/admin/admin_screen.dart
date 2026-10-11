import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

String _n(num? v) => v == null ? '–' : compactCount(v.toInt());

String _pct(num? v) => v == null ? '–' : '${(v * 100).toStringAsFixed(0)}%';

String _money(int cents, String currency) {
  final symbol = switch (currency.toLowerCase()) {
    'usd' => r'$',
    'gbp' => '£',
    'eur' => '€',
    _ => '${currency.toUpperCase()} ',
  };
  return '$symbol${(cents / 100).toStringAsFixed(2)}';
}

/// Moderator dashboard: users, a 30-day chart, retention, engagement,
/// revenue, moderation queues and top posts.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isModerator = ref.watch(sessionProvider.select((s) => s.isModerator));
    if (!isModerator) {
      return Scaffold(
        appBar: AppBar(
          leading: exitLeading(context),
          title: const Text('Dashboard'),
        ),
        body: const Center(child: Text('Only moderators can see this.')),
      );
    }
    final stats = ref.watch(adminStatsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Dashboard'),
      ),
      body: stats.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(adminStatsProvider),
        ),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(adminStatsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              ReadingWidth(maxWidth: 960, child: _Dashboard(stats: s)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.stats});
  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = stats;
    final u = s.users;
    final e = s.engagement;
    final m = s.moderation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tiles([
          ('Users', _n(u['total'])),
          ('New (7d)', _n(u['new_7d'])),
          ('New (30d)', _n(u['new_30d'])),
          ('Daily active', _n(u['dau'])),
          ('Weekly active', _n(u['wau'])),
          ('Monthly active', _n(u['mau'])),
          ('Premium', _n(u['premium'])),
          ('Posts', _n(s.content['posts'])),
          ('Books', _n(s.content['sources'])),
        ]),
        const _Title('Last 30 days'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              children: [
                SizedBox(
                  height: 180,
                  child: CustomPaint(
                    key: const ValueKey('daily-chart'),
                    painter: DailyChartPainter(
                      days: s.daily,
                      activeColor: theme.colorScheme.primary,
                      signupColor: theme.colorScheme.tertiary,
                      gridColor: theme.colorScheme.outlineVariant,
                      labelColor: theme.colorScheme.onSurfaceVariant,
                    ),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  children: [
                    _Legend(theme.colorScheme.primary, 'Active'),
                    _Legend(theme.colorScheme.tertiary, 'Sign-ups'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const _Title('Retention'),
        _Tiles([
          ('Cohort', _n(s.retention['cohort'])),
          ('Day 1', _pct(s.retention['d1'])),
          ('Day 7', _pct(s.retention['d7'])),
        ]),
        const _Title('Engagement (7 days)'),
        _Tiles([
          ('Ideas read', _n(e['ideas_read_7d'])),
          ('Reactions', _n(e['reactions_7d'])),
          ('Comments', _n(e['comments_7d'])),
          ('Favourites', _n(e['favorites_7d'])),
          ('Shares', _n(e['shares_7d'])),
        ]),
        const _Title('Revenue'),
        Card(
          child: Column(
            children: [
              if (s.gifts.isEmpty && s.subscriptions.isEmpty)
                const ListTile(title: Text('No revenue yet')),
              for (final g in s.gifts)
                ListTile(
                  leading: const Icon(Icons.volunteer_activism_outlined),
                  title: Text('Gifts via ${g['provider']} (30 days)'),
                  subtitle: Text('${g['count'] ?? 0} gifts'),
                  trailing: Text(
                    _money(
                      (g['amount_cents'] as num?)?.toInt() ?? 0,
                      g['currency']?.toString() ?? 'usd',
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              for (final sub in s.subscriptions)
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text('Active subscriptions via ${sub['provider']}'),
                  trailing: Text(
                    '${sub['count'] ?? 0}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
            ],
          ),
        ),
        const _Title('Moderation'),
        _Tiles([
          ('Pending contributions', _n(m['pending_contributions'])),
          ('Reported comments', _n(m['reported_comments'])),
        ]),
        const _Title('Top posts this week'),
        Card(
          child: Column(
            children: [
              if (s.topPosts.isEmpty) const ListTile(title: Text('None yet')),
              for (final p in s.topPosts)
                ListTile(
                  title: Text(p.title),
                  trailing: Text('${p.score}'),
                  onTap: () =>
                      context.push('/cards/${Uri.encodeComponent(p.id)}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// Stat tiles of (label, value), in equal columns that fill the width: two
/// on a phone, more as it widens (each at least [minTileWidth]).
class _Tiles extends StatelessWidget {
  const _Tiles(this.items);
  final List<(String, String)> items;

  static const minTileWidth = 150.0;
  static const gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final cols = math.max(
          2,
          ((box.maxWidth + gap) / (minTileWidth + gap)).floor(),
        );
        final width = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, value) in items)
              SizedBox(
                key: ValueKey('stat-$label'),
                width: width,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value, style: theme.textTheme.headlineSmall),
                        Text(label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Two lines (active users and sign-ups per day) on a shared scale.
class DailyChartPainter extends CustomPainter {
  DailyChartPainter({
    required this.days,
    required this.activeColor,
    required this.signupColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<DailyStat> days;
  final Color activeColor;
  final Color signupColor;
  final Color gridColor;

  /// The scale's top value; a text colour, so it reads in both modes (the
  /// grid colour is too faint for text in dark mode).
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (days.isEmpty) return;
    final maxV = math.max(
      1,
      days.fold<int>(0, (m, d) => math.max(m, math.max(d.active, d.signups))),
    );
    Offset point(int i, int v) => Offset(
      days.length == 1 ? size.width / 2 : size.width * i / (days.length - 1),
      size.height - size.height * v / maxV,
    );
    void line(int Function(DailyStat) value, Color color) {
      final path = Path();
      for (var i = 0; i < days.length; i++) {
        final p = point(i, value(days[i]));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
    }

    line((d) => d.active, activeColor);
    line((d) => d.signups, signupColor);
    final label = TextPainter(
      text: TextSpan(
        text: '$maxV',
        style: TextStyle(color: labelColor, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(2, 2));
  }

  @override
  bool shouldRepaint(DailyChartPainter old) =>
      old.days != days ||
      old.activeColor != activeColor ||
      old.signupColor != signupColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor;
}
