import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../layout/adaptive.dart';
import '../../widgets/common.dart';
import '../listen/listen_controller.dart';
import '../listen/listen_follow.dart';
import '../post/post_view.dart';

/// The widest the card page gets on tablets and up.
const kCardPageWidth = 720.0;

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
    // While Listen mode is on, it moves to this card; when it moves on to
    // another card, that card opens in place of this one.
    final card = post.value?.value.card ?? initial;
    return Scaffold(
      appBar: AppBar(leading: exitLeading(context), title: const Text('Idea')),
      body: ListenFollow(
        target: card == null ? null : ListenTarget.card(card),
        onMove: (p) {
          if (p.card.id == widget.cardId) return;
          context.pushReplacement(
            '/cards/${Uri.encodeComponent(p.card.id)}',
            extra: p.card,
          );
        },
        child: body,
      ),
    );
  }

  /// Phones: the post edge to edge. Tablets and up: a card centred at
  /// most [kCardPageWidth] wide, with margins around it.
  Widget _scroll(Post post) {
    if (WindowSize.of(context).isCompact) {
      return SingleChildScrollView(
        child: ReadingWidth(child: PostView(post: post)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: ReadingWidth(
        maxWidth: kCardPageWidth,
        child: Card(
          key: const ValueKey('card-page-card'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: PostView(post: post),
          ),
        ),
      ),
    );
  }
}
