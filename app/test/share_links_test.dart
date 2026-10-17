import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/features/post/share.dart';

import 'fake_server.dart';
import 'fixtures.dart';
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

  test('a card shares its image post first, else its full-size picture; '
      'in the browser through the API, and never a member card picture', () {
    IdeaCard withMedia(Map<String, dynamic> extra) =>
        IdeaCard.fromJson(cardJsonWith({'id': 'a--01', ...extra}));
    final both = withMedia({
      'post_image': {'url': 'https://m/p.jpg', 'width': 1080, 'height': 1350},
      'image': {'url': 'https://m/c.webp', 'full_url': 'https://m/c.png'},
    });
    expect(cardPicture(both, web: false)!.url.toString(), 'https://m/p.jpg');
    expect(cardPicture(both, web: false)!.mimeType, 'image/jpeg');
    final image = withMedia({
      'image': {'url': 'https://m/c.webp', 'full_url': 'https://m/c.png'},
    });
    final m = cardPicture(image, web: false)!;
    expect(m.url.toString(), 'https://m/c.png');
    expect(m.fileName, 'reborn-a--01.png');
    expect(m.mimeType, 'image/png');
    expect(cardPicture(image, web: true)!.url.path, '/v1/cards/a--01/picture');
    expect(cardPicture(withMedia({}), web: false), isNull);
  });
}
