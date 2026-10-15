import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notifications_screen.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../card/card_view.dart';
import 'quiz_question.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          if (signedIn)
            TextButton.icon(
              onPressed: () => context.push('/review/quiz'),
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('Quiz'),
            ),
          const NotificationBell(),
          const ProfileMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: !signedIn
          ? const SignInPrompt(
              icon: Icons.refresh,
              title: 'Remember what you read',
              message: 'Sign in to review saved ideas at the right moment and take quick quizzes.',
            )
          : ref
                .watch(reviewDueProvider)
                .when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(reviewDueProvider),
                  ),
                  data: (due) =>
                      ReviewSession(items: due.items, dueCount: due.dueCount),
                ),
    );
  }
}

/// Steps through due items: quiz (if any) first, then the card, then grading.
class ReviewSession extends ConsumerStatefulWidget {
  const ReviewSession({super.key, required this.items, required this.dueCount});
  final List<ReviewItem> items;
  final int dueCount;

  @override
  ConsumerState<ReviewSession> createState() => _ReviewSessionState();
}

class _ReviewSessionState extends ConsumerState<ReviewSession> {
  int _index = 0;
  bool _quizDone = false;
  bool _revealed = false;
  bool _grading = false;
  bool? _quizCorrect;
  String? _error;

  ReviewItem get _item => widget.items[_index];

  Future<void> _grade(Grade grade) async {
    setState(() {
      _grading = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).review(_item.card.id, grade);
      if (!mounted) return;
      setState(() {
        _index++;
        _quizDone = false;
        _revealed = false;
        _quizCorrect = null;
        _grading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _grading = false;
        _error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_index >= widget.items.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.task_alt, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                widget.items.isEmpty
                    ? 'Nothing due right now'
                    : 'All caught up',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                // True whether or not the reader has stashed anything yet:
                // a stashed idea is first due the next day.
                'Ideas you save come back here for review, first the next '
                'day, then at growing intervals.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => ref.invalidate(reviewDueProvider),
                    child: const Text('Check again'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => context.push('/review/quiz'),
                    child: const Text('Take a quiz'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final item = _item;
    final quiz = item.card.quiz;
    final askQuiz = quiz != null && !_quizDone;
    return SingleChildScrollView(
      key: ValueKey('review-${item.card.id}'),
      child: ReadingWidth(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: _index / widget.items.length,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                '${_index + 1} of ${widget.items.length}'
                '${widget.dueCount > widget.items.length ? ' · ${widget.dueCount} due' : ''}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (askQuiz) ...[
                Text(item.card.title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                QuizQuestion(
                  quiz: quiz,
                  onAnswered: (correct) =>
                      setState(() => _quizCorrect = correct),
                ),
                const SizedBox(height: 16),
                if (_quizCorrect != null)
                  FilledButton(
                    onPressed: () => setState(() {
                      _quizDone = true;
                      _revealed = true;
                    }),
                    child: const Text('Show the idea'),
                  ),
              ] else if (!_revealed) ...[
                Text(item.card.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text('Can you recall the idea and how to apply it?'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => setState(() => _revealed = true),
                  child: const Text('Show the idea'),
                ),
              ] else ...[
                Card(child: IdeaCardView(card: item.card, showActions: false)),
                const SizedBox(height: 16),
                Text(
                  'How well did you remember it?',
                  style: theme.textTheme.titleMedium,
                ),
                if (_quizCorrect != null)
                  Text(
                    _quizCorrect!
                        ? 'You got the quiz right.'
                        : 'You missed the quiz.',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                _GradeButtons(onGrade: _grading ? null : _grade),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GradeButtons extends StatelessWidget {
  const _GradeButtons({required this.onGrade});
  final void Function(Grade)? onGrade;

  @override
  Widget build(BuildContext context) {
    const labels = {
      Grade.again: 'Again',
      Grade.hard: 'Hard',
      Grade.good: 'Good',
      Grade.easy: 'Easy',
    };
    return Row(
      children: [
        for (final g in Grade.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: g == Grade.good
                  ? FilledButton(
                      onPressed: onGrade == null ? null : () => onGrade!(g),
                      child: Text(labels[g]!),
                    )
                  : OutlinedButton(
                      onPressed: onGrade == null ? null : () => onGrade!(g),
                      child: Text(labels[g]!),
                    ),
            ),
          ),
      ],
    );
  }
}
