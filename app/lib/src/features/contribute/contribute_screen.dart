import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

const kSourceKinds = [
  'book',
  'textbook',
  'article',
  'guide',
  'study',
  'talk',
  'podcast',
  'video',
];
const kMinBodyWords = 25;
const kMaxBodyWords = 160;

class ContributeScreen extends ConsumerStatefulWidget {
  const ContributeScreen({super.key});

  @override
  ConsumerState<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends ConsumerState<ContributeScreen> {
  final _form = GlobalKey<FormState>();
  final _sourceTitle = TextEditingController();
  final _authors = TextEditingController();
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _applyIt = TextEditingController();
  final _tags = TextEditingController();
  final _question = TextEditingController();
  final _options = List.generate(4, (_) => TextEditingController());
  final _explanation = TextEditingController();
  String _kind = 'book';
  String? _topic;
  bool _withQuiz = false;
  int _answer = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [
      _sourceTitle,
      _authors,
      _url,
      _title,
      _body,
      _applyIt,
      _tags,
      _question,
      _explanation,
      ..._options,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    Quiz? quiz;
    if (_withQuiz) {
      final filled = <String>[];
      var answer = 0;
      for (var i = 0; i < _options.length; i++) {
        final t = _options[i].text.trim();
        if (t.isEmpty) continue;
        if (i == _answer) answer = filled.length;
        filled.add(t);
      }
      if (filled.length < 2 || _options[_answer].text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A quiz needs at least two options and a marked correct answer.',
            ),
          ),
        );
        return;
      }
      quiz = Quiz(
        question: _question.text.trim(),
        options: filled,
        answer: answer,
        explanation: _explanation.text.trim().isEmpty
            ? null
            : _explanation.text.trim(),
      );
    }
    final draft = ContributionDraft(
      source: ContributionSource(
        title: _sourceTitle.text.trim(),
        authors: _split(_authors.text),
        url: _url.text.trim(),
        kind: _kind,
      ),
      topic: _topic!,
      title: _title.text.trim(),
      body: _body.text.trim(),
      applyIt: _applyIt.text.trim(),
      tags: _split(_tags.text).map((t) => t.toLowerCase()).toList(),
      quiz: quiz,
    );
    setState(() => _submitting = true);
    try {
      await ref.read(repositoryProvider).contribute(draft);
      ref.invalidate(myContributionsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks! Your idea is waiting for review.'),
        ),
      );
      context.pushReplacement('/contributions');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(
          leading: exitLeading(context),
          title: const Text('Contribute'),
        ),
        body: const SignInPrompt(
          icon: Icons.edit_note,
          title: 'Share an idea',
          message: 'Sign in to submit an idea from a book or article. Moderators review every submission.',
        ),
      );
    }
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
    final theme = Theme.of(context);
    final words = wordCount(_body.text);
    final wordsOk = words >= kMinBodyWords && words <= kMaxBodyWords;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Contribute an idea'),
        actions: [
          TextButton(
            onPressed: () => context.push('/contributions'),
            child: const Text('My contributions'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Source', style: theme.textTheme.titleMedium),
                    gap,
                    TextFormField(
                      controller: _sourceTitle,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: _required,
                    ),
                    gap,
                    TextFormField(
                      controller: _authors,
                      decoration: const InputDecoration(
                        labelText: 'Authors',
                        helperText: 'Separate several with commas',
                      ),
                      validator: (v) => _split(v ?? '').isEmpty
                          ? 'At least one author'
                          : null,
                    ),
                    gap,
                    TextFormField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Link (https://…)',
                      ),
                      validator: (v) {
                        final u = Uri.tryParse(v?.trim() ?? '');
                        return (u == null ||
                                !u.hasScheme ||
                                !u.scheme.startsWith('http') ||
                                u.host.isEmpty)
                            ? 'Enter a full link'
                            : null;
                      },
                    ),
                    gap,
                    DropdownButtonFormField<String>(
                      initialValue: _kind,
                      decoration: const InputDecoration(labelText: 'Kind'),
                      items: [
                        for (final k in kSourceKinds)
                          DropdownMenuItem(
                            value: k,
                            child: Text(k[0].toUpperCase() + k.substring(1)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _kind = v ?? 'book'),
                    ),
                    const SizedBox(height: 24),
                    Text('The idea', style: theme.textTheme.titleMedium),
                    gap,
                    DropdownButtonFormField<String>(
                      initialValue: _topic,
                      decoration: const InputDecoration(labelText: 'Topic'),
                      items: [
                        for (final t in topics)
                          DropdownMenuItem(value: t.slug, child: Text(t.name)),
                      ],
                      validator: (v) => v == null ? 'Choose a topic' : null,
                      onChanged: (v) => setState(() => _topic = v),
                    ),
                    gap,
                    TextFormField(
                      controller: _title,
                      maxLength: 90,
                      decoration: const InputDecoration(
                        labelText: 'Title — the idea in one line',
                      ),
                      validator: _required,
                    ),
                    gap,
                    TextFormField(
                      controller: _body,
                      minLines: 5,
                      maxLines: 12,
                      maxLength: 1200,
                      decoration: InputDecoration(
                        labelText: 'The idea in your own words',
                        alignLabelWithHint: true,
                        helperText:
                            '$words words · $kMinBodyWords–$kMaxBodyWords',
                        helperStyle: TextStyle(
                          color: wordsOk
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                      ),
                      validator: (v) {
                        final n = wordCount(v ?? '');
                        if (n < kMinBodyWords) {
                          return 'At least $kMinBodyWords words ($n so far)';
                        }
                        if (n > kMaxBodyWords) {
                          return 'At most $kMaxBodyWords words ($n now)';
                        }
                        return null;
                      },
                    ),
                    gap,
                    TextFormField(
                      controller: _applyIt,
                      maxLength: 240,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Apply it — one small action or question',
                      ),
                      validator: _required,
                    ),
                    gap,
                    TextFormField(
                      controller: _tags,
                      decoration: const InputDecoration(
                        labelText: 'Tags (optional)',
                        helperText: 'Comma separated, e.g. habits, focus',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Add a quiz question'),
                      subtitle: const Text('Helps readers remember the idea'),
                      value: _withQuiz,
                      onChanged: (v) => setState(() => _withQuiz = v),
                    ),
                    if (_withQuiz) ...[
                      TextFormField(
                        controller: _question,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'Question',
                        ),
                        validator: (v) => _withQuiz ? _required(v) : null,
                      ),
                      RadioGroup<int>(
                        groupValue: _answer,
                        onChanged: (v) => setState(() => _answer = v ?? 0),
                        child: Column(
                          children: [
                            for (var i = 0; i < _options.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Radio<int>(value: i),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _options[i],
                                        maxLength: 120,
                                        decoration: InputDecoration(
                                          labelText:
                                              'Option ${i + 1}${i < 2 ? '' : ' (optional)'}',
                                          counterText: '',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        'Select the correct answer with the radio button.',
                        style: theme.textTheme.bodySmall,
                      ),
                      gap,
                      TextFormField(
                        controller: _explanation,
                        maxLength: 300,
                        decoration: const InputDecoration(
                          labelText: 'Explanation (optional)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit for review'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Write in your own words and keep quotes short. Moderators check every idea before it is published with credit to the source.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
