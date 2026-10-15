import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

typedef SearchQuery = ({String q, String? topic});

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<IdeaCard>, SearchQuery>((ref, query) {
      return ref.watch(repositoryProvider).search(query.q, topic: query.topic);
    });

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String? _topic;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _q = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
    final hasQuery = _q.isNotEmpty || _topic != null;
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Search'),
        actions: const [
          ThemeToggleButton(),
          ProfileMenuButton(),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          ReadingWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SearchBar(
                controller: _controller,
                hintText: 'Search ideas, e.g. sleep, habits, anger',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(0),
                onChanged: _onChanged,
                onSubmitted: (t) {
                  _debounce?.cancel();
                  setState(() => _q = t.trim());
                },
                trailing: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _q = '');
                      },
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in topics)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(t.name),
                      selected: _topic == t.slug,
                      onSelected: (on) =>
                          setState(() => _topic = on ? t.slug : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: !hasQuery
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Search the library by word or pick a topic.',
                      ),
                    ),
                  )
                : ref
                      .watch(searchResultsProvider((q: _q, topic: _topic)))
                      .when(
                        loading: () => const LoadingView(),
                        error: (e, _) => ErrorView(
                          error: e,
                          onRetry: () => ref.invalidate(
                            searchResultsProvider((q: _q, topic: _topic)),
                          ),
                        ),
                        data: (cards) => cards.isEmpty
                            ? const Center(
                                child: Text('No ideas match that yet.'),
                              )
                            : ListView.separated(
                                itemCount: cards.length,
                                separatorBuilder: (_, _) => const ReadingWidth(
                                  child: Divider(height: 1),
                                ),
                                itemBuilder: (_, i) => ReadingWidth(
                                  child: CardTile(card: cards[i]),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
