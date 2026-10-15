import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/ai_models.dart';
import '../../api/api_client.dart';
import '../../api/member_models.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The default narration voice, as on the server.
const kDefaultStudioVoice = 'af_heart';

/// "250 units a month buy about 12 videos, 62 illustrations or 83
/// one-minute audios."
String studioAllowanceLine(StudioStatus s) =>
    '${unitsLabel(s.monthlyUnits)} a month buy about ${s.allowanceLine}.';

/// The card studio on one of my cards: an image, the card read aloud, or an
/// illustrated video, each priced in AI units on its button before anything
/// is spent. Premium only. Each kind of media can be removed for free.
class CardStudio extends ConsumerStatefulWidget {
  const CardStudio({
    super.key,
    required this.card,
    required this.onCard,
    this.dirty = false,
  });

  final IdeaCard card;

  /// Called with the card after media is made or removed.
  final ValueChanged<IdeaCard> onCard;

  /// The editor has unsaved changes: media is made from the saved card.
  final bool dirty;

  @override
  ConsumerState<CardStudio> createState() => _CardStudioState();
}

class _CardStudioState extends ConsumerState<CardStudio> {
  StudioStyle _style = StudioStyle.illustration;
  String _shape = 'landscape';
  String _voice = kDefaultStudioVoice;
  final _prompt = TextEditingController();

  /// `image`, `audio` or `video` while it is being made or removed.
  String? _busy;
  bool _removing = false;
  AIWallet? _wallet;
  _Problem? _problem;

