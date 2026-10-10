import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/features/ask/citations.dart';

import 'fixtures.dart';

void main() {
  test('turns cited [card-id] markers into citation segments', () {
    final a = sampleCard();
    final b = healthCard();
    final segments = parseReply(
      'Expect friction [meditations-marcus-aurelius--01]. Sleep matters [nhs-sleep--01][unknown--09].',
      [a, b],
    );
    expect(segments, hasLength(5));
    expect((segments[0] as TextSegment).text, 'Expect friction ');
    expect((segments[1] as CitationSegment).card.id, a.id);
    expect((segments[2] as TextSegment).text, '. Sleep matters ');
    expect((segments[3] as CitationSegment).card.id, b.id);
    // Unknown ids stay as plain text.
    expect((segments[4] as TextSegment).text, '[unknown--09].');
  });

  test('reply without citations is one text segment', () {
    final s = parseReply('No markers here.', const []);
    expect(s.single, isA<TextSegment>());
  });
}
