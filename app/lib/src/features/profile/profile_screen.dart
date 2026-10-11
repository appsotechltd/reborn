import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../premium/premium_screen.dart';
import '../streak/streak_card.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sessionProvider.notifier).refreshUser());
  }

  Future<void> _editName(String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final user = await ref
          .read(repositoryProvider)
          .updateMe(displayName: name);
      await ref.read(sessionProvider.notifier).setUser(user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final names = ref.watch(topicNamesProvider);
    final user = session.user;
    if (!session.signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const SignInPrompt(
          icon: Icons.person_outline,
          title: 'Your profile',
          message: 'Sign in to sync across devices.',
        ),
      );
    }
    final topics = ref.watch(topicPrefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          ReadingWidth(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(user?.displayName ?? ''),
                      if (user?.premium ?? false) const PremiumBadge(),
                    ],
                  ),
                  subtitle: Text(
                    [
                      if (user?.handle.isNotEmpty ?? false) '@${user!.handle}',
                      user?.email ?? '',
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: 'Edit name',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editName(user?.displayName ?? ''),
                  ),
                ),
                if (session.isModerator)
                  const ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text('Moderator'),
                  ),
                if (user?.handle.isNotEmpty ?? false)
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('Your public profile'),
                    onTap: () => context.push(
                      '/users/${Uri.encodeComponent(user!.handle)}',
                    ),
                  ),
                const StreakCard(),
                ListTile(
                  leading: const Icon(Icons.favorite_border),
                  title: const Text('Favourites'),
                  onTap: () => context.push('/favorites'),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Following'),
                  onTap: () => context.push('/following'),
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Book circles'),
                  onTap: () => context.push('/circles'),
                ),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Premium'),
                  subtitle: Text(
                    (user?.premium ?? false) ? "You're Premium" : 'See plans',
                  ),
                  onTap: () => context.push('/premium'),
                ),
                ListTile(
                  leading: const Icon(Icons.card_giftcard),
                  title: const Text('Invite friends'),
                  subtitle: const Text('You both get free Premium days'),
                  onTap: () => context.push('/invite'),
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Your topics'),
                  subtitle: Text(
                    topics.isEmpty
                        ? 'All topics'
                        : topics.map((t) => names[t] ?? t).join(', '),
                  ),
                  onTap: () => context.push('/topics'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('Contribute an idea'),
                  onTap: () => context.push('/contribute'),
                ),
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('My contributions'),
                  onTap: () => context.push('/contributions'),
                ),
                if (session.isModerator)
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Moderation queue'),
                    onTap: () => context.push('/moderation'),
                  ),
                if (session.isModerator)
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Dashboard'),
                    onTap: () => context.push('/admin'),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  subtitle: const Text('Handle, bio, delete account'),
                  onTap: () => context.push('/settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: () async {
                    await ref.read(sessionProvider.notifier).signOut();
                    if (context.mounted) context.go('/home');
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Server: $apiBaseUrl',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
