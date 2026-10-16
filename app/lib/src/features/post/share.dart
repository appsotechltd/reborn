import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import 'post_store.dart';
import 'web_share_stub.dart' if (dart.library.js_interop) 'web_share_web.dart';

/// Opens the platform share sheet (which is how WhatsApp, Instagram,
/// Facebook and the rest are reached on mobile). Returns false when the
/// person dismissed the sheet.
abstract class Sharer {
  Future<bool> share({
    required String text,
    required String subject,
    Rect? origin,
  });

  /// Shares the video file at [url] (saved as [fileName]) with [text].
  Future<bool> shareVideo({
    required Uri url,
    required String fileName,
    required String text,
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
    if (!platformCanShare) {
      throw UnsupportedError('No share sheet here');
    }
    final r = await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        title: subject,
        sharePositionOrigin: origin,
      ),
    );
    // Nothing could be shared: let the caller copy the link instead.
    if (r.status == ShareResultStatus.unavailable) {
      throw UnsupportedError('Share unavailable');
    }
    return r.status != ShareResultStatus.dismissed;
  }

  @override
  Future<bool> shareVideo({
    required Uri url,
    required String fileName,
    required String text,
    Rect? origin,
  }) async {
    final res = await http.get(url);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', url);
    }
    final r = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(res.bodyBytes, mimeType: 'video/mp4', name: fileName),
        ],
        fileNameOverrides: [fileName],
        text: text,
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

/// The web link of any public page from its site [path], e.g.
/// `/sources/meditations`. Segments in [path] must already be encoded.
String webLink(String path, {String base = webBaseUrl}) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$b${path.startsWith('/') ? '' : '/'}$path';
}

/// Opens the share sheet for [text], falling back to copying it (or showing
/// [link] to copy by hand). Returns the channel used, or null when nothing
/// was shared.
Future<String?> _shareOrCopy(
  BuildContext context,
  WidgetRef ref, {
  required String text,
  required String subject,
  required String link,
}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final shared = await ref
        .read(sharerProvider)
        .share(text: text, subject: subject, origin: origin);
    return shared ? 'native' : null;
  } catch (_) {
    // No share sheet here (a desktop browser without Web Share): copy the
    // link instead, and say so.
    try {
      await Clipboard.setData(ClipboardData(text: text));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Link copied — paste it anywhere')),
      );
      return 'copy_link';
    } catch (_) {
      // The clipboard was refused too: show the link to copy by hand. Not
      // counted, since nothing was shared.
      messenger?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: SelectableText('Share this link: $link'),
        ),
      );
      return null;
    }
  }
}

/// Shares any public page that isn't a single idea (a book, author, topic,
/// summary, guide, stash or profile): its [title] and web link at [path],
/// through the share sheet (WhatsApp, Instagram, Facebook, email and the
/// rest), or copies the link. Only idea shares are counted.
Future<void> shareLink(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String path,
}) async {
  final link = webLink(path);
  await _shareOrCopy(
    context,
    ref,
    text: '$title\n$link',
    subject: title,
    link: link,
  );
}

/// A share icon for an app bar or action row that shares [path].
class ShareLinkButton extends ConsumerWidget {
  const ShareLinkButton({
    super.key,
    required this.title,
    required this.path,
    this.tooltip = 'Share',
  });

  final String title;
  final String path;
  final String tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Builder(
    builder: (context) => IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.ios_share),
      onPressed: () => shareLink(context, ref, title: title, path: path),
    ),
  );
}

/// What to share of an idea with a video: its link, or the video itself in
/// the shape that suits where it's going.
enum ShareShape { link, tall, wide }

/// Asks whether to share the link or the video (tall for Status, Reels,
/// Shorts and TikTok; wide for YouTube, Facebook, X and LinkedIn).
Future<ShareShape?> _pickShareShape(BuildContext context, Explainer e) =>
    showModalBottomSheet<ShareShape>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('share-link'),
              leading: const Icon(Icons.link_rounded),
              title: const Text('Share the link'),
              subtitle: const Text('WhatsApp, Facebook, X, email and more'),
              onTap: () => Navigator.pop(context, ShareShape.link),
            ),
            ListTile(
              key: const ValueKey('share-video-tall'),
              leading: const Icon(Icons.stay_current_portrait_rounded),
              title: const Text('Tall video'),
              subtitle: const Text('Status, Reels, Shorts, TikTok'),
              onTap: () => Navigator.pop(context, ShareShape.tall),
            ),
            if (e.landscape != null)
              ListTile(
                key: const ValueKey('share-video-wide'),
                leading: const Icon(Icons.stay_current_landscape_rounded),
                title: const Text('Wide video'),
                subtitle: const Text('YouTube, Facebook, X, LinkedIn'),
                onTap: () => Navigator.pop(context, ShareShape.wide),
              ),
          ],
        ),
      ),
    );

/// Shares the card's video file in [shape], with its link as the text.
Future<String?> _shareVideo(
  BuildContext context,
  WidgetRef ref,
  IdeaCard card,
  ShareShape shape,
) async {
  final e = card.explainer!.cut(wide: shape == ShareShape.wide);
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(const SnackBar(content: Text('Getting the video…')));
  try {
    final shared = await ref
        .read(sharerProvider)
        .shareVideo(
          url: Uri.parse(resolveMediaUrl(e.videoUrl)),
          fileName: 'reborn-${card.id}-${shape.name}.mp4',
          text: postShareText(card),
          origin: origin,
        );
    messenger?.hideCurrentSnackBar();
    return shared ? 'native' : null;
  } catch (_) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't get the video. Try again.")),
    );
    return null;
  }
}

/// Shares [post] through the native share sheet and counts the share
/// (channel `native`). Falls back to copying the link (`copy_link`). An idea
/// with a video first asks whether to share the link or the video, tall or
/// wide.
///
/// [countLocally] false skips the optimistic count, for views that show no
/// stats (the [post] is then only a card).
Future<void> sharePost(
  BuildContext context,
  WidgetRef ref,
  Post post, {
  bool countLocally = true,
}) async {
  final e = post.card.explainer;
  if (e != null && !kIsWeb) {
    final shape = await _pickShareShape(context, e);
    if (shape == null || !context.mounted) return;
    if (shape != ShareShape.link) {
      final channel = await _shareVideo(context, ref, post.card, shape);
      if (channel == null) return;
      if (countLocally) ref.read(postStoreProvider.notifier).countShare(post);
      unawaited(ref.read(repositoryProvider).recordShare(post.id, channel));
      return;
    }
  }
  if (!context.mounted) return;
  final channel = await _shareOrCopy(
    context,
    ref,
    text: postShareText(post.card),
    subject: post.card.title,
    link: postWebLink(post.card.id),
  );
  if (channel == null) return;
  if (countLocally) ref.read(postStoreProvider.notifier).countShare(post);
  unawaited(ref.read(repositoryProvider).recordShare(post.id, channel));
}
