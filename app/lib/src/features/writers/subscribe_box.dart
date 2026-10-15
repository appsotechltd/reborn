import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/member_models.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../gifts/gift_service.dart';
import '../gifts/gift_store.dart';
import 'writer_pass_service.dart';

/// The store's price for a writer's pass when it can be bought on this
/// device, or null when it can't (no store, store unavailable, provider off).
final writerPassPriceProvider = FutureProvider.autoDispose
    .family<String?, WriterOffer>((ref, offer) async {
      final store = ref.watch(giftStoreProvider);
      final platform = store.platform;
      final tier = offer.tier;
      if (platform == null || tier == null) return null;
      if (!offer.enabled(platform.provider)) return null;
      try {
        if (!await store.isAvailable()) return null;
        final prices = await store.prices({tier.productId});
        return prices[tier.productId];
      } catch (_) {
        return null;
      }
    });

/// On a writer's page, when they sell subscriptions: the price, their
/// pitch, how many cards subscribing opens, and Subscribe (an in-app 30-day
/// pass). Subscribed, when it ends, and Cancel renewal for web
/// subscriptions that renew.
class SubscribeBox extends ConsumerStatefulWidget {
  const SubscribeBox({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<SubscribeBox> createState() => _SubscribeBoxState();
}

class _SubscribeBoxState extends ConsumerState<SubscribeBox> {
  bool _busy = false;
  String? _message;

  String get _handle => widget.profile.handle;
  String get _name => widget.profile.displayName.isEmpty
      ? '@${widget.profile.handle}'
      : widget.profile.displayName;

  Future<void> _subscribe(WriterOffer offer) async {
    if (!ensureSignedIn(context, ref)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(writerPassServiceProvider).subscribe(_handle, offer.tier!);
      messenger.showSnackBar(
        SnackBar(content: Text("You're subscribed to $_name.")),
      );
    } on GiftCancelled {
      // Backed out of the store's sheet.
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is GiftException ? e.message : errorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel renewal?'),
        content: const Text(
          'Your subscription stops renewing. You keep access until it ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel renewal'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).cancelSubscription(_handle);
      ref.invalidate(writerOfferProvider(_handle));
      ref.invalidate(mySubscriptionsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text("Renewal cancelled")),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(writerOfferProvider(_handle)).value;
    // Nothing to show until it loads, or when they don't sell any.
    if (offer == null || (!offer.sells && !offer.subscribed)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final sub = offer.subscription;
    final isMe = widget.profile.isMe;
    return Container(
      key: const ValueKey('subscribe-box'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CandlelightTokens.radiusInset),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_membership, color: c.amberText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMe ? 'Your subscription' : 'Subscribe to $_name',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (offer.tier != null)
                Text(
                  '${offer.tier!.displayPrice} a month',
                  style: theme.textTheme.titleSmall,
                ),
            ],
          ),
          if (offer.pitch.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(offer.pitch),
          ],
          const SizedBox(height: 8),
          Text(
            [
              '${compactCount(offer.subscribers)} '
                  '${offer.subscribers == 1 ? 'subscriber' : 'subscribers'}',
              if (offer.lockedCards > 0)
                '${offer.lockedCards} subscriber-only '
                    '${offer.lockedCards == 1 ? 'card' : 'cards'}',
            ].join(' · '),
            key: const ValueKey('subscribe-counts'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (isMe)
            OutlinedButton(
              onPressed: () => context.push('/me/earnings'),
              child: const Text('Edit in Earnings'),
            )
          else if (offer.subscribed && sub != null) ...[
            Text(
              sub.renews
                  ? 'Subscribed · renews ${shortDate(sub.expiresAt)}'
                  : 'Subscribed until ${shortDate(sub.expiresAt)}',
              key: const ValueKey('subscribed-until'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (sub.renews)
              TextButton(
                key: const ValueKey('cancel-renewal'),
                onPressed: _busy ? null : _cancel,
                child: const Text('Cancel renewal'),
              ),
          ] else
            _subscribeButton(offer),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  Widget _subscribeButton(WriterOffer offer) {
    if (!offer.sells) return const SizedBox.shrink();
    final price = ref.watch(writerPassPriceProvider(offer));
    if (price.isLoading) {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final storePrice = price.value;
    if (storePrice == null) {
      return const Text(
        "Subscribing isn't available in this app yet. You can subscribe on "
        'the Reborn website.',
        key: ValueKey('subscribe-unavailable'),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('subscribe-button'),
      onPressed: _busy ? null : () => _subscribe(offer),
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.card_membership, size: 18),
      label: Text('Subscribe · $storePrice for 30 days'),
    );
  }
}
