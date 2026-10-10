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
