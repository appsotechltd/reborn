import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/features/subjects/subject_controller.dart';
import 'package:reborn/src/router.dart';

import 'fake_server.dart';
import 'fixtures.dart';

const titles = ['Get to the point', 'Listen well', 'Say it kindly'];
const ids = ['clarity-one', 'clarity-two', 'clarity-three'];

Map<String, dynamic> subjectJson({Map<String, dynamic>? viewer}) => {
  'id': 'communication-clarity',
  'title': 'Communication Clarity',
  'description': 'Say what you mean, and be understood.',
  'topics': ['life-guides', 'communication'],
  'guide_count': 7,
  'part_count': 221,
  'minutes': 60,
  'viewer': ?viewer,
};

Map<String, dynamic> guideJson(int i, {Map<String, dynamic>? viewer}) => {
  'id': ids[i],
  'kind': 'topic',
  'title': titles[i],
  'description': 'Guide ${i + 1}.',
  'topic': 'life-guides',
  'topic_name': 'Life Guides',
  'coverage': 'guide',
  'authors': <String>[],
  'source_count': 2,
  'part_count': 3,
  'minutes': 2,
  'viewer': ?viewer,
};

Map<String, dynamic> detailFor(int i, {Map<String, dynamic>? viewer}) => {
  ...guideJson(i, viewer: viewer),
  'parts': [
    for (var p = 1; p <= 3; p++)
      cardJsonWith({
        'id': '${ids[i]}--0$p',
        'title': '${titles[i]}, part $p',
        'quote': null,
        'explainer': null,
      }),
  ],
  'subject': {
    'id': 'communication-clarity',
    'title': 'Communication Clarity',
    'step': i + 1,
    'count': 3,
    if (i < 2) 'next': {'id': ids[i + 1], 'title': titles[i + 1]},
  },
};

/// A subject of three guides; [viewers] gives the reader's place in each.
FakeServer subjectServer({
  List<Map<String, dynamic>?> viewers = const [null, null, null],
  Map<String, dynamic>? subjectViewer,
}) {
  final server = FakeServer()
    ..on(
      'GET /v1/topics',
      (_) => {
        'topics': [
          {'slug': 'life-guides', 'name': 'Life Guides'},
        ],
      },
    )
    ..on(
      'GET /v1/subjects',
      (c) => {
        'subjects': [
          if (c.query['topic'] == null || c.query['topic'] == 'life-guides')
            subjectJson(viewer: subjectViewer),
        ],
      },
    )
    ..on(
      'GET /v1/subjects/communication-clarity',
      (_) => {
        ...subjectJson(viewer: subjectViewer),
        'guide_count': 3,
        'guides': [
          for (var i = 0; i < 3; i++) guideJson(i, viewer: viewers[i]),
        ],
      },
    );
  for (var i = 0; i < 3; i++) {
    server
      ..on(
        'GET /v1/summaries/${ids[i]}',
        (_) => detailFor(i, viewer: viewers[i]),
      )
      ..on(
        'PUT /v1/summaries/${ids[i]}/progress',
        (c) => {
          'started': true,
          'position': (c.body as Map)['position'],
          'finished': (c.body as Map)['finished'],
        },
      );
  }
  return server;
}

/// The page on top, pushed pages included.
String topPath(ProviderContainer c) => c.read(routerProvider).state.uri.path;

const notStarted = {'started': false, 'position': 0, 'finished': false};
const done = {'started': true, 'position': 2, 'finished': true};

