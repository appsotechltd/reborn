import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'follow_button.dart';

/// People, books and authors the signed-in user follows.
class FollowingScreen extends ConsumerWidget {
  const FollowingScreen({super.key});

  static IconData _icon(String kind) => switch (kind) {
    'user' => Icons.person_outline,
    'source' => Icons.menu_book_outlined,
    _ => Icons.history_edu_outlined,
  };

  static String? _route(FollowItem f) => switch (f.kind) {
    'user' when f.handle != null && f.handle!.isNotEmpty =>
      '/users/${Uri.encodeComponent(f.handle!)}',
    'source' => '/sources/${Uri.encodeComponent(f.target)}',
    'author' => '/authors/${Uri.encodeComponent(f.target)}',
    _ => null,
  };

  static FollowKind? _kind(String kind) {
    for (final k in FollowKind.values) {
      if (k.name == kind) return k;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Following')),
        body: const SignInPrompt(
          icon: Icons.people_outline,
          title: 'Follow books, authors and people',
          message: 'Sign in to follow and see their ideas in your timeline.',
        ),
      );
    }
    final following = ref.watch(followingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Following')),
      body: following.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(followingProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(followingProvider.future),
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        "You're not following anyone yet. Follow a book from "
                        'its source page, or an author from their name.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    for (final f in list)
                      ReadingWidth(
                        child: ListTile(
                          leading: Icon(_icon(f.kind)),
                          title: Text(f.label.isEmpty ? f.target : f.label),
                          subtitle: Text(switch (f.kind) {
                            'user' => '@${f.handle ?? ''}',
                            'source' => 'Book',
                            _ => 'Author',
                          }),
                          trailing: _kind(f.kind) == null
                              ? null
                              : FollowButton(
                                  kind: _kind(f.kind)!,
                                  target: f.target,
                                  initial: const FollowState(isFollowing: true),
                                  showCount: false,
                                ),
                          onTap: _route(f) == null
                              ? null
                              : () => context.push(_route(f)!),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
