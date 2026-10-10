import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'favorites_screen.dart';
import 'follow_button.dart';

/// A person's public profile by handle, with their favourites.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.handle});
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(handle));
    return Scaffold(
      appBar: AppBar(title: Text('@$handle')),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(profileProvider(handle)),
        ),
        data: (p) => ListView(
          children: [
            ReadingWidth(child: ProfileHeader(profile: p)),
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  'Favourites',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            ...favoriteTiles(
              context,
              ref,
              handle,
              empty: p.isMe
                  ? 'Tap the heart on an idea to add it here.'
                  : 'No favourites yet.',
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final name = p.displayName.isEmpty ? p.handle : p.displayName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.headlineSmall),
                    Text('@${p.handle}', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          if (p.bio.isNotEmpty) ...[const SizedBox(height: 12), Text(p.bio)],
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            children: [
              _Count(p.following, 'following'),
              _Count(
                p.favorites,
                p.favorites == 1 ? 'favourite' : 'favourites',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (p.isMe)
            OutlinedButton.icon(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit profile'),
            )
          else
            FollowButton(
              kind: FollowKind.user,
              target: p.id,
              initial: FollowState(
                followers: p.followers,
                isFollowing: p.isFollowing,
              ),
            ),
          if (p.isMe) ...[
            const SizedBox(height: 8),
            Text(
              '${compactCount(p.followers)} '
              '${p.followers == 1 ? 'follower' : 'followers'}',
            ),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, this.label);
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: compactCount(n),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(text: ' $label'),
      ],
    ),
  );
}