  @override
  void initState() {
    super.initState();
    final v = widget.card.video?.voice ?? widget.card.audio?.voice ?? '';
    if (v.isNotEmpty) _voice = v;
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _make(String kind) async {
    final repo = ref.read(repositoryProvider);
    final id = widget.card.id;
    setState(() {
      _busy = kind;
      _removing = false;
      _problem = null;
    });
    try {
      final r = switch (kind) {
        'image' => await repo.makeCardImage(
          id,
          style: _style.name,
          prompt: _prompt.text.trim(),
          shape: _shape,
        ),
        'audio' => await repo.makeCardAudio(id, voice: _voice),
        _ => await repo.makeCardVideo(id, voice: _voice),
      };
      if (!mounted) return;
      widget.onCard(r.card);
      setState(() {
        _busy = null;
        _wallet = r.wallet ?? _wallet;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.units > 0 ? 'Done. That used ${unitsLabel(r.units)}.' : 'Done.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _problem = _Problem.of(e);
      });
    }
  }

  Future<void> _remove(String kind) async {
    setState(() {
      _busy = kind;
      _removing = true;
      _problem = null;
    });
    try {
      final card = await ref
          .read(repositoryProvider)
          .deleteCardMedia(widget.card.id, kind);
      if (!mounted) return;
      widget.onCard(card);
      setState(() => _busy = null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _problem = _Problem(errorMessage(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(studioProvider);
    return Card(
      key: const ValueKey('card-studio'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: Candlelight.of(context).amberText,
                ),
                const SizedBox(width: 8),
                Text('Card studio', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Add a picture, a voice or an illustrated video with Reborn AI.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            status.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LoadingView(),
              ),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(studioProvider),
              ),
              data: _body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(StudioStatus s) {
    if (!s.available) return const _Problem(kAIOff).view(context);
    if (!s.premium) return const _Problem.premium().view(context);
    final theme = Theme.of(context);
    final card = widget.card;
    final wallet = _wallet ?? s.wallet;
    final busy = _busy != null;
    final locked = busy || widget.dirty;
    final voices = s.voices.isEmpty
        ? const [StudioVoice(id: kDefaultStudioVoice, name: 'Heart')]
        : s.voices;
    final voice = voices.any((v) => v.id == _voice) ? _voice : voices.first.id;
    final audioUnits = s.audioUnits(card.title, card.body, card.applyIt);
    final videoUnits = s.videoUnits(card.title, card.body, card.applyIt);

    Widget voicePicker(String key) => DropdownButtonFormField<String>(
      key: ValueKey('$key-$voice'),
      initialValue: voice,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Voice', isDense: true),
      items: [
        for (final v in voices)
          DropdownMenuItem(value: v.id, child: Text(v.name)),
      ],
      onChanged: locked ? null : (v) => setState(() => _voice = v ?? _voice),
    );

    Widget actions({
      required String kind,
      required String make,
      required int units,
      required bool has,
    }) => Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          key: ValueKey('studio-make-$kind'),
          onPressed: locked ? null : () => _make(kind),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text('${has ? 'Remake' : make} · ${unitsLabel(units)}'),
        ),
        if (has)
          TextButton(
            key: ValueKey('studio-remove-$kind'),
            onPressed: busy ? null : () => _remove(kind),
            child: Text('Remove $kind'),
          ),
      ],
    );

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wallet != null)
          Text(
            '${unitsLabel(wallet.remaining)} left this month',
            key: const ValueKey('studio-wallet'),
            style: theme.textTheme.titleSmall,
          ),
        Text(studioAllowanceLine(s), style: theme.textTheme.bodySmall),
        if (widget.dirty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Save your changes first: the studio works from the saved card.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (_busy != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              key: const ValueKey('studio-progress'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_progressText),
              ],
            ),
          ),
        if (_problem != null) _problem!.view(context),
        section('Image', [
          SegmentedButton<StudioStyle>(
            key: const ValueKey('studio-style'),
            segments: [
              for (final st in StudioStyle.values)
                ButtonSegment(
                  value: st,
                  label: Text('${st.label} (${s.imageUnits(st)})'),
                ),
            ],
            selected: {_style},
            showSelectedIcon: false,
            onSelectionChanged: locked
                ? null
                : (v) => setState(() => _style = v.first),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('studio-prompt'),
            controller: _prompt,
            enabled: !locked,
            maxLength: 1000,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Describe the image (optional)',
              helperText: 'Left empty, the picture is drawn from the card.',
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in const [
                ('landscape', 'Landscape'),
                ('square', 'Square'),
                ('portrait', 'Portrait'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _shape == value,
                  onSelected: locked
                      ? null
                      : (_) => setState(() => _shape = value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          actions(
            kind: 'image',
            make: 'Make image',
            units: s.imageUnits(_style),
            has: card.image != null,
          ),
        ]),
        section('Audio', [
          Text(
            'The card read aloud: 1 unit per 50 words.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          voicePicker('studio-voice-audio'),
          const SizedBox(height: 8),
          actions(
            kind: 'audio',
            make: 'Make audio',
            units: audioUnits,
            has: card.audio != null,
          ),
        ]),
        section('Video', [
          Text(
            '${s.videoScenes} illustrations that move with the narration.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          voicePicker('studio-voice-video'),
          const SizedBox(height: 8),
          actions(
            kind: 'video',
            make: 'Make video',
            units: videoUnits,
            has: card.video != null,
          ),
        ]),
      ],
    );
  }

  String get _progressText {
    if (_removing) return 'Removing…';
    return switch (_busy) {
      'image' => 'Making your image… this can take a little while',
      'audio' => 'Recording your card…',
      _ => 'Making your video… this can take a minute',
    };
  }
}

const kAIOff = "AI isn't switched on yet.";

/// Why the studio couldn't make something, with the way forward.
class _Problem {
  const _Problem(this.message, {this.topUp = false}) : premium = false;
  const _Problem.premium()
    : message = 'The card studio is part of Premium.',
      topUp = false,
      premium = true;

  final String message;
  final bool topUp;
  final bool premium;

  factory _Problem.of(Object e) {
    if (e is ApiException) {
      if (e.statusCode == 402 || e.code == 'out_of_units') {
        return const _Problem('Not enough AI units.', topUp: true);
      }
      if (e.statusCode == 403 || e.code == 'premium_required') {
        return const _Problem.premium();
      }
      if (e.statusCode == 503 || e.code == 'ai_unavailable') {
        return const _Problem(kAIOff);
      }
      if (e.statusCode == 422 || e.code == 'declined') {
        return const _Problem(
          "The image was turned down. Try describing it another way.",
        );
      }
    }
    return _Problem(errorMessage(e));
  }

  Widget view(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('studio-problem'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Candlelight.of(context).inset,
        borderRadius: BorderRadius.circular(CandlelightTokens.radiusInset),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          if (topUp || premium) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => context.push(topUp ? '/ai' : '/premium'),
              child: Text(topUp ? 'Top up AI units' : 'See Premium'),
            ),
          ],
        ],
      ),
    );
  }
}
