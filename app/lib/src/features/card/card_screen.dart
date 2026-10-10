import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../post/post_view.dart';

/// Shows one card as a post (reactions, favourite, comments, share, gift).
/// When [initial] is given (navigated from a list) the card is shown right
/// away while the post's stats load; otherwise the post is fetched (offline,
/// the cached post or card is shown).
class CardScreen extends ConsumerStatefulWidget {
  const CardScreen({super.key, required this.cardId, this.initial});
  final String cardId;
  final IdeaCard? initial;

  @override
  ConsumerState<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends ConsumerState<CardScreen> {
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      Future.microtask(() => _opened(initial));
    }
  }

  void _opened(IdeaCard card) {
    if (_recorded) return;
    _recorded = true;
    final repo = ref.read(repositoryProvider);
    repo.rememberCard(card);
    if (ref.read(sessionProvider).signedIn) repo.recordView(card.id);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    final post = ref.watch(postProvider(widget.cardId));
    ref.listen(postProvider(widget.cardId), (_, next) {
      final v = next.value;
      if (v != null && !v.offline) _opened(v.value.card);
    });
    Widget body;
    if (initial != null) {
      body = _scroll(post.value?.value ?? Post.fromCard(initial));
    } else {
      body = post.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(postProvider(widget.cardId)),
        ),
        data: (f) => _scroll(f.value),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Idea')),
      body: body,
    );
  }

  Widget _scroll(Post post) => SingleChildScrollView(
    child: ReadingWidth(child: PostView(post: post)),
  );
}
