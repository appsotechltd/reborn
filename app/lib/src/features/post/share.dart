import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import 'post_store.dart';

/// Opens the platform share sheet (which is how WhatsApp, Instagram,
/// Facebook and the rest are reached on mobile). Returns false when the
/// person dismissed the sheet.
abstract class Sharer {
  Future<bool> share({
    required String text,
    required String subject,
    Rect? origin,
  });
}

class NativeSharer implements Sharer {
  const NativeSharer();

  @override
  Future<bool> share({
    required String text,
    required String subject,
    Rect? origin,
  }) async {
    final r = await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        title: subject,
        sharePositionOrigin: origin,
      ),
    );
    return r.status != ShareResultStatus.dismissed;
  }
}

final sharerProvider = Provider<Sharer>((ref) => const NativeSharer());

/// What gets shared: the title and the post's canonical web link.
String postShareText(IdeaCard card, {String base = webBaseUrl}) =>
    '${card.title}\n${postWebLink(card.id, base: base)}';

/// Shares [post] through the native share sheet and counts the share
/// (channel `native`). Falls back to copying the link (`copy_link`).
///
/// [countLocally] false skips the optimistic count, for views that show no
/// stats (the [post] is then only a card).
Future<void> sharePost(
  BuildContext context,
  WidgetRef ref,
  Post post, {
  bool countLocally = true,
}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final text = postShareText(post.card);
  var channel = 'native';
  bool shared;
  try {
    shared = await ref
        .read(sharerProvider)
        .share(text: text, subject: post.card.title, origin: origin);
  } catch (_) {
    channel = 'copy_link';
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied — paste it anywhere')),
      );
    }
    shared = true;
  }
  if (!shared) return;
  if (countLocally) ref.read(postStoreProvider.notifier).countShare(post);
  unawaited(ref.read(repositoryProvider).recordShare(post.id, channel));
}
