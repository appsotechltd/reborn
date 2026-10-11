import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../api/ai_models.dart';
import '../../api/api_client.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../ask/citations.dart';
import '../card/explainer_player.dart';
import '../gifts/gift_service.dart';
import '../gifts/gift_store.dart';
import 'ai_chart.dart';
import 'ai_controller.dart';
import 'topup_service.dart';
import 'voice_recorder.dart';

/// Makes the microphone recorder; tests swap in a fake.
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>(
  (_) => VoiceRecorder.new,
);

/// Reborn AI, the premium assistant: chat by text or voice, with pictures,
/// charts and answers from the library, paid for in AI units.
class AIScreen extends ConsumerWidget {
  const AIScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final status = signedIn ? ref.watch(aiStatusProvider) : null;
    final ready = status?.value;
    final chatting = ready != null && ready.available && ready.premium;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reborn AI'),
        actions: [
          if (chatting) ...[
            IconButton(
              tooltip: 'Your chats',
              icon: const Icon(Icons.history),
              onPressed: () => _showChats(context),
            ),
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: ref.read(aiChatProvider.notifier).newChat,
            ),
          ],
          const ProfileMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (status) {
        null => const SignInPrompt(
          icon: Icons.auto_awesome_outlined,
          title: 'Reborn AI',
          message: 'Sign in to chat with Reborn AI by text or voice. It answers from the library and can draw charts and pictures.',
        ),
        AsyncValue(:final value?) when !value.premium => _Upsell(status: value),
        AsyncValue(:final value?) when !value.available => const _Unavailable(),
        AsyncValue(:final value?) => _Chat(status: value),
        AsyncValue(:final error?) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(aiStatusProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }

  static void _showChats(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _ChatsSheet(),
  );
}

class _Upsell extends StatelessWidget {
  const _Upsell({required this.status});
  final AIStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ReadingWidth(
          maxWidth: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, color: c.amber, size: 40),
              const SizedBox(height: 12),
              Text('Reborn AI', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Your own assistant inside Reborn. Talk or type, and it answers from the library with links to each idea, saves cards to your stashes, and draws charts, sketches and pictures.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Premium includes ${unitsLabel(status.wallet?.monthlyUnits ?? 250)} every month. Top up any time if you need more.',
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.push('/premium'),
                child: const Text('Get Premium'),
              ),
              if (status.rates.isNotEmpty) ...[
                const SizedBox(height: 24),
                _Rates(rates: status.rates),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => const SignInPrompt(
    icon: Icons.cloud_off_outlined,
    title: 'Reborn AI is resting',
    message: "Reborn AI isn't available right now. Please try again soon.",
  );
}

class _Rates extends StatelessWidget {
  const _Rates({required this.rates});
  final List<AIRate> rates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What things cost', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final r in rates)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(r.label)),
                Text(r.cost, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Charts and pictures cost on top of the reply they come with. Replaying audio is free.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Candlelight.of(context).muted,
          ),
        ),
      ],
    );
  }
}

