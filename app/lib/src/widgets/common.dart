import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../data/providers.dart';
import '../theme.dart';

/// Centers [child] and limits it to a comfortable reading width.
class ReadingWidth extends StatelessWidget {
  const ReadingWidth({
    super.key,
    required this.child,
    this.maxWidth = kReadingWidth,
  });
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

String errorMessage(Object error) {
  if (error is ApiException) {
    if (error.isNetwork) {
      return "You're offline and this isn't saved on this device yet.";
    }
    return error.message;
  }
  return 'Something went wrong.';
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.cloud_off_outlined : Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(errorMessage(error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Shown in place of a signed-in-only screen.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ReadingWidth(
        maxWidth: 420,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.push('/signin'),
                child: const Text('Sign in'),
              ),
              TextButton(
                onPressed: () => context.push('/register'),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns true if signed in; otherwise offers sign-in and returns false.
Future<bool> requireSignIn(
  BuildContext context,
  WidgetRef ref,
  String reason,
) async {
  if (ref.read(sessionProvider).signedIn) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign in to continue'),
      content: Text(reason),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sign in'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) context.push('/signin');
  return false;
}

/// For social actions (react, favourite, comment, gift, follow): returns
/// true when signed in, otherwise goes to the sign-in screen.
bool ensureSignedIn(BuildContext context, WidgetRef ref) {
  if (ref.read(sessionProvider).signedIn) return true;
  context.push('/signin');
  return false;
}

/// 0, 12, 999, 1.2k, 12k, 1.2M.
String compactCount(int n) {
  if (n < 1000) return '$n';
  String f(double v) {
    final s = v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (n < 1000000) return '${f(n / 1000)}k';
  return '${f(n / 1000000)}M';
}

/// "just now", "5m", "3h", "2d", or a date for older times.
String timeAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  final l = t.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// A small banner shown while serving cached content.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off,
                size: 16,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Offline — showing saved ideas',
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

/// Compact list entry for a card; opens the card screen.
class CardTile extends ConsumerWidget {
  const CardTile({
    super.key,
    required this.card,
    this.trailing,
    this.onTap,
    this.selected = false,
  });
  final IdeaCard card;
  final Widget? trailing;

  /// Instead of opening the card screen (e.g. to show it in a side pane).
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(topicNamesProvider);
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(card.title, style: theme.textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${names[card.topic] ?? card.topic} · '
          '${card.author != null ? 'by ${card.author!.name}' : card.source.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: trailing,
      selected: selected,
      onTap:
          onTap ??
          () => context.push(
            '/cards/${Uri.encodeComponent(card.id)}',
            extra: card,
          ),
    );
  }
}

/// Profile / overflow menu shown in every tab's app bar.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return PopupMenuButton<String>(
      tooltip: 'Profile and more',
      icon: session.signedIn
          ? PersonAvatar(
              name: session.user?.displayName ?? session.user?.email ?? '?',
              radius: 15,
            )
          : CircleAvatar(
              radius: 15,
              backgroundColor: Candlelight.of(context).inset,
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              child: const Icon(Icons.person_outline, size: 18),
            ),
      onSelected: (v) async {
        if (v == 'signout') {
          await ref.read(sessionProvider.notifier).signOut();
          return;
        }
        if (context.mounted) context.push(v);
      },
      itemBuilder: (context) => [
        if (session.signedIn)
          const PopupMenuItem(
            value: '/profile',
            child: _MenuRow(Icons.person_outline, 'Profile'),
          )
        else
          const PopupMenuItem(
            value: '/signin',
            child: _MenuRow(Icons.login, 'Sign in'),
          ),
        if (session.signedIn) ...[
          const PopupMenuItem(
            value: '/favorites',
            child: _MenuRow(Icons.favorite_border, 'Favourites'),
          ),
          const PopupMenuItem(
            value: '/following',
            child: _MenuRow(Icons.people_outline, 'Following'),
          ),
          const PopupMenuItem(
            value: '/me/cards',
            child: _MenuRow(Icons.edit_note, 'My cards'),
          ),
          const PopupMenuItem(
            value: '/me/earnings',
            child: _MenuRow(Icons.savings_outlined, 'Earnings'),
          ),
          const PopupMenuItem(
            value: '/circles',
            child: _MenuRow(Icons.groups_outlined, 'Book circles'),
          ),
          const PopupMenuItem(
            value: '/invite',
            child: _MenuRow(Icons.card_giftcard, 'Invite friends'),
          ),
        ],
        const PopupMenuItem(
          value: '/ai',
          child: _MenuRow(Icons.auto_awesome_outlined, 'Reborn AI'),
        ),
        const PopupMenuItem(
          value: '/library',
          child: _MenuRow(Icons.local_library_outlined, 'Library'),
        ),
        const PopupMenuItem(
          value: '/premium',
          child: _MenuRow(Icons.workspace_premium_outlined, 'Premium'),
        ),
        const PopupMenuItem(
          value: '/topics',
          child: _MenuRow(Icons.tune, 'Your topics'),
        ),
        const PopupMenuItem(
          value: '/contribute',
          child: _MenuRow(Icons.edit_note, 'Contribute an idea'),
        ),
        if (session.signedIn)
          const PopupMenuItem(
            value: '/contributions',
            child: _MenuRow(Icons.inbox_outlined, 'My contributions'),
          ),
        if (session.isModerator)
          const PopupMenuItem(
            value: '/moderation',
            child: _MenuRow(Icons.gavel_outlined, 'Moderation'),
          ),
        if (session.isModerator)
          const PopupMenuItem(
            value: '/admin',
            child: _MenuRow(Icons.insights_outlined, 'Dashboard'),
          ),
        const PopupMenuItem(
          value: '/settings',
          child: _MenuRow(Icons.settings_outlined, 'Settings'),
        ),
        if (session.signedIn)
          const PopupMenuItem(
            value: 'signout',
            child: _MenuRow(Icons.logout, 'Sign out'),
          ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
  );
}

/// The tabs' own pages: a page shown at one of these is in the shell (or in
/// one of its panes), which has its navigation.
const _shellPaths = ['/home', '/discover', '/stashes', '/review', '/ask'];

/// An app bar's `leading` for pages that can be opened straight from a link
/// (a shared card, a refresh, an installed web app): when there is nothing
/// to go back to, a Home button, so the page is never a dead end. Null (the
/// usual Back button, or none in a pane) otherwise.
Widget? exitLeading(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isFirst) return null;
  final router = GoRouter.maybeOf(context);
  if (router == null) return null;
  final path = router.routerDelegate.currentConfiguration.uri.path;
  if (_shellPaths.any((p) => path == p || path.startsWith('$p/'))) {
    return null;
  }
  return IconButton(
    key: const ValueKey('exit-home'),
    tooltip: 'Home',
    icon: const Icon(Icons.home_outlined),
    onPressed: () => context.go('/home'),
  );
}