void main() {
  test('subjects and a guide\'s step parse and survive the cache', () {
    final s = Subject.fromJson(
      subjectJson(
        viewer: {
          'started': true,
          'finished': 3,
          'done': false,
          'next_summary_id': 'clarity-four',
        },
      ),
    );
    expect(s.meta, '7 guides · 60 min');
    expect(s.viewer!.finished, 3);
    expect(s.viewer!.nextSummaryId, 'clarity-four');
    final again = Subject.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
    );
    expect(again.viewer!.nextSummaryId, 'clarity-four');
    expect(again.topics, ['life-guides', 'communication']);

    final d = SummaryDetail.fromJson(detailFor(1));
    expect(d.subject!.label, 'Guide 2 of 3 · Communication Clarity');
    expect(d.subject!.next!.id, 'clarity-three');
    final cached = SummaryDetail.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
    );
    expect(cached.subject!.step, 2);
    expect(SummaryDetail.fromJson(detailFor(2)).subject!.isLast, isTrue);
    expect(
      SummaryDetail.fromJson({...detailFor(0), 'subject': null}).subject,
      isNull,
    );

    expect(nextGuide(const [SummaryProgress(finished: true), null]), 1);
    expect(nextGuide(const [SummaryProgress(finished: true)]), isNull);
  });

  testWidgets('a topic shows its subjects above the posts, with progress', (
    tester,
  ) async {
    final server = subjectServer(
      subjectViewer: {
        'started': true,
        'finished': 3,
        'done': false,
        'next_summary_id': 'clarity-four',
      },
    );
    final container = await pumpApp(tester, server, prefs: signedInPrefs);
    // "For you" has no subjects row.
    expect(find.text('Communication Clarity'), findsNothing);
    await tester.tap(find.text('Life Guides'));
    await tester.pumpAndSettle();
    expect(
      server.calls.where(
        (c) => c.path == '/v1/subjects' && c.query['topic'] == 'life-guides',
      ),
      isNotEmpty,
    );
    expect(
      find.byKey(const ValueKey('subjects-row-life-guides')),
      findsOneWidget,
    );
    expect(find.text('Communication Clarity'), findsOneWidget);
    expect(find.text('7 guides · 60 min'), findsOneWidget);
    expect(find.text('3 of 7 done'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('subject-card-communication-clarity')),
    );
    await tester.pumpAndSettle();
    expect(topPath(container), '/subjects/communication-clarity');
  });

  testWidgets('signed out, a subject card shows no progress', (tester) async {
    final server = subjectServer();
    await pumpApp(tester, server);
    await tester.tap(find.text('Life Guides'));
    await tester.pumpAndSettle();
    expect(find.text('Communication Clarity'), findsOneWidget);
    expect(find.textContaining('done'), findsNothing);
  });

  testWidgets('the subject lists its guides in order and continues', (
    tester,
  ) async {
    final server = subjectServer(
      viewers: [
        done,
        {'started': true, 'position': 1, 'finished': false},
        notStarted,
      ],
    );
    final container = await pumpApp(
      tester,
      server,
      prefs: signedInPrefs,
      location: '/subjects/communication-clarity',
    );
    expect(find.text('Communication Clarity'), findsWidgets);
    expect(find.text('Say what you mean, and be understood.'), findsOneWidget);
    expect(find.text('1. Get to the point'), findsOneWidget);
    expect(find.text('2. Listen well'), findsOneWidget);
    expect(find.text('3. Say it kindly'), findsOneWidget);
    expect(find.text('1 of 3 done'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-reading')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-not-started')), findsOneWidget);
    expect(find.textContaining('In progress · part 2 of 3'), findsOneWidget);
    expect(find.textContaining('Not started'), findsOneWidget);

    expect(find.text('Continue: Listen well'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('subject-start')));
    await tester.pumpAndSettle();
    expect(topPath(container), '/summaries/clarity-two');
    // The reader picks up where they stopped in that guide.
    expect(find.text('Listen well, part 2'), findsOneWidget);
    expect(find.text('Guide 2 of 3 · Communication Clarity'), findsOneWidget);

    // The subject line opens the subject again.
    await tester.tap(find.byKey(const ValueKey('summary-subject')));
    await tester.pumpAndSettle();
    expect(topPath(container), '/subjects/communication-clarity');
    // A tapped guide opens its reader.
    await tester.tap(find.byKey(const ValueKey('subject-guide-clarity-three')));
    await tester.pumpAndSettle();
    expect(topPath(container), '/summaries/clarity-three');
  });

  testWidgets('Start before any guide', (tester) async {
    final fresh = subjectServer();
    await pumpApp(tester, fresh, location: '/subjects/communication-clarity');
    expect(find.text('Start'), findsOneWidget);
    expect(find.byKey(const ValueKey('subject-progress')), findsNothing);
    expect(find.byKey(const ValueKey('guide-not-started')), findsNWidgets(3));
  });

  testWidgets('Read again once every guide is done', (tester) async {
    final finished = subjectServer(viewers: [done, done, done]);
    await pumpApp(
      tester,
      finished,
      prefs: signedInPrefs,
      location: '/subjects/communication-clarity',
    );
    expect(find.text('Read again'), findsOneWidget);
    expect(find.text('3 of 3 done'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-done')), findsNWidgets(3));
  });

  testWidgets('the end of a guide leads on to the next guide', (tester) async {
    final server = subjectServer();
    final container = await pumpApp(
      tester,
      server,
      location: '/summaries/clarity-one',
    );
    expect(find.text('Guide 1 of 3 · Communication Clarity'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('summary-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text("You've finished Get to the point"), findsOneWidget);
    expect(find.text('Next guide: Listen well'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('summary-next-guide')));
    await tester.pumpAndSettle();
    expect(topPath(container), '/summaries/clarity-two');
    expect(find.text('Listen well, part 1'), findsOneWidget);
    expect(find.text('Guide 2 of 3 · Communication Clarity'), findsOneWidget);

    // Having read the first guide, the subject continues with the second.
    await tester.tap(find.byKey(const ValueKey('summary-subject')));
    await tester.pumpAndSettle();
    expect(find.text('Continue: Listen well'), findsOneWidget);
  });

  testWidgets('the last guide leads back to its subject', (tester) async {
    final server = subjectServer();
    final container = await pumpApp(
      tester,
      server,
      location: '/summaries/clarity-three?view=all',
    );
    expect(find.text('Guide 3 of 3 · Communication Clarity'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('summary-next-guide')),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('summary-all')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Back to Communication Clarity'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('summary-next-guide')));
    await tester.pumpAndSettle();
    expect(topPath(container), '/subjects/communication-clarity');
  });

  testWidgets('Summaries lists the subjects first', (tester) async {
    final server = subjectServer()
      ..on('GET /v1/summaries', (_) => {'summaries': <Object>[]});
    await pumpApp(tester, server, location: '/summaries');
    expect(find.text('Subjects'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subject-card-communication-clarity')),
      findsOneWidget,
    );
  });
}
