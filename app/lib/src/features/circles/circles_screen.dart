import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../layout/adaptive.dart';
import '../../widgets/common.dart';
import '../discover/discover_screen.dart';
import 'circle_screen.dart';

/// Book circles: yours, and all of them to browse. On expanded windows the
/// open circle shows on the right.
class CirclesScreen extends ConsumerWidget {
  const CirclesScreen({super.key});

  static const pane = 'circles';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(paneSelectionProvider(pane));
    final id = selected is String ? selected : null;
    return ListDetail(
      list: _list(context, ref),
      selectedId: id,
      detail: () => CircleScreen(circleId: id!),
      empty: const EmptyDetail(
        icon: Icons.groups_outlined,
        text: 'Pick a circle to join the conversation here.',
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    return DefaultTabController(
      length: 2,
      initialIndex: signedIn ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Book circles'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Yours'),
              Tab(text: 'Browse'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            signedIn
                ? const _CircleList(
                    query: (source: null, mine: true),
                    empty:
                        "You're not in any circles yet. Join one, or start "
                        'one from a book page.',
                  )
                : const SignInPrompt(
                    icon: Icons.groups_outlined,
                    title: 'Read together',
                    message: 'Sign in to join circles and talk about books.',
                  ),
            const _CircleList(
              query: (source: null, mine: false),
              empty: 'No circles yet. Start one from any book page.',
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleList extends ConsumerWidget {
  const _CircleList({required this.query, required this.empty});
  final CircleQuery query;
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(circlesProvider(query));
    return circles.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(circlesProvider(query)),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(circlesProvider(query).future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: list.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(empty, textAlign: TextAlign.center),
                  ),
                ]
              : [for (final c in list) _tile(context, ref, c)],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, Circle c) {
    if (!WindowSize.of(context).isTwoPane) return CircleTile(circle: c);
    final pane = paneSelectionProvider(CirclesScreen.pane);
    return CircleTile(
      circle: c,
      selected: ref.watch(pane) == c.id,
      onTap: () => ref.read(pane.notifier).select(c.id),
    );
  }
}

/// The "Circles" section of a source screen, with a create button.
class SourceCircles extends ConsumerWidget {
  const SourceCircles({
    super.key,
    required this.sourceId,
    required this.sourceTitle,
  });
  final String sourceId;
  final String sourceTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (source: sourceId, mine: false);
    final circles = ref.watch(circlesProvider(query));
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Circles', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                key: const ValueKey('start-circle'),
                onPressed: () =>
                    showCreateCircle(context, ref, sourceId, sourceTitle),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Start a circle'),
              ),
            ],
          ),
        ),
        ...circles.when(
          loading: () => const [SizedBox(height: 8)],
          error: (_, _) => const [SizedBox.shrink()],
          data: (list) => list.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'No circles for this book yet. Start one to read it '
                      'with others.',
                    ),
                  ),
                ]
              : [for (final c in list) CircleTile(circle: c)],
        ),
      ],
    );
  }
}

/// Asks for a name and description, creates the circle and opens it.
Future<void> showCreateCircle(
  BuildContext context,
  WidgetRef ref,
  String sourceId,
  String sourceTitle,
) async {
  if (!ensureSignedIn(context, ref)) return;
  final created = await showDialog<Circle>(
    context: context,
    builder: (_) =>
        _CreateCircleDialog(sourceId: sourceId, sourceTitle: sourceTitle),
  );
  if (created == null || !context.mounted) return;
  ref.invalidate(circlesProvider);
  context.push('/circles/${Uri.encodeComponent(created.id)}');
}

class _CreateCircleDialog extends ConsumerStatefulWidget {
  const _CreateCircleDialog({
    required this.sourceId,
    required this.sourceTitle,
  });
  final String sourceId;
  final String sourceTitle;

  @override
  ConsumerState<_CreateCircleDialog> createState() =>
      _CreateCircleDialogState();
}

class _CreateCircleDialogState extends ConsumerState<_CreateCircleDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: '${widget.sourceTitle} readers',
  );
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref
          .read(repositoryProvider)
          .createCircle(
            widget.sourceId,
            _name.text.trim(),
            description: _description.text.trim(),
          );
      if (mounted) Navigator.pop(context, c);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Start a circle'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'A small group (up to 50) to read and discuss '
            '${widget.sourceTitle}.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('circle-name'),
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          TextFormField(
            controller: _description,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _create,
        child: const Text('Create'),
      ),
    ],
  );
}
