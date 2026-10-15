import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'quiz_question.dart';

final quizCardsProvider = FutureProvider.autoDispose<List<IdeaCard>>(
  (ref) => ref.watch(repositoryProvider).quiz(),
);

/// Quiz mode: questions from GET /v1/quiz; a right answer records `good`,
/// a wrong one `again`.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  int _index = 0;
  int _correct = 0;
  bool _answered = false;

  void _onAnswered(IdeaCard card, bool correct) {
    setState(() {
      _answered = true;
      if (correct) _correct++;
    });
    ref
        .read(repositoryProvider)
        .review(card.id, correct ? Grade.good : Grade.again)
        .then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: ref
          .watch(quizCardsProvider)
          .when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(quizCardsProvider),
            ),
            data: (cards) {
              final quizCards = cards.where((c) => c.quiz != null).toList();
              if (quizCards.isEmpty) {
                return const Center(
                  child: Text('No quiz questions yet. Save a few ideas first.'),
                );
              }
              if (_index >= quizCards.length) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_correct / ${quizCards.length} correct',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _index = 0;
                            _correct = 0;
                            _answered = false;
                          });
                          ref.invalidate(quizCardsProvider);
                        },
                        child: const Text('New quiz'),
                      ),
                    ],
                  ),
                );
              }
              final card = quizCards[_index];
              return SingleChildScrollView(
                child: ReadingWidth(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Question ${_index + 1} of ${quizCards.length}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        QuizQuestion(
                          key: ValueKey(card.id),
                          quiz: card.quiz!,
                          onAnswered: (c) => _onAnswered(card, c),
                        ),
                        const SizedBox(height: 12),
                        if (_answered) ...[
                          Text(card.credit, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => setState(() {
                              _index++;
                              _answered = false;
                            }),
                            child: Text(
                              _index + 1 < quizCards.length ? 'Next' : 'Finish',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}
