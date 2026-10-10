import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../home/feed_controller.dart';

/// First-run topic picker; also reachable later as "Your topics".
class TopicPickerScreen extends ConsumerStatefulWidget {
  const TopicPickerScreen({super.key, this.onboarding = true});
  final bool onboarding;

  @override
  ConsumerState<TopicPickerScreen> createState() => _TopicPickerScreenState();
}

class _TopicPickerScreenState extends ConsumerState<TopicPickerScreen> {
  late final Set<String> _selected = {...ref.read(topicPrefsProvider)};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(topicPrefsProvider.notifier).save(_selected.toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved on this device. ${errorMessage(e)}')),
        );
      }
    }
    ref.read(feedFilterProvider.notifier).select(null);
    ref.invalidate(feedProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    _leave();
  }

  void _leave() {
    if (widget.onboarding || !context.canPop()) {
      context.go('/home');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = ref.watch(topicsProvider);
    final theme = Theme.of(context);
    final list = topics.value ?? (topics.hasError ? kDefaultTopics : null);
    return Scaffold(
      appBar: widget.onboarding
          ? null
          : AppBar(title: const Text('Your topics')),
      body: SafeArea(
        child: list == null
            ? const LoadingView()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ReadingWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.onboarding) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Welcome to Reborn',
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Big ideas from great books, one minute at a time. What would you like to grow in?',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ] else
                        Text(
                          'Pick the topics for your feed.',
                          style: theme.textTheme.bodyLarge,
                        ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in list)
                            FilterChip(
                              label: Text(t.name),
                              selected: _selected.contains(t.slug),
                              onSelected: (on) => setState(() {
                                on
                                    ? _selected.add(t.slug)
                                    : _selected.remove(t.slug);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          if (widget.onboarding)
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () async {
                                      await ref
                                          .read(topicPrefsProvider.notifier)
                                          .markOnboarded();
                                      _leave();
                                    },
                              child: const Text('Skip'),
                            ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(
                              _selected.isEmpty
                                  ? 'Show me everything'
                                  : 'Continue with ${_selected.length}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
