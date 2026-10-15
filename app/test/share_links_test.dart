import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/features/post/share.dart';

import 'fake_server.dart';
import 'library_test.dart' show book, card, phone, sourceDetail, sourceId;

void main() {
  test('webLink joins the site base and a path', () {
    expect(
      webLink('/sources/a', base: 'https://iamreborn.app/'),
      'https://iamreborn.app/sources/a',
    );
    expect(webLink('topics/x', base: 'https://x.y'), 'https://x.y/topics/x');
  });

  testWidgets('a book page shares its title, authors and web link, '
      'without counting it as an idea share', (tester) async {
    final server = FakeServer()
      ..on('GET /v1/sources/$sourceId', (_) => sourceDetail([card('m--01')]));
    final sharer = FakeSharer();
    await pumpApp(
      tester,
      server,
      size: phone,
      location: '/sources/$sourceId',
      sharer: sharer,
    );
    await tester.tap(find.byKey(const ValueKey('source-share')));
    await tester.pumpAndSettle();
    expect(
      sharer.shared.single,
      'Meditations by Marcus Aurelius\nhttps://reborn.app/sources/$sourceId',
    );
    expect(server.calls.where((c) => c.method == 'POST'), isEmpty);
  });

  testWidgets('an author page shares the author link', (tester) async {
    final server = FakeServer()
      ..on(
        'GET /v1/authors/Seneca',
        (_) => {
          'name': 'Seneca',
          'sources': [book('a')],
          'cards': [card('x--01')],
          'card_count': 1,
          'video_count': 0,
          'followers': 0,
          'is_following': false,
        },
      );
    final sharer = FakeSharer();
    await pumpApp(
      tester,
      server,
      size: phone,
      location: '/authors/Seneca',
      sharer: sharer,
    );
    await tester.tap(find.byKey(const ValueKey('author-share')));
    await tester.pumpAndSettle();
    expect(
      sharer.shared.single,
      'Seneca on Reborn\nhttps://reborn.app/authors/Seneca',
    );
  });
}
