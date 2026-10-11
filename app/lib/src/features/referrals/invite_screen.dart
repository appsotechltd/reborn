import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../post/share.dart';

/// The invite link for a referral code.
String referralLink(String code, {String base = webBaseUrl}) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$b/join?ref=${Uri.encodeQueryComponent(code)}';
}

/// Your referral code, a share link, and how many people joined with it.
class InviteScreen extends ConsumerWidget {
  const InviteScreen({super.key});

  Future<void> _share(BuildContext context, WidgetRef ref, Referrals r) async {
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final link = referralLink(r.code);
    final text = 'Join me on Reborn: one-minute ideas from great books. $link';
    try {
      await ref
          .read(sharerProvider)
          .share(text: text, subject: 'Join me on Reborn', origin: origin);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Invite link copied')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invite friends')),
        body: const SignInPrompt(
          icon: Icons.card_giftcard,
          title: 'Invite friends',
          message: 'Sign in to get your invite link.',
        ),
      );
    }
    final referrals = ref.watch(referralsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends')),
      body: referrals.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(referralsProvider),
        ),
        data: (r) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ReadingWidth(
              maxWidth: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.card_giftcard,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    r.rewardDays > 0
                        ? 'Give ${r.rewardDays} days of Premium, get '
                              '${r.rewardDays} days'
                        : 'Invite friends to Reborn',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'When someone joins with your link and reads on three '
                    'different days, you both get free Premium.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text('Your code', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Card(
                    child: ListTile(
                      title: SelectableText(
                        r.code,
                        key: const ValueKey('referral-code'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          letterSpacing: 2,
                        ),
                      ),
                      subtitle: Text(referralLink(r.code)),
                      trailing: IconButton(
                        tooltip: 'Copy link',
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: referralLink(r.code)),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Invite link copied'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) => FilledButton.icon(
                      onPressed: () => _share(context, ref, r),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share invite link'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _Stat(r.invited, 'joined')),
                      Expanded(child: _Stat(r.rewarded, 'rewarded')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.n, this.label);
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('$n', style: Theme.of(context).textTheme.headlineMedium),
          Text(label),
        ],
      ),
    ),
  );
}
