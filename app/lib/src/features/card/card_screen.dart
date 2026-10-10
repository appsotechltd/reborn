import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'card_view.dart';

/// Shows one card. When [initial] is given (navigated from a list) it is shown
/// right away; otherwise the card is fetched (or read from the offline cache).
class CardScreen extends ConsumerStatefulWidget {
  const CardScreen({super.key, required this.cardId, this.initial});
  final String cardId;
  final IdeaCard? initial;

  @override
  ConsumerState<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends ConsumerState<CardScreen> {
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      Future.microtask(() => _opened(initial));
    }
  }

  void _opened(IdeaCard card) {
    final repo = ref.read(repositoryProvider);
    repo.rememberCard(card);
    if (ref.read(sessionProvider).signedIn) repo.recordView(card.id);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    Widget body;
    if (initial != null) {
      body = _scroll(initial);
    } else {
      ref.listen(cardProvider(widget.cardId), (_, next) {
        final v = next.value;
        if (v != null && !v.offline) _opened(v.value);
      });
      body = ref
          .watch(cardProvider(widget.cardId))
          .when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(cardProvider(widget.cardId)),
            ),
            data: (f) => _scroll(f.value),
          );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Idea')),
      body: body,
    );
  }

  Widget _scroll(IdeaCard card) => SingleChildScrollView(
    child: ReadingWidth(child: IdeaCardView(card: card)),
  );
}
