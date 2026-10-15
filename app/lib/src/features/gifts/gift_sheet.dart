import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../post/post_store.dart';
import 'gift_service.dart';
import 'gift_store.dart';

const kGiftExplainer =
    'Gifts support Reborn: they keep the library free, ad-free and growing. '
    "They go to Reborn, not to the book's author, and show on this idea as "
    'a thank-you.';

/// Opens the gift sheet for [post].
Future<void> showGiftSheet(BuildContext context, Post post) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GiftSheet(post: post),
    );

/// Store prices for the tiers when gifts can be bought on this device,
/// or null when they can't (no store, store unavailable, provider off).
final giftStorePricesProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, GiftTiers>((ref, tiers) async {
      final store = ref.watch(giftStoreProvider);
      final platform = store.platform;
      if (platform == null || !tiers.enabled(platform.provider)) return null;
      try {
        if (!await store.isAvailable()) return null;
        final prices = await store.prices({
          for (final t in tiers.tiers) t.productId,
        });
        return prices.isEmpty ? null : prices;
      } catch (_) {
        return null;
      }
    });

class GiftSheet extends ConsumerStatefulWidget {
  const GiftSheet({super.key, required this.post});
  final Post post;

  @override
  ConsumerState<GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends ConsumerState<GiftSheet> {
  String? _buying;
  String? _error;

  Future<void> _buy(GiftTier tier) async {
    if (!ref.read(sessionProvider).signedIn) {
      Navigator.pop(context);
      context.push('/signin');
      return;
    }
    setState(() {
      _buying = tier.id;
      _error = null;
    });
    try {
      await ref.read(giftServiceProvider).give(widget.post.id, tier);
      ref.read(postStoreProvider.notifier).countGift(widget.post);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.post.card.author == null
                ? 'Thank you! Your ${tier.name} gift supports Reborn.'
                : 'Thank you! Your ${tier.name} gift is on its way to '
                      '${widget.post.card.author!.name}.',
          ),
        ),
      );
    } on GiftCancelled {
      if (mounted) setState(() => _buying = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buying = null;
        _error = e is GiftException ? e.message : errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiers = ref.watch(giftTiersProvider);
    final writer = widget.post.card.author;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ReadingWidth(
          maxWidth: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.volunteer_activism,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text('Send a gift', style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                writer == null
                    ? kGiftExplainer
                    : 'Your gift goes to ${writer.name}, who wrote this card. '
                          'Reborn keeps a share to cover costs.',
                key: const ValueKey('gift-explainer'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              tiers.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: LoadingView(),
                ),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(giftTiersProvider),
                ),
                data: (t) => _tiers(context, t),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tiers(BuildContext context, GiftTiers tiers) {
    final prices = ref.watch(giftStorePricesProvider(tiers));
    if (prices.isLoading) {
      return const Padding(padding: EdgeInsets.all(24), child: LoadingView());
    }
    final storePrices = prices.value;
    final enabled = storePrices != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!enabled)
          Container(
            key: const ValueKey('gifts-coming-soon'),
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
                Text('Gifts are coming soon'),
              ],
            ),
          ),
        for (final t in tiers.tiers)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: ValueKey('gift-tier-${t.id}'),
              leading: Icon(_icon(t.id)),
              title: Text(t.name),
              subtitle: Text(storePrices?[t.productId] ?? t.displayPrice),
              trailing: _buying == t.id
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed:
                          enabled &&
                              _buying == null &&
                              storePrices.containsKey(t.productId)
                          ? () => _buy(t)
                          : null,
                      child: const Text('Gift'),
                    ),
            ),
          ),
      ],
    );
  }

  static IconData _icon(String tier) => switch (tier) {
    'spark' => Icons.auto_awesome_outlined,
    'lamp' => Icons.light_outlined,
    'sun' => Icons.wb_sunny_outlined,
    _ => Icons.card_giftcard,
  };
}
