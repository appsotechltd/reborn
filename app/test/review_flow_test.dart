import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/data/speaker.dart';
import 'package:reborn/src/features/review/review_screen.dart';
import 'package:reborn/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'fixtures.dart';

void main() {
  late FakeRepository repo;

  Future<void> pumpReview(WidgetTester tester, {bool signedIn = true}) async {
    SharedPreferences.setMockInitialValues({
      if (signedIn) 'auth.token': 'tok',
      if (signedIn) 'auth.user': '{"id":"u1","email":"a@b.com","display_name":"Ada","role":"member","topics":[]}',
    });
    final prefs = await SharedPreferences.getInstance();
    repo = FakeRepository(prefs)
      ..due = ReviewDue(
        dueCount: 2,
        items: [
          ReviewItem(
            card: sampleCard({
              'quiz': {
                'question': 'What did Marcus do each morning?',
                'options': ['Slept in', 'Expected difficult people'],
                'answer': 1,
                'explanation': 'He prepared for friction in advance.',
              },
            }),
          ),
          ReviewItem(card: healthCard()),
        ],
      );
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
          speakerProvider.overrideWithValue(FakeSpeaker()),
        ],
        child: MaterialApp(theme: lightTheme, home: const ReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('quiz first, then card, then grade; then next card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpReview(tester);

    // Card 1 has a quiz: the question comes before the card.
    expect(find.text('What did Marcus do each morning?'), findsOneWidget);
    expect(find.text(sampleCard().body), findsNothing);
    expect(find.text('Good'), findsNothing);

    await tester.tap(find.text('Expected difficult people'));
    await tester.pumpAndSettle();
    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('He prepared for friction in advance.'), findsOneWidget);

    await tester.tap(find.text('Show the idea'));
    await tester.pumpAndSettle();
    expect(find.text(sampleCard().body), findsOneWidget);
    expect(find.text(sampleCard().applyIt), findsOneWidget);
    for (final g in ['Again', 'Hard', 'Good', 'Easy']) {
      expect(find.text(g), findsOneWidget);
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Good'));
    await tester.pumpAndSettle();
    expect(repo.graded, [('meditations-marcus-aurelius--01', Grade.good)]);

    // Card 2 has no quiz: recall, reveal, grade.
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text(healthCard().title), findsOneWidget);
    await tester.tap(find.text('Show the idea'));
    await tester.pumpAndSettle();
    expect(find.text(healthDisclaimer), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Again'));
    await tester.pumpAndSettle();
    expect(repo.graded.last, ('nhs-sleep--01', Grade.again));

    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('signed out shows a sign-in prompt', (tester) async {
    await pumpReview(tester, signedIn: false);
    expect(find.text('Sign in'), findsOneWidget);
    expect(repo.graded, isEmpty);
  });
}