class _Chat extends ConsumerStatefulWidget {
  const _Chat({required this.status});
  final AIStatus status;

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  VoiceRecorder? _recorder;
  bool _recording = false;
  Timer? _limit;
  VideoPlayerController? _player;
  String? _playing;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _limit?.cancel();
    _recorder?.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _scrollToEnd();
    final failed = await ref.read(aiChatProvider.notifier).send(text);
    if (failed != null && _input.text.isEmpty) _input.text = failed;
    _scrollToEnd();
  }

  Future<void> _toggleMic() async {
    if (_recording) return _stopMic();
    final rec = _recorder ??= ref.read(voiceRecorderFactoryProvider)();
    bool started;
    try {
      started = await rec.start();
    } catch (_) {
      started = false;
    }
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Allow the microphone to send voice messages.'),
        ),
      );
      return;
    }
    setState(() => _recording = true);
    _limit = Timer(VoiceRecorder.maxDuration, _stopMic);
  }

  Future<void> _stopMic() async {
    _limit?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    final wav = await _recorder!.stop();
    if (wav == null || !mounted) return;
    _scrollToEnd();
    await ref.read(aiChatProvider.notifier).sendVoice(wav);
    _scrollToEnd();
  }

  Future<void> _listen(AIMessage m) async {
    if (_playing == m.id && _player != null) {
      final p = _player!;
      p.value.isPlaying ? await p.pause() : await p.play();
      setState(() {});
      return;
    }
    final url = await ref.read(aiChatProvider.notifier).speak(m.id);
    if (url == null || !mounted) return;
    await _player?.dispose();
    final p = ref.read(videoControllerFactoryProvider)(
      Uri.parse(resolveMediaUrl(url)),
    );
    _player = p;
    setState(() => _playing = m.id);
    p.addListener(() {
      if (mounted && _player == p) setState(() {});
    });
    try {
      await p.initialize();
      await p.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("The audio couldn't play.")),
        );
      }
    }
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
    final state = ref.watch(aiChatProvider);
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final wallet = state.wallet ?? widget.status.wallet;
    final empty = state.messages.isEmpty && state.pending == null;
    final count = state.messages.length + (state.pending != null ? 2 : 0);
    return Column(
      children: [
        if (wallet != null)
          ReadingWidth(
            child: _WalletBar(wallet: wallet, status: widget.status),
          ),
        Expanded(
          child: empty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: ReadingWidth(
                      maxWidth: 460,
                      child: Text(
                        'Ask anything, talk with the mic, or ask for a chart or picture. “Sketch a calm morning routine.” “Chart my week: 2, 4, 3, 5 hours of focus.”',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    if (i >= state.messages.length) {
                      final pending = state.pending!;
                      if (i == state.messages.length) {
                        return ReadingWidth(
                          child: _UserBubble(
                            text: pending.isEmpty ? 'Voice message…' : pending,
                            voice: pending.isEmpty,
                          ),
                        );
                      }
                      return const ReadingWidth(child: _Thinking());
                    }
                    final m = state.messages[i];
                    return ReadingWidth(
                      child: m.isUser
                          ? _UserBubble(text: m.content, voice: m.voice)
                          : _ReplyBubble(
                              message: m,
                              playing:
                                  _playing == m.id &&
                                  (_player?.value.isPlaying ?? false),
                              onListen: () => _listen(m),
                            ),
                    );
                  },
                ),
        ),
        if (state.outOfUnits)
          ReadingWidth(
            child: _Note(
              color: c.inset,
              text:
                  "You've used all your AI units. Top up to keep going${wallet?.resetLabel.isNotEmpty == true ? ', or wait until your allowance ${wallet!.resetLabel.toLowerCase()}' : ''}.",
              action: TextButton(
                onPressed: () => _showTopUp(context, widget.status),
                child: const Text('Top up'),
              ),
            ),
          ),
        if (state.error != null)
          ReadingWidth(
            child: _Note(
              color: theme.colorScheme.errorContainer,
              textColor: theme.colorScheme.onErrorContainer,
              text: state.error!,
            ),
          ),
        SafeArea(
          top: false,
          child: ReadingWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_recording,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _recording
                            ? 'Listening… tap stop to send'
                            : 'Message Reborn AI…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: _recording ? 'Stop and send' : 'Voice message',
                    color: _recording ? c.oxblood : null,
                    onPressed: state.sending && !_recording ? null : _toggleMic,
                    icon: Icon(
                      _recording ? Icons.stop_circle_outlined : Icons.mic_none,
                    ),
                  ),
                  IconButton.filled(
                    style: amberIconButtonStyle,
                    tooltip: 'Send',
                    onPressed: state.sending || _recording ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WalletBar extends StatelessWidget {
  const _WalletBar({required this.wallet, required this.status});
  final AIWallet wallet;
  final AIStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${unitsLabel(wallet.remaining)} left',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: wallet.allowanceShare,
                    minHeight: 5,
                    color: c.amber,
                    backgroundColor: c.line,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    wallet.summary,
                    if (wallet.resetLabel.isNotEmpty) wallet.resetLabel,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _showTopUp(context, status),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Top up'),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.color,
    required this.text,
    this.textColor,
    this.action,
  });
  final Color color;
  final Color? textColor;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: TextStyle(color: textColor)),
        ),
        ?action,
      ],
    ),
  );
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, this.voice = false});
  final String text;
  final bool voice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (voice) ...[
              Icon(Icons.mic, size: 16, color: scheme.onPrimaryContainer),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({
    required this.message,
    required this.playing,
    required this.onListen,
  });
  final AIMessage message;
  final bool playing;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = Candlelight.of(context);
    final segments = parseReply(message.content, message.citations);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
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
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            avatar: const Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                            ),
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
            ),
            for (final a in message.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: a.chart != null
                    ? AIChart(chart: a.chart!)
                    : a.url.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: a.width > 0 && a.height > 0
                              ? a.width / a.height
                              : 1,
                          child: Image.network(
                            resolveMediaUrl(a.url),
                            fit: BoxFit.cover,
                            semanticLabel: a.alt,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: c.inset,
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: message.id.isEmpty ? null : onListen,
                  icon: Icon(
                    playing ? Icons.pause : Icons.volume_up_outlined,
                    size: 18,
                  ),
                  label: Text(playing ? 'Pause' : 'Listen'),
                ),
                const Spacer(),
                if (message.units > 0)
                  Text(
                    unitsLabel(message.units),
                    style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatsSheet extends ConsumerWidget {
  const _ChatsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(aiConversationsProvider);
    final current = ref.watch(aiChatProvider.select((s) => s.conversationId));
    return SafeArea(
      child: switch (chats) {
        AsyncValue(:final value?) when value.isEmpty => const Padding(
          padding: EdgeInsets.all(32),
          child: Text('No chats yet.', textAlign: TextAlign.center),
        ),
        AsyncValue(:final value?) => ListView(
          shrinkWrap: true,
          children: [
            for (final chat in value)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(
                  chat.title.isEmpty ? 'Untitled chat' : chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: chat.id == current,
                onTap: () {
                  Navigator.pop(context);
                  ref.read(aiChatProvider.notifier).open(chat);
                },
                trailing: IconButton(
                  tooltip: 'Delete chat',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref.read(aiChatProvider.notifier).delete(chat.id);
                    ref.invalidate(aiConversationsProvider);
                  },
                ),
              ),
          ],
        ),
        AsyncValue(:final error?) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(aiConversationsProvider),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

void _showTopUp(BuildContext context, AIStatus status) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TopUpSheet(status: status),
    );

/// Store prices for the unit packs on this device, or null when they can't
/// be bought here.
final _packPricesProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, AIStatus>((ref, status) async {
      final store = ref.watch(giftStoreProvider);
      final platform = store.platform;
      if (platform == null || status.providers[platform.provider] != true) {
        return null;
      }
      try {
        if (!await store.isAvailable()) return null;
        final prices = await store.prices({
          for (final p in status.packs) p.productId,
        });
        return prices.isEmpty ? null : prices;
      } catch (_) {
        return null;
      }
    });

class _TopUpSheet extends ConsumerStatefulWidget {
  const _TopUpSheet({required this.status});
  final AIStatus status;

  @override
  ConsumerState<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<_TopUpSheet> {
  String? _buying;
  String? _error;

  Future<void> _buy(UnitPack pack) async {
    setState(() {
      _buying = pack.id;
      _error = null;
    });
    try {
      final topUp = await ref.read(topUpServiceProvider).buy(pack);
      if (!mounted) return;
      ref.read(aiChatProvider.notifier).dismissError();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${unitsLabel(topUp.units)}.')),
      );
    } on GiftCancelled {
      if (mounted) setState(() => _buying = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _buying = null;
          _error = e is GiftException ? e.message : AIChatController.message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final prices = ref.watch(_packPricesProvider(widget.status));
    final buyable = prices.value != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Top up AI units', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Top-up units never expire. Your monthly allowance is used first.',
              style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
            ),
            const SizedBox(height: 16),
            for (final pack in widget.status.packs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(unitsLabel(pack.units)),
                  subtitle: Text(pack.name),
                  trailing: _buying == pack.id
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton(
                          onPressed: buyable && _buying == null
                              ? () => _buy(pack)
                              : null,
                          child: Text(
                            prices.value?[pack.productId] ?? pack.displayPrice,
                          ),
                        ),
                ),
              ),
            if (prices.hasValue && !buyable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Top-ups aren\'t available on this device yet. You can top up on the Reborn website.',
                  style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (widget.status.rates.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Rates(rates: widget.status.rates),
            ],
          ],
        ),
      ),
    );
  }
}
