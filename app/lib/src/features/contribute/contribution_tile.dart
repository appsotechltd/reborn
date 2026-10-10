import 'package:flutter/material.dart';

import '../../api/models.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, label) = switch (status) {
      'approved' => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        'Approved',
      ),
      'rejected' => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        'Rejected',
      ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, 'Pending'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Full text of a contribution, used in My contributions and Moderation.
class ContributionDetails extends StatelessWidget {
  const ContributionDetails({super.key, required this.c});
  final Contribution c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.body, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          'Apply it: ${c.applyIt}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Source: ${c.source.title} — ${c.source.authors.join(', ')} (${c.source.kind})',
          style: theme.textTheme.bodySmall,
        ),
        Text(c.source.url, style: theme.textTheme.bodySmall),
        if (c.tags.isNotEmpty)
          Text('Tags: ${c.tags.join(', ')}', style: theme.textTheme.bodySmall),
        if (c.quiz != null) ...[
          const SizedBox(height: 8),
          Text('Quiz: ${c.quiz!.question}', style: theme.textTheme.bodySmall),
          for (var i = 0; i < c.quiz!.options.length; i++)
            Text(
              '${i == c.quiz!.answer ? '✓' : '·'} ${c.quiz!.options[i]}',
              style: theme.textTheme.bodySmall,
            ),
        ],
        if (c.moderatorNote != null && c.moderatorNote!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Moderator note: ${c.moderatorNote}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}
