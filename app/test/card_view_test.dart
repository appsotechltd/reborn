import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/data/speaker.dart';
import 'package:reborn/src/features/card/card_view.dart';
import 'package:reborn/src/features/card/explainer_player.dart';
import 'package:reborn/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'fixtures.dart';

Future<FakeSpeaker> pumpCard(WidgetTester tester, IdeaCard card) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final speaker = FakeSpeaker();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(child: IdeaCardView(card: card)),
        ),
      ),
      GoRoute(
        path: '/sources/:id',
        builder: (_, s) =>
            Scaffold(body: Text('source page ${s.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(FakeRepository(prefs)),
        speakerProvider.overrideWithValue(speaker),
      ],
      child: MaterialApp.router(theme: lightTheme, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return speaker;
}

void main() {
  testWidgets('shows title, body, quote, apply it and the credit', (
    tester,
  ) async {
    final card = sampleCard();
    await pumpCard(tester, card);
    expect(find.text(card.title), findsOneWidget);
    expect(find.text(card.body), findsOneWidget);
    expect(find.textContaining('Begin the morning'), findsOneWidget);
    expect(find.text('APPLY IT'), findsOneWidget);
    expect(find.text(card.applyIt), findsOneWidget);
    expect(find.text(card.credit), findsOneWidget);
    expect(find.text('MINDFULNESS & PHILOSOPHY'), findsOneWidget);
    // No disclaimer on a non-health card.
    expect(find.byKey(const ValueKey('card-disclaimer')), findsNothing);
  });

  testWidgets('health card always shows its disclaimer and credit', (
    tester,
  ) async {
    final card = healthCard();
    await pumpCard(tester, card);
    expect(find.text(healthDisclaimer), findsOneWidget);
    expect(find.byKey(const ValueKey('card-disclaimer')), findsOneWidget);
    expect(find.text(card.credit), findsNothing); // credit lives on the source page
  });

  testWidgets('health card without disclaimer text still gets the notice', (
    tester,
  ) async {
    await pumpCard(tester, sampleCard({'health': true, 'disclaimer': null}));
    expect(find.text(kHealthDisclaimerFallback), findsOneWidget);
  });

  testWidgets('no source section at the bottom of the card', (tester) async {
    await pumpCard(tester, sampleCard());
    expect(find.byKey(const ValueKey('card-credit')), findsNothing);
  });

  testWidgets('Listen reads title, body and apply it; Stop stops', (
    tester,
  ) async {
    final card = sampleCard();
    final speaker = await pumpCard(tester, card);
    await tester.tap(find.text('Listen'));
    await tester.pump();
    expect(speaker.spoken.single, contains(card.title));
    expect(speaker.spoken.single, contains(card.body));
    expect(speaker.spoken.single, contains(card.applyIt));
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Listen'), findsOneWidget);
  });

  testWidgets('cards with an explainer show its poster and play button', (
    tester,
  ) async {
    final card = sampleCard({
      'explainer': {
        'kind': 'animated',
        'video_url': '/media/explainers/meditations-marcus-aurelius--01.mp4',
        'poster_url': '/media/explainers/meditations-marcus-aurelius--01.jpg',
        'captions_url': '/media/explainers/meditations-marcus-aurelius--01.vtt',
        'duration_s': 48.6,
        'width': 720,
        'height': 1280,
        'narrated': false,
      },
    });
    await pumpCard(tester, card);
    expect(find.byType(ExplainerPlayer), findsOneWidget);
    expect(
      find.bySemanticsLabel('Play animated explainer: ${card.title}'),
      findsOneWidget,
    );
    // Video posts carry the kicker, title and duration on the film.
    expect(find.text('ANIMATED EXPLAINER'), findsOneWidget);
    expect(find.text(card.title), findsOneWidget);
    expect(find.text('0:49'), findsOneWidget);
    // The credit stays on the card even with a video.
    expect(find.text(card.credit), findsNothing); // credit lives on the source page
  });

  testWidgets('cards without an explainer show no player', (tester) async {
    await pumpCard(tester, sampleCard());
    expect(find.byType(ExplainerPlayer), findsNothing);
  });

  testWidgets('share text always includes the credit', (tester) async {
    final text = shareText(healthCard());
    expect(text, contains('Source: NHS'));
    expect(text, contains(healthDisclaimer));
  });
}
