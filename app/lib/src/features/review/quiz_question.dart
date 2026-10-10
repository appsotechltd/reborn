import 'package:flutter/material.dart';

import '../../api/models.dart';

/// A multiple-choice question. After a choice it marks the right answer,
/// shows the explanation and calls [onAnswered].
class QuizQuestion extends StatefulWidget {
  const QuizQuestion({super.key, required this.quiz, required this.onAnswered});
  final Quiz quiz;
  final void Function(bool correct) onAnswered;

  @override
  State<QuizQuestion> createState() => _QuizQuestionState();
}

class _QuizQuestionState extends State<QuizQuestion> {
  int? _chosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quiz = widget.quiz;
    final answered = _chosen != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(quiz.question, style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        for (var i = 0; i < quiz.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionButton(
              label: quiz.options[i],
              state: !answered
                  ? _OptionState.idle
                  : i == quiz.answer
                  ? _OptionState.correct
                  : i == _chosen
                  ? _OptionState.wrong
                  : _OptionState.dimmed,
              onTap: answered
                  ? null
                  : () {
                      setState(() => _chosen = i);
                      widget.onAnswered(i == quiz.answer);
                    },
            ),
          ),
        if (answered) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _chosen == quiz.answer ? Icons.check_circle : Icons.cancel,
                color: _chosen == quiz.answer ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                _chosen == quiz.answer ? 'Correct' : 'Not quite',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          if (quiz.explanation != null && quiz.explanation!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(quiz.explanation!, style: theme.textTheme.bodyLarge),
          ],
        ],
      ],
    );
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.label, required this.state, this.onTap});
  final String label;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (state) {
      _OptionState.correct => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      _OptionState.wrong => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHigh, scheme.onSurface),
    };
    return Opacity(
      opacity: state == _OptionState.dimmed ? 0.6 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Text(label, style: TextStyle(color: fg, fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
