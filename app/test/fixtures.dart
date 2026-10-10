import 'dart:convert';

import 'package:reborn/src/api/models.dart';

/// The Card example from docs/API.md, verbatim.
const cardJsonExample = r'''
{
  "id": "meditations-marcus-aurelius--01",
  "title": "Expect difficult people before the day starts",
  "body": "Each morning, Marcus reminded himself...",
  "quote": "Begin the morning by saying to thyself...",
  "apply_it": "Before your next meeting, name one way it could go badly...",
  "topic": "mindfulness",
  "tags": ["stoicism"],
  "locator": "Book II, 1",
  "health": false,
  "disclaimer": null,
  "quiz": { "question": "...", "options": ["...", "..."], "answer": 1, "explanation": "..." },
  "source": {
    "id": "meditations-marcus-aurelius",
    "title": "Meditations",
    "authors": ["Marcus Aurelius"],
    "kind": "book",
    "url": "https://www.gutenberg.org/ebooks/2680",
    "licence": "public-domain",
    "licence_url": "https://www.gutenberg.org/policy/license.html",
    "attribution": "Marcus Aurelius, Meditations (trans. George Long), Project Gutenberg, public domain"
  },
  "credit": "Source: Marcus Aurelius, Meditations (trans. George Long), Project Gutenberg, public domain"
}
''';

Map<String, dynamic> cardJson() =>
    jsonDecode(cardJsonExample) as Map<String, dynamic>;

/// A card JSON with overrides, e.g. `cardJsonWith({'id': 'x--02'})`.
Map<String, dynamic> cardJsonWith(Map<String, dynamic> overrides) => {
  ...cardJson(),
  ...overrides,
};

IdeaCard sampleCard([Map<String, dynamic> overrides = const {}]) =>
    IdeaCard.fromJson(cardJsonWith(overrides));

const healthDisclaimer = 'This is general information, not medical advice.';

IdeaCard healthCard() => sampleCard({
  'id': 'nhs-sleep--01',
  'title': 'Keep a regular wake-up time',
  'topic': 'health',
  'health': true,
  'disclaimer': healthDisclaimer,
  'quote': null,
  'quiz': null,
  'locator': null,
  'credit': 'Source: NHS, Sleep and tiredness, Open Government Licence v3.0',
});

/// A Post JSON (docs/API.md) wrapping [card].
Map<String, dynamic> postJson(
  Map<String, dynamic> card, {
  Map<String, int> reactions = const {},
  int comments = 0,
  int favorites = 0,
  int shares = 0,
  int gifts = 0,
  Map<String, dynamic>? viewer,
  Map<String, dynamic>? reason,
}) => {
  'id': card['id'],
  'published_at': '2026-10-10T09:00:00Z',
  'card': card,
  'stats': {
    'reactions': reactions,
    'comments': comments,
    'favorites': favorites,
    'shares': shares,
    'gifts': gifts,
  },
  'viewer': ?viewer,
  'reason': ?reason,
};

Post samplePost({
  Map<String, dynamic> card = const {},
  Map<String, int> reactions = const {},
  int comments = 0,
  int favorites = 0,
  int shares = 0,
  Map<String, dynamic>? viewer,
  Map<String, dynamic>? reason,
}) => Post.fromJson(
  postJson(
    cardJsonWith(card),
    reactions: reactions,
    comments: comments,
    favorites: favorites,
    shares: shares,
    viewer: viewer,
    reason: reason,
  ),
);

const signedInPrefs = <String, Object>{
  'onboarding.done': true,
  'auth.token': 'tok',
  'auth.user': '{"id":"u1","email":"a@b.com","handle":"ada","display_name":"Ada","bio":"","role":"member","topics":[]}',
};
