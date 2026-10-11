import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../gifts/gift_service.dart';
import '../gifts/gift_store.dart';
import 'premium_service.dart';

const kPremiumBenefits = [
  (
    Icons.auto_awesome_outlined,
    'Reborn AI: chat by text or voice, with charts and pictures, 250 units a month',
  ),
  (Icons.forum_outlined, 'Ask the AI guide ten times as much every hour'),
  (
    Icons.volunteer_activism_outlined,
    'Keep Reborn free and growing for everyone',
  ),
  (Icons.workspace_premium_outlined, 'A Premium badge on your profile'),
];

/// Store prices for the plans when Premium can be bought on this device, or
/// null when it can't (no store, store unavailable, provider off).
final premiumStorePricesProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, PremiumStatus>((ref, status) async {
      final store = ref.watch(giftStoreProvider);
      final platform = store.platform;
      if (platform == null || !status.enabled(platform.provider)) return null;
      try {
        if (!await store.isAvailable()) return null;
        final prices = await store.prices({
          for (final p in status.plans) p.productId,
        });
        return prices.isEmpty ? null : prices;
      } catch (_) {
        return null;
      }
    });

/// "Premium" chip shown on your own profile.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('premium-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium,
            size: 14,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'Premium',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime d) {
  final l = d.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  return '${l.day} ${months[l.month - 1]} ${l.year}';
}

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  String? _buying;
  String? _error;

  Future<void> _subscribe(PremiumPlan plan) async {
    if (!ensureSignedIn(context, ref)) return;
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    setState(() {
      _buying = plan.id;
      _error = null;
    });
    try {
      await ref.read(premiumServiceProvider).subscribe(plan, user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Premium. Thank you!')),
      );
    } on GiftCancelled {
      // Nothing to say.
    } on GiftException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'subscription_taken'
              ? 'This subscription belongs to another Reborn account.'
              : errorMessage(e),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  Future<void> _restore() async {
    if (!ensureSignedIn(context, ref)) return;
    ref.read(premiumErrorProvider.notifier).set(null);
    try {
      await ref.read(premiumServiceProvider).restore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checking your purchases with the store…'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _manage(GiftPlatform platform) => openExternal(
    context,
    platform == GiftPlatform.apple
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions',
  );

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(premiumProvider);
    final restoreError = ref.watch(premiumErrorProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Premium'),
      ),
      body: status.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(premiumProvider)),
        data: (s) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ReadingWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _status(s),
                  const SizedBox(height: 20),
                  Text('What you get', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (final (icon, text) in kPremiumBenefits)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon, color: theme.colorScheme.primary),
                      title: Text(text),
                    ),
                  const SizedBox(height: 12),
                  Text('Plans', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _plans(s),
                  if (_error != null || restoreError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error ??
                          (restoreError is ApiException &&
                                  restoreError.code == 'subscription_taken'
                              ? 'This subscription belongs to another '
                                    'Reborn account.'
                              : errorMessage(restoreError!)),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Subscriptions renew automatically until cancelled. '
                    'Manage or cancel them in your store account settings.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(PremiumStatus s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sub = s.subscription;
    return Card(
      color: s.premium ? scheme.tertiaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  s.premium
                      ? Icons.workspace_premium
                      : Icons.workspace_premium_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  s.premium ? "You're Premium" : 'Reborn Premium',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (s.premium && s.premiumUntil != null)
              Text('Premium until ${_date(s.premiumUntil!)}'),
            if (sub != null)
              Text(
                '${sub.plan == 'yearly' ? 'Yearly' : 'Monthly'} plan via '
                '${switch (sub.provider) {
                  'apple' => 'the App Store',
                  'google' => 'Google Play',
                  _ => 'the web',
                }}'
                '${sub.expiresAt == null ? '' : ' · renews or ends ${_date(sub.expiresAt!)}'}',
                style: theme.textTheme.bodySmall,
              ),
            if (!s.premium)
              const Text(
                'More from the AI guide, and support for the library.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _plans(PremiumStatus s) {
    final prices = ref.watch(premiumStorePricesProvider(s));
    if (prices.isLoading) {
      return const Padding(padding: EdgeInsets.all(24), child: LoadingView());
    }
    final store = ref.watch(giftStoreProvider);
    final storePrices = prices.value;
    final enabled = storePrices != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!enabled)
          Container(
            key: const ValueKey('premium-coming-soon'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.schedule, size: 18),
                SizedBox(width: 8),
                Text('Premium in the app is coming soon'),
              ],
            ),
          ),
        for (final p in s.plans)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: ValueKey('plan-${p.id}'),
              title: Text(p.name),
              subtitle: Text(
                '${storePrices?[p.productId] ?? p.displayPrice} '
                'per ${p.interval}',
              ),
              trailing: _buying == p.id
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed:
                          enabled &&
                              _buying == null &&
                              !(s.subscription?.plan == p.id && s.premium) &&
                              storePrices.containsKey(p.productId)
                          ? () => _subscribe(p)
                          : null,
                      child: Text(
                        s.subscription?.plan == p.id && s.premium
                            ? 'Current'
                            : 'Subscribe',
                      ),
                    ),
            ),
          ),
        if (store.platform != null)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const ValueKey('restore-purchases'),
                onPressed: enabled ? _restore : null,
                child: const Text('Restore purchases'),
              ),
              TextButton(
                onPressed: () => _manage(store.platform!),
                child: const Text('Manage subscription'),
              ),
            ],
          )
        else if (!enabled)
          TextButton(
            onPressed: () => context.push('/invite'),
            child: const Text('Invite friends to earn free Premium days'),
          ),
      ],
    );
  }
}
