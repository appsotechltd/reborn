import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/member_models.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// What I earn from gifts and subscriptions on my cards, my subscription
/// offer, and the writers I subscribe to.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Earnings'),
      ),
      body: !signedIn
          ? const SignInPrompt(
              icon: Icons.savings_outlined,
              title: 'Earn from your cards',
              message:
                  'Sign in to see gifts and subscriptions from your readers.',
            )
          : RefreshIndicator(
              onRefresh: () => Future.wait([
                ref.refresh(earningsProvider.future),
                ref.refresh(myPlanProvider.future),
                ref.refresh(mySubscriptionsProvider.future),
              ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  ReadingWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _EarningsSummary(),
                        heading('Subscriptions to you'),
                        const _PlanEditor(),
                        heading('Your subscriptions'),
                        const _MySubscriptions(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EarningsSummary extends ConsumerWidget {
  const _EarningsSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(earningsProvider)
        .when(
          loading: () =>
              const Padding(padding: EdgeInsets.all(32), child: LoadingView()),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(earningsProvider),
          ),
          data: (e) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Stat(
                      key: const ValueKey('earnings-total'),
                      value: moneyLabel(e.totalCents, e.currency),
                      label: 'Earned in all',
                    ),
                    _Stat(
                      value: moneyLabel(e.thisMonthCents, e.currency),
                      label: 'This month',
                    ),
                    _Stat(
                      value: compactCount(e.gifts),
                      label: e.gifts == 1 ? 'Gift' : 'Gifts',
                    ),
                    _Stat(
                      value: compactCount(e.subscribers),
                      label: e.subscribers == 1 ? 'Subscriber' : 'Subscribers',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'Reborn keeps ${e.commissionPercent}% after the payment '
                  'fee. Payouts start once writer payouts are set up.',
                  key: const ValueKey('earnings-note'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                child: Text('Recent', style: theme.textTheme.titleMedium),
              ),
              if (e.recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    'Nothing yet. Gifts on your cards and subscriptions to '
                    'you show up here.',
                  ),
                )
              else
                for (final r in e.recent) _EarningTile(item: r),
            ],
          ),
        );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Candlelight.of(context).inset,
        borderRadius: BorderRadius.circular(CandlelightTokens.radiusInset),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EarningTile extends StatelessWidget {
  const _EarningTile({required this.item});
  final EarningItem item;

  @override
  Widget build(BuildContext context) {
    final gift = item.kind == 'gift';
    final from = item.from;
    return ListTile(
      leading: Icon(
        gift ? Icons.volunteer_activism_outlined : Icons.card_membership,
      ),
      title: Text(
        gift
            ? (item.postTitle.isEmpty ? 'Gift' : 'Gift on “${item.postTitle}”')
            : 'Subscription',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (from != null) 'from ${from.name}',
          if (item.paidAt != null) shortDate(item.paidAt),
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '+${moneyLabel(item.authorCents, item.currency)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'of ${moneyLabel(item.amountCents, item.currency)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      onTap: gift && item.postId.isNotEmpty
          ? () => context.push('/cards/${Uri.encodeComponent(item.postId)}')
          : null,
    );
  }
}

/// Turns my subscription offer on or off, with its price and pitch.
class _PlanEditor extends ConsumerWidget {
  const _PlanEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(myPlanProvider)
      .when(
        loading: () =>
            const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(myPlanProvider)),
        data: (p) => _PlanForm(plan: p),
      );
}

class _PlanForm extends ConsumerStatefulWidget {
  const _PlanForm({required this.plan});
  final MyWriterPlan plan;

  @override
  ConsumerState<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends ConsumerState<_PlanForm> {
  late bool _enabled = widget.plan.plan?.enabled ?? false;
  late String _tier = _initialTier();
  late final _pitch = TextEditingController(
    text: widget.plan.plan?.pitch ?? '',
  );
  bool _saving = false;

  String _initialTier() {
    final tiers = widget.plan.tiers;
    final t = widget.plan.plan?.tier;
    if (t != null && tiers.any((x) => x.id == t)) return t;
    // $4.99 unless the server lists otherwise.
    return tiers.any((x) => x.id == 'month_499') ? 'month_499' : tiers.first.id;
  }

  @override
  void dispose() {
    _pitch.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .setMyPlan(tier: _tier, enabled: _enabled, pitch: _pitch.text.trim());
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
      ref.invalidate(myPlanProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;
    final subscribers = plan.plan?.subscribers ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('plan-enabled'),
            title: const Text('Offer subscriptions'),
            subtitle: Text(
              subscribers > 0
                  ? '${compactCount(subscribers)} '
                        '${subscribers == 1 ? 'subscriber' : 'subscribers'}'
                  : 'Subscribers read your subscriber-only and '
                        'followers-only cards.',
            ),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in plan.tiers)
                  ChoiceChip(
                    key: ValueKey('plan-tier-${t.id}'),
                    label: Text('${t.displayPrice} a month'),
                    selected: _tier == t.id,
                    onSelected: (_) => setState(() => _tier = t.id),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: const ValueKey('plan-pitch'),
              controller: _pitch,
              maxLength: kPitchMax,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Why subscribe? (optional)',
                hintText: 'What subscribers get from you',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              'In the apps a subscription is a 30-day pass. Reborn keeps '
              '${plan.commissionPercent}% after the payment fee.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const ValueKey('plan-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The writers I subscribe to, with when each subscription ends or renews.
class _MySubscriptions extends ConsumerWidget {
  const _MySubscriptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(mySubscriptionsProvider)
      .when(
        loading: () =>
            const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(mySubscriptionsProvider),
        ),
        data: (list) => list.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Text(
                  "You don't subscribe to anyone yet. Writers who offer "
                  'subscriptions show a Subscribe box on their page.',
                ),
              )
            : Column(
                children: [
                  for (final s in list)
                    ListTile(
                      key: ValueKey('subscription-${s.writer.handle}'),
                      leading: PersonAvatar(name: s.writer.name, radius: 18),
                      title: Text(s.writer.name),
                      subtitle: Text(subscriptionLine(s)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                        '/users/${Uri.encodeComponent(s.writer.handle)}',
                      ),
                    ),
                ],
              ),
      );
}

/// "Renews 14 Nov 2026", "Until 14 Nov 2026" or "Ended 14 Oct 2026".
String subscriptionLine(WriterSubscription s) {
  final date = shortDate(s.expiresAt);
  if (!s.active) return 'Ended $date';
  return s.renews ? 'Renews $date' : 'Until $date';
}
