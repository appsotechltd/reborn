import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/member_models.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../card/card_view.dart';
import '../card/illustrated_video_player.dart';
import '../listen/listen_controller.dart';
import 'card_studio.dart';
import 'my_cards_screen.dart';

/// Writes a new card ([cardId] null) or edits one of mine, with its media
/// and the card studio once it is saved.
class MyCardScreen extends ConsumerWidget {
  const MyCardScreen({super.key, this.cardId, this.initial});
  final String? cardId;

  /// The card as the list had it, shown while it loads.
  final IdeaCard? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final id = cardId;
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(
          leading: exitLeading(context),
          title: const Text('My card'),
        ),
        body: const SignInPrompt(
          icon: Icons.edit_note,
          title: 'Write your own cards',
          message: 'Sign in to write cards and share them.',
        ),
      );
    }
    if (id == null) return const _Editor(key: ValueKey('new-card'));
    final card = ref.watch(myCardProvider(id));
    final loaded = card.value ?? initial;
    if (loaded == null) {
      return Scaffold(
        appBar: AppBar(
          leading: exitLeading(context),
          title: const Text('My card'),
        ),
        body: card.hasError
            ? ErrorView(
                error: card.error!,
                onRetry: () => ref.invalidate(myCardProvider(id)),
              )
            : const LoadingView(),
      );
    }
    // Rebuilt from scratch when a different card arrives.
    return _Editor(key: ValueKey('card-${loaded.id}'), card: loaded);
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, this.card});
  final IdeaCard? card;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late IdeaCard? _card = widget.card;
  late final _title = TextEditingController(text: _card?.title ?? '');
  late final _body = TextEditingController(text: _card?.body ?? '');
  late final _applyIt = TextEditingController(text: _card?.applyIt ?? '');
  late String? _topic = _card?.topic;
  late String _categoryId = _card?.category?.id ?? '';
  late String _audience = _audienceOf(_card);
  bool _saving = false;
  String? _error;

  static String _audienceOf(IdeaCard? c) {
    final v = c?.visibility;
    return kAudiences.contains(v) ? v! : 'everyone';
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body, _applyIt]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _applyIt.dispose();
    super.dispose();
  }

  bool get _isNew => _card == null;

  /// The form differs from the saved card.
  bool get _dirty {
    final c = _card;
    if (c == null) return true;
    return _title.text.trim() != c.title ||
        _body.text.trim() != c.body ||
        _applyIt.text.trim() != c.applyIt ||
        _topic != c.topic ||
        _categoryId != (c.category?.id ?? '') ||
        (c.visibility != 'hidden' && _audience != _audienceOf(c));
  }

  String? _problem() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty) return 'Give your card a title.';
    if (title.length > kCardTitleMax) {
      return 'The title can be up to $kCardTitleMax characters.';
    }
    if (body.isEmpty) return 'Write the idea itself in the body.';
    if (body.length > kCardBodyMax) {
      return 'The body can be up to 1,500 characters.';
    }
    if (_applyIt.text.trim().length > kCardApplyItMax) {
      return '“Apply it” can be up to $kCardApplyItMax characters.';
    }
    if (_topic == null || _topic!.isEmpty) return 'Pick a topic.';
    return null;
  }

  Future<void> _save() async {
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final fields = <String, Object?>{
      'title': _title.text.trim(),
      'body': _body.text.trim(),
      'apply_it': _applyIt.text.trim(),
      'topic': _topic,
      'category_id': _categoryId,
      'audience': _audience,
    };
    final repo = ref.read(repositoryProvider);
    try {
      final saved = _isNew
          ? await repo.createMyCard(
              {...fields, if (_categoryId.isEmpty) 'category_id': null}
                ..removeWhere((_, v) => v == null),
            )
          : await repo.updateMyCard(_card!.id, fields);
      ref.invalidate(myCardsProvider);
      ref.invalidate(myCategoriesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isNew ? 'Card saved' : 'Changes saved')),
      );
      if (_isNew) {
        // Open the saved card, where the studio is.
        context.pushReplacement(
          '/me/cards/${Uri.encodeComponent(saved.id)}',
          extra: saved,
        );
        return;
      }
      setState(() {
        _card = saved;
        _saving = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this card?'),
        content: const Text(
          'It disappears from your page and from timelines. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).deleteMyCard(_card!.id);
      ref.invalidate(myCardsProvider);
      ref.invalidate(myCategoriesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Card deleted')));
      if (mounted) {
        context.canPop() ? context.pop() : context.go('/me/cards');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  void _onCard(IdeaCard card) {
    setState(() => _card = card);
    ref.invalidate(myCardsProvider);
    ref.invalidate(studioProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = _card;
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
    final cats = ref.watch(myCategoriesProvider).value ?? const [];
    final hidden = card?.visibility == 'hidden';
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: Text(_isNew ? 'New card' : 'Edit card'),
        actions: [
          if (!_isNew)
            IconButton(
              key: const ValueKey('delete-card'),
              tooltip: 'Delete card',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        children: [
          ReadingWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (card != null) ...[
                    Row(
                      children: [
                        VisibilityBadge(visibility: card.visibility),
                        const Spacer(),
                        if (card.createdAt != null)
                          Text(
                            shortDate(card.createdAt),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    if (hidden)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'This card was taken down after reports. Only you '
                          'can see it.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const ValueKey('card-title-field'),
                    controller: _title,
                    maxLength: kCardTitleMax,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('card-body-field'),
                    controller: _body,
                    maxLength: kCardBodyMax,
                    minLines: 5,
                    maxLines: 14,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'The idea',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('card-apply-field'),
                    controller: _applyIt,
                    maxLength: kCardApplyItMax,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Apply it (optional)',
                      helperText: 'One small step a reader can take today.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('card-topic-field'),
                    initialValue: topics.any((t) => t.slug == _topic)
                        ? _topic
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Topic'),
                    items: [
                      for (final t in topics)
                        DropdownMenuItem(value: t.slug, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _topic = v),
                  ),
                  const SizedBox(height: 16),
                  _categoryField(cats),
                  const SizedBox(height: 16),
                  Text('Who can see it', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final a in kAudiences)
                        ChoiceChip(
                          key: ValueKey('audience-$a'),
                          label: Text(audienceLabel(a)),
                          selected: _audience == a,
                          onSelected: hidden
                              ? null
                              : (_) => setState(() => _audience = a),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _audienceHelp(_audience),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const ValueKey('card-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('save-card'),
                    onPressed: _saving || (!_isNew && !_dirty) ? null : _save,
                    child: Text(
                      _saving
                          ? 'Saving…'
                          : _isNew
                          ? 'Save card'
                          : 'Save changes',
                    ),
                  ),
                  if (card != null) ..._media(card),
                  if (card != null) ...[
                    const SizedBox(height: 24),
                    CardStudio(card: card, onCard: _onCard, dirty: _dirty),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _audienceHelp(String a) => switch (a) {
    'followers' => 'People who follow you, and your subscribers.',
    'subscribers' => 'Only people who subscribe to you.',
    'private' => 'Only you. Nobody else sees it.',
    _ => 'Anyone on Reborn, in timelines and on your page.',
  };

  Widget _categoryField(List<CardCategory> cats) {
    const newValue = '__new__';
    final value = cats.any((c) => c.id == _categoryId) ? _categoryId : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('card-category-field-${cats.length}-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category (optional)'),
      items: [
        const DropdownMenuItem(value: '', child: Text('No category')),
        for (final c in cats)
          DropdownMenuItem(value: c.id, child: Text(c.name)),
        const DropdownMenuItem(value: newValue, child: Text('New category…')),
      ],
      onChanged: (v) async {
        if (v != newValue) {
          setState(() => _categoryId = v ?? '');
          return;
        }
        final c = await createCategory(context, ref);
        if (mounted) setState(() => _categoryId = c?.id ?? _categoryId);
      },
    );
  }

  List<Widget> _media(IdeaCard card) {
    final theme = Theme.of(context);
    if (card.video == null && card.image == null && card.audio == null) {
      return const [];
    }
    final playing = ref.watch(
      listenProvider.select(
        (s) => s.active && s.playing && s.current?.card.id == card.id,
      ),
    );
    return [
      const SizedBox(height: 24),
      Text('Media', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      if (card.video != null) ...[
        Center(
          child: IllustratedVideoPlayer(video: card.video!, title: card.title),
        ),
        const SizedBox(height: 12),
      ],
      if (card.image != null) ...[
        CardPicture(image: card.image!),
        const SizedBox(height: 12),
      ],
      if (card.audio != null)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('my-card-listen'),
            onPressed: () {
              final listen = ref.read(listenProvider.notifier);
              playing ? listen.stop() : listen.playCard(card);
            },
            icon: Icon(playing ? Icons.stop : Icons.headphones_outlined),
            label: Text(
              playing
                  ? 'Stop'
                  : 'Listen · ${card.audio!.voiceName.isEmpty ? 'audio' : card.audio!.voiceName}',
            ),
          ),
        ),
    ];
  }
}
