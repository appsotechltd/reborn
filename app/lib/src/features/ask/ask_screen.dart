import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notifications_screen.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'ask_controller.dart';
import 'citations.dart';

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _scrollToEnd();
    final failed = await ref.read(askProvider.notifier).send(text);
    if (failed != null && _input.text.isEmpty) _input.text = failed;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final state = ref.watch(askProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask'),
        actions: [
          if (signedIn && state.entries.isNotEmpty)
            IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: ref.read(askProvider.notifier).clear,
            ),
          const NotificationBell(),
          const ProfileMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: !signedIn
          ? const SignInPrompt(
              icon: Icons.forum_outlined,
              title: 'Ask the library',
              message: 'Sign in to ask questions. Answers come only from ideas in the Reborn library, with links to each one.',
            )
          : Column(
              children: [
                Expanded(
                  child: state.entries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Ask anything — “How do I stop procrastinating?” — and get an answer built from idea cards.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount:
                              state.entries.length + (state.sending ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == state.entries.length) {
                              return const ReadingWidth(
                                child: _Bubble.thinking(),
                              );
                            }
                            return ReadingWidth(
                              child: _Bubble(entry: state.entries[i]),
                            );
                          },
                        ),
                ),
                if (state.error != null)
                  ReadingWidth(
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: ReadingWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  decoration: const InputDecoration(
                                    hintText: 'Ask a question…',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                style: amberIconButtonStyle,
                                tooltip: 'Send',
                                onPressed: state.sending ? null : _send,
                                icon: const Icon(Icons.arrow_upward),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Answers come only from the Reborn library and link to the ideas they use.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry}) : thinking = false;
  const _Bubble.thinking() : entry = null, thinking = true;

  final AskEntry? entry;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = entry?.message.role == 'user';
    final bg = isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final fg = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    Widget content;
    if (thinking) {
      content = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (isUser) {
      content = Text(
        entry!.message.content,
        style: TextStyle(color: fg, fontSize: 16),
      );
    } else {
      final segments = parseReply(entry!.message.content, entry!.citations);
      content = Text.rich(
        TextSpan(
          style: theme.textTheme.bodyLarge?.copyWith(color: fg, fontSize: 16),
          children: [
            for (final s in segments)
              switch (s) {
                TextSegment(:final text) => TextSpan(text: text),
                CitationSegment(:final card) => WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.lightbulb_outline, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          card.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      tooltip: card.credit,
                      onPressed: () => context.push(
                        '/cards/${Uri.encodeComponent(card.id)}',
                        extra: card,
                      ),
                    ),
                  ),
                ),
              },
          ],
        ),
      );
    }
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: content,
      ),
    );
  }
}
