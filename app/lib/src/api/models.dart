// Hand-written models matching docs/API.md. Field names in JSON are snake_case
// exactly as the API sends them.

List<String> _stringList(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : const <String>[];

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

class Quiz {
  const Quiz({
    required this.question,
    required this.options,
    required this.answer,
    this.explanation,
  });

  final String question;
  final List<String> options;
  final int answer;
  final String? explanation;

  factory Quiz.fromJson(Map<String, dynamic> json) => Quiz(
    question: json['question'] as String? ?? '',
    options: _stringList(json['options']),
    answer: (json['answer'] as num?)?.toInt() ?? 0,
    explanation: json['explanation'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'question': question,
    'options': options,
    'answer': answer,
    if (explanation != null) 'explanation': explanation,
  };
}

class Source {
  const Source({
    required this.id,
    required this.title,
    required this.authors,
    required this.kind,
    required this.url,
    required this.licence,
    this.licenceUrl,
    required this.attribution,
  });

  final String id;
  final String title;
  final List<String> authors;
  final String kind;
  final String url;
  final String licence;
  final String? licenceUrl;
  final String attribution;

  factory Source.fromJson(Map<String, dynamic> json) => Source(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    authors: _stringList(json['authors']),
    kind: json['kind'] as String? ?? '',
    url: json['url'] as String? ?? '',
    licence: json['licence'] as String? ?? '',
    licenceUrl: json['licence_url'] as String?,
    attribution: json['attribution'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'authors': authors,
    'kind': kind,
    'url': url,
    'licence': licence,
    'licence_url': licenceUrl,
    'attribution': attribution,
  };
}

/// An explainer video rendered for a card (see content/explainers).
class Explainer {
  const Explainer({
    required this.kind,
    required this.videoUrl,
    required this.posterUrl,
    this.captionsUrl,
    this.durationS = 0,
    this.width = 720,
    this.height = 1280,
    this.narrated = false,
  });

  /// `animated` today, `film` for realistic films later.
  final String kind;

  /// Absolute, or a path relative to the API base URL.
  final String videoUrl;
  final String posterUrl;
  final String? captionsUrl;
  final double durationS;
  final int width;
  final int height;
  final bool narrated;

  double get aspectRatio => height == 0 ? 9 / 16 : width / height;

  factory Explainer.fromJson(Map<String, dynamic> json) => Explainer(
    kind: json['kind'] as String? ?? 'animated',
    videoUrl: json['video_url'] as String? ?? '',
    posterUrl: json['poster_url'] as String? ?? '',
    captionsUrl: json['captions_url'] as String?,
    durationS: (json['duration_s'] as num?)?.toDouble() ?? 0,
    width: (json['width'] as num?)?.toInt() ?? 720,
    height: (json['height'] as num?)?.toInt() ?? 1280,
    narrated: json['narrated'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'video_url': videoUrl,
    'poster_url': posterUrl,
    'captions_url': captionsUrl,
    'duration_s': durationS,
    'width': width,
    'height': height,
    'narrated': narrated,
  };
}

/// A card's voiced recording (Listen mode). It reads the title, body,
/// "Apply it." and the apply-it line, the health note when there is one, and
/// "From `source`, by `authors`."
class CardAudio {
  const CardAudio({
    required this.url,
    this.durationS = 0,
    this.voice = '',
    this.voiceName = '',
  });

  /// Absolute, or a path relative to the API base URL (like explainers).
  final String url;
  final double durationS;

  /// The voice id, e.g. `bm_george`.
  final String voice;

  /// The voice's display name, e.g. `George`.
  final String voiceName;

  Duration get duration => Duration(milliseconds: (durationS * 1000).round());

  factory CardAudio.fromJson(Map<String, dynamic> json) => CardAudio(
    url: json['url'] as String? ?? '',
    durationS: (json['duration_s'] as num?)?.toDouble() ?? 0,
    voice: json['voice'] as String? ?? '',
    voiceName: json['voice_name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'duration_s': durationS,
    'voice': voice,
    'voice_name': voiceName,
  };
}

/// The card's picture (content/images): a 3:2 illustration, 3D render or
/// chart. Absent on text-only cards.
class CardImage {
  const CardImage({
    required this.url,
    this.fullUrl,
    this.type = '',
    this.caption = '',
    this.basis,
    this.source,
    this.credit,
  });

  /// Absolute, or a path relative to the API base URL (like explainers).
  final String url;
  final String? fullUrl;

  /// `illustration`, `3d` or `chart`.
  final String type;
  final String caption;

  /// Charts only: `data` when drawn from real figures, `illustration` when it
  /// pictures a concept.
  final String? basis;
  final String? source;
  final String? credit;

  /// The badge on the picture.
  String get typeLabel => switch (type) {
    'illustration' => 'Illustration',
    '3d' => '3D',
    'chart' => 'Chart',
    _ => 'Image',
  };

  /// True when a chart only pictures an idea rather than measured figures.
  bool get isConceptChart => type == 'chart' && basis == 'illustration';

  /// The line under the credit.
  String get captionLine =>
      'Image: $caption${isConceptChart ? ' · A concept, not measured data' : ''}';

  factory CardImage.fromJson(Map<String, dynamic> json) => CardImage(
    url: json['url'] as String? ?? '',
    fullUrl: json['full_url'] as String?,
    type: json['type'] as String? ?? '',
    caption: json['caption'] as String? ?? '',
    basis: json['basis'] as String?,
    source: json['source'] as String?,
    credit: json['credit'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    if (fullUrl != null) 'full_url': fullUrl,
    'type': type,
    'caption': caption,
    if (basis != null) 'basis': basis,
    if (source != null) 'source': source,
    if (credit != null) 'credit': credit,
  };
}

/// A library card's designed 4:5 picture post (title, category and book
/// already set in it), shown as an image post in the feed. Absent until one
/// is made.
class PostImage {
  const PostImage({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.alt = '',
  });

  /// Absolute, or a path relative to the API base URL (like explainers).
  final String url;
  final int width;
  final int height;

  /// A short description of the scene, for screen readers.
  final String alt;

  /// Width over height; 4:5 when the size is unknown.
  double get aspectRatio => width > 0 && height > 0 ? width / height : 4 / 5;

  factory PostImage.fromJson(Map<String, dynamic> json) => PostImage(
    url: json['url'] as String? ?? '',
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
    alt: json['alt'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'width': width,
    'height': height,
    'alt': alt,
  };
}

/// One illustration of a member card's illustrated video.
class VideoScene {
  const VideoScene({required this.url, this.width = 0, this.height = 0});

  /// Absolute, or a path relative to the API base URL (like explainers).
  final String url;
  final int width;
  final int height;

  factory VideoScene.fromJson(Map<String, dynamic> json) => VideoScene(
    url: json['url'] as String? ?? '',
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'width': width,
    'height': height,
  };
}

/// A member card's illustrated video: a few illustrations shown in turn over
/// the card's narration (no captions). The apps animate it themselves.
class CardVideo {
  const CardVideo({
    this.kind = 'illustrated',
    this.scenes = const [],
    required this.audioUrl,
    this.voice = '',
    this.durationS = 0,
  });

  final String kind;
  final List<VideoScene> scenes;
  final String audioUrl;
  final String voice;
  final double durationS;

  Duration get duration => Duration(milliseconds: (durationS * 1000).round());

  factory CardVideo.fromJson(Map<String, dynamic> json) => CardVideo(
    kind: json['kind'] as String? ?? 'illustrated',
    scenes: (json['scenes'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VideoScene.fromJson)
        .where((s) => s.url.isNotEmpty)
        .toList(),
    audioUrl: json['audio_url'] as String? ?? '',
    voice: json['voice'] as String? ?? '',
    durationS: (json['duration_s'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'scenes': scenes.map((s) => s.toJson()).toList(),
    'audio_url': audioUrl,
    'voice': voice,
    'duration_s': durationS,
  };
}

/// One of a member's own categories for the cards they write.
class CardCategory {
  const CardCategory({required this.id, required this.name, this.cardCount});
  final String id;
  final String name;

  /// Present in category lists, absent on a card.
  final int? cardCount;

  factory CardCategory.fromJson(Map<String, dynamic> json) => CardCategory(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    cardCount: (json['card_count'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (cardCount != null) 'card_count': cardCount,
  };
}

/// The All / Videos / Images switch: every card, only those with a video
/// (an explainer, or a member card's illustrated video), or only those with
/// a picture.
enum MediaFilter {
  all,
  videos,
  images;

  /// `media` for `GET /v1/timeline`; null for [all].
  String? get query => switch (this) {
    MediaFilter.all => null,
    MediaFilter.videos => 'video',
    MediaFilter.images => 'image',
  };

  bool matches(IdeaCard card) => switch (this) {
    MediaFilter.all => true,
    MediaFilter.videos => card.explainer != null || card.video != null,
    MediaFilter.images => card.image != null || card.postImage != null,
  };
}

/// An idea card. Named `IdeaCard` to avoid clashing with Material's `Card`.
class IdeaCard {
  const IdeaCard({
    required this.id,
    required this.title,
    required this.body,
    this.quote,
    required this.applyIt,
    required this.topic,
    this.tags = const [],
    this.locator,
    this.health = false,
    this.disclaimer,
    this.quiz,
    required this.source,
    required this.credit,
    this.explainer,
    this.audio,
    this.image,
    this.author,
    this.category,
    this.visibility,
    this.createdAt,
    this.video,
    this.postImage,
  });

  final String id;
  final String title;
  final String body;
  final String? quote;
  final String applyIt;
  final String topic;
  final List<String> tags;
  final String? locator;
  final bool health;
  final String? disclaimer;
  final Quiz? quiz;
  final Source source;
  final String credit;

  /// The card's explainer video, when one is rendered.
  final Explainer? explainer;

  /// The card's voiced recording, absent until one is made.
  final CardAudio? audio;

  /// The card's picture, absent on text-only cards.
  final CardImage? image;

  /// Who wrote it, on cards members write (absent on library cards).
  final UserSummary? author;

  /// The writer's own category for it, when they filed it under one.
  final CardCategory? category;

  /// Member cards: `everyone`, `followers`, `subscribers`, `private`, or
  /// `hidden` when reports or a moderator took it down.
  final String? visibility;
  final DateTime? createdAt;

  /// A member card's illustrated video, when one is made.
  final CardVideo? video;

  /// A library card's designed picture post, when one is made.
  final PostImage? postImage;

  /// True for cards members write.
  bool get isMemberCard => author != null;

  factory IdeaCard.fromJson(Map<String, dynamic> json) => IdeaCard(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    quote: json['quote'] as String?,
    applyIt: json['apply_it'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    tags: _stringList(json['tags']),
    locator: json['locator'] as String?,
    health: json['health'] as bool? ?? false,
    disclaimer: json['disclaimer'] as String?,
    quiz: json['quiz'] is Map<String, dynamic>
        ? Quiz.fromJson(json['quiz'] as Map<String, dynamic>)
        : null,
    source: Source.fromJson(
      (json['source'] as Map<String, dynamic>?) ?? const {},
    ),
    credit: json['credit'] as String? ?? '',
    explainer: json['explainer'] is Map<String, dynamic>
        ? Explainer.fromJson(json['explainer'] as Map<String, dynamic>)
        : null,
    audio:
        json['audio'] is Map<String, dynamic> &&
            ((json['audio'] as Map<String, dynamic>)['url'] as String? ?? '')
                .isNotEmpty
        ? CardAudio.fromJson(json['audio'] as Map<String, dynamic>)
        : null,
    image:
        json['image'] is Map<String, dynamic> &&
            ((json['image'] as Map<String, dynamic>)['url'] as String? ?? '')
                .isNotEmpty
        ? CardImage.fromJson(json['image'] as Map<String, dynamic>)
        : null,
    author: json['author'] is Map<String, dynamic>
        ? UserSummary.fromJson(json['author'] as Map<String, dynamic>)
        : null,
    category: json['category'] is Map<String, dynamic>
        ? CardCategory.fromJson(json['category'] as Map<String, dynamic>)
        : null,
    visibility: json['visibility'] as String?,
    createdAt: _date(json['created_at']),
    video:
        json['video'] is Map<String, dynamic> &&
            ((json['video'] as Map<String, dynamic>)['audio_url'] as String? ??
                    '')
                .isNotEmpty
        ? CardVideo.fromJson(json['video'] as Map<String, dynamic>)
        : null,
    postImage:
        json['post_image'] is Map<String, dynamic> &&
            ((json['post_image'] as Map<String, dynamic>)['url'] as String? ??
                    '')
                .isNotEmpty
        ? PostImage.fromJson(json['post_image'] as Map<String, dynamic>)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'quote': quote,
    'apply_it': applyIt,
    'topic': topic,
    'tags': tags,
    'locator': locator,
    'health': health,
    'disclaimer': disclaimer,
    'quiz': quiz?.toJson(),
    'source': source.toJson(),
    'credit': credit,
    if (explainer != null) 'explainer': explainer!.toJson(),
    if (audio != null) 'audio': audio!.toJson(),
    if (image != null) 'image': image!.toJson(),
    if (author != null) 'author': author!.toJson(),
    if (category != null) 'category': category!.toJson(),
    if (visibility != null) 'visibility': visibility,
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    if (video != null) 'video': video!.toJson(),
    if (postImage != null) 'post_image': postImage!.toJson(),
  };

  /// Text read aloud by the device voice when the card has no [audio]: the
  /// same script as the recording (title, body, apply it, the health note
  /// when there is one, and where it comes from).
  String get spokenText {
    final b = StringBuffer('$title.\n\n$body');
    if (applyIt.isNotEmpty || author == null) b.write('\n\nApply it. $applyIt');
    final note = disclaimer?.trim() ?? '';
    if (note.isNotEmpty) b.write('\n\n$note');
    if (author != null) {
      if (author!.displayName.isNotEmpty) {
        b.write('\n\nBy ${author!.displayName}.');
      }
    } else if (source.title.isNotEmpty) {
      b.write('\n\nFrom ${source.title}');
      if (source.authors.isNotEmpty) {
        b.write(', by ${_andList(source.authors)}');
      }
      b.write('.');
    }
    return b.toString();
  }
}

/// "A", "A and B", "A, B and C".
String _andList(List<String> items) {
  if (items.length <= 1) return items.join();
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

List<IdeaCard> parseCards(Object? v) => v is List
    ? v.whereType<Map<String, dynamic>>().map(IdeaCard.fromJson).toList()
    : <IdeaCard>[];

class Topic {
  const Topic({required this.slug, required this.name, this.cardCount = 0});
  final String slug;
  final String name;
  final int cardCount;

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
    slug: json['slug'] as String? ?? '',
    name: json['name'] as String? ?? '',
    cardCount: (json['card_count'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'name': name,
    'card_count': cardCount,
  };
}

class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.handle = '',
    this.bio = '',
    this.topics = const [],
    this.timezone = '',
    this.dailyGoal = 3,
    this.notify = const {},
    this.referralCode = '',
    this.premium = false,
    this.premiumUntil,
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final String handle;
  final String bio;
  final List<String> topics;

  /// IANA name, e.g. "Europe/London".
  final String timezone;
  final int dailyGoal;

  /// Push settings by kind: `daily`, `replies`, `follows`, `circles`.
  final Map<String, bool> notify;
  final String referralCode;
  final bool premium;
  final DateTime? premiumUntil;

  bool get isModerator => role == 'moderator';

  /// Missing settings default to on.
  bool notifies(String kind) => notify[kind] ?? true;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    handle: json['handle'] as String? ?? '',
    bio: json['bio'] as String? ?? '',
    topics: _stringList(json['topics']),
    timezone: json['timezone'] as String? ?? '',
    dailyGoal: (json['daily_goal'] as num?)?.toInt() ?? 3,
    notify: json['notify'] is Map
        ? {
            for (final e in (json['notify'] as Map).entries)
              e.key.toString(): e.value == true,
          }
        : const {},
    referralCode: json['referral_code'] as String? ?? '',
    premium: json['premium'] as bool? ?? false,
    premiumUntil: _date(json['premium_until']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'handle': handle,
    'display_name': displayName,
    'bio': bio,
    'role': role,
    'topics': topics,
    'timezone': timezone,
    'daily_goal': dailyGoal,
    'notify': notify,
    'referral_code': referralCode,
    'premium': premium,
    'premium_until': premiumUntil?.toUtc().toIso8601String(),
  };
}

class AuthResult {
  const AuthResult({required this.token, required this.user});
  final String token;
  final User user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
    token: json['token'] as String,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );
}

class Stash {
  const Stash({
    required this.id,
    required this.name,
    this.description = '',
    this.cardCount = 0,
    this.isPublic = false,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final int cardCount;

  /// Public stashes show on the owner's profile.
  final bool isPublic;
  final DateTime? createdAt;

  factory Stash.fromJson(Map<String, dynamic> json) => Stash(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    cardCount: (json['card_count'] as num?)?.toInt() ?? 0,
    isPublic: json['is_public'] as bool? ?? false,
    createdAt: _date(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'card_count': cardCount,
    'is_public': isPublic,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };
}

class StashDetail {
  const StashDetail({required this.stash, required this.cards});
  final Stash stash;
  final List<IdeaCard> cards;

  factory StashDetail.fromJson(Map<String, dynamic> json) => StashDetail(
    stash: Stash.fromJson(json['stash'] as Map<String, dynamic>),
    cards: parseCards(json['cards']),
  );

  Map<String, dynamic> toJson() => {
    'stash': stash.toJson(),
    'cards': cards.map((c) => c.toJson()).toList(),
  };
}

class FeedPage {
  const FeedPage({required this.cards, this.nextCursor});
  final List<IdeaCard> cards;
  final String? nextCursor;

  factory FeedPage.fromJson(Map<String, dynamic> json) => FeedPage(
    cards: parseCards(json['cards']),
    nextCursor: json['next_cursor'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'cards': cards.map((c) => c.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}

class DailyIdea {
  const DailyIdea({required this.date, required this.card});
  final String date;
  final IdeaCard card;

  factory DailyIdea.fromJson(Map<String, dynamic> json) => DailyIdea(
    date: json['date'] as String? ?? '',
    card: IdeaCard.fromJson(json['card'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {'date': date, 'card': card.toJson()};
}

class SourceDetail {
  const SourceDetail({
    required this.source,
    required this.cards,
    this.follow = const FollowState(),
    this.summaryId,
  });
  final Source source;
  final List<IdeaCard> cards;
  final FollowState follow;

  /// The book's summary post, when it has one.
  final String? summaryId;

  factory SourceDetail.fromJson(Map<String, dynamic> json) => SourceDetail(
    source: Source.fromJson(json['source'] as Map<String, dynamic>),
    cards: parseCards(json['cards']),
    follow: json['follow'] is Map<String, dynamic>
        ? FollowState.fromJson(json['follow'] as Map<String, dynamic>)
        : const FollowState(),
    summaryId: json['summary_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'source': source.toJson(),
    'cards': cards.map((c) => c.toJson()).toList(),
    'follow': follow.toJson(),
    'summary_id': summaryId,
  };
}

class ReviewItem {
  const ReviewItem({
    required this.card,
    this.dueAt,
    this.reps = 0,
    this.intervalDays = 0,
  });
  final IdeaCard card;
  final DateTime? dueAt;
  final int reps;
  final num intervalDays;

  factory ReviewItem.fromJson(Map<String, dynamic> json) => ReviewItem(
    card: IdeaCard.fromJson(json['card'] as Map<String, dynamic>),
    dueAt: _date(json['due_at']),
    reps: (json['reps'] as num?)?.toInt() ?? 0,
    intervalDays: (json['interval_days'] as num?) ?? 0,
  );
}

class ReviewDue {
  const ReviewDue({required this.items, required this.dueCount});
  final List<ReviewItem> items;
  final int dueCount;

  factory ReviewDue.fromJson(Map<String, dynamic> json) => ReviewDue(
    items: (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReviewItem.fromJson)
        .toList(),
    dueCount: (json['due_count'] as num?)?.toInt() ?? 0,
  );
}

enum Grade { again, hard, good, easy }

class ReviewResult {
  const ReviewResult({
    this.dueAt,
    required this.intervalDays,
    required this.reps,
  });
  final DateTime? dueAt;
  final num intervalDays;
  final int reps;

  factory ReviewResult.fromJson(Map<String, dynamic> json) => ReviewResult(
    dueAt: _date(json['due_at']),
    intervalDays: (json['interval_days'] as num?) ?? 0,
    reps: (json['reps'] as num?)?.toInt() ?? 0,
  );
}

class ContributionSource {
  const ContributionSource({
    required this.title,
    required this.authors,
    required this.url,
    required this.kind,
  });
  final String title;
  final List<String> authors;
  final String url;
  final String kind;

  factory ContributionSource.fromJson(Map<String, dynamic> json) =>
      ContributionSource(
        title: json['title'] as String? ?? '',
        authors: _stringList(json['authors']),
        url: json['url'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'authors': authors,
    'url': url,
    'kind': kind,
  };
}

/// Body of POST /v1/contributions.
class ContributionDraft {
  const ContributionDraft({
    required this.source,
    required this.topic,
    required this.title,
    required this.body,
    required this.applyIt,
    this.tags = const [],
    this.quiz,
  });
  final ContributionSource source;
  final String topic;
  final String title;
  final String body;
  final String applyIt;
  final List<String> tags;
  final Quiz? quiz;

  Map<String, dynamic> toJson() => {
    'source': source.toJson(),
    'topic': topic,
    'title': title,
    'body': body,
    'apply_it': applyIt,
    if (tags.isNotEmpty) 'tags': tags,
    if (quiz != null) 'quiz': quiz!.toJson(),
  };
}

class Contribution {
  const Contribution({
    required this.id,
    required this.status,
    required this.source,
    required this.topic,
    required this.title,
    required this.body,
    required this.applyIt,
    this.tags = const [],
    this.quiz,
    this.moderatorNote,
    this.cardId,
    this.createdAt,
  });

  final String id;
  final String status;
  final ContributionSource source;
  final String topic;
  final String title;
  final String body;
  final String applyIt;
  final List<String> tags;
  final Quiz? quiz;
  final String? moderatorNote;
  final String? cardId;
  final DateTime? createdAt;

  factory Contribution.fromJson(Map<String, dynamic> json) => Contribution(
    id: json['id'] as String? ?? '',
    status: json['status'] as String? ?? 'pending',
    source: ContributionSource.fromJson(
      (json['source'] as Map<String, dynamic>?) ?? const {},
    ),
    topic: json['topic'] as String? ?? '',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    applyIt: json['apply_it'] as String? ?? '',
    tags: _stringList(json['tags']),
    quiz: json['quiz'] is Map<String, dynamic>
        ? Quiz.fromJson(json['quiz'] as Map<String, dynamic>)
        : null,
    moderatorNote: json['moderator_note'] as String?,
    cardId: json['card_id'] as String?,
    createdAt: _date(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'source': source.toJson(),
    'topic': topic,
    'title': title,
    'body': body,
    'apply_it': applyIt,
    'tags': tags,
    'quiz': quiz?.toJson(),
    'moderator_note': moderatorNote,
    'card_id': cardId,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };
}

class ChatMessage {
  const ChatMessage({required this.role, required this.content});
  final String role; // "user" | "assistant"
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] as String? ?? 'user',
    content: json['content'] as String? ?? '',
  );
}

class ChatReply {
  const ChatReply({required this.reply, required this.citations});
  final String reply;
  final List<IdeaCard> citations;

  factory ChatReply.fromJson(Map<String, dynamic> json) => ChatReply(
    reply: json['reply'] as String? ?? '',
    citations: parseCards(json['citations']),
  );
}

/// Counts words the way the contribution form and backend expect: runs of
/// non-whitespace.
int wordCount(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

// ---------------------------------------------------------------------------
// Social: posts, profiles, follows, comments and gifts.

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// The five reactions, in display order.
enum Reaction {
  like('Like', '👍'),
  love('Love', '❤️'),
  insightful('Insightful', '💡'),
  inspiring('Inspiring', '✨'),
  helpful('Helpful', '🙏');

  const Reaction(this.label, this.emoji);
  final String label;
  final String emoji;

  static Reaction? fromName(Object? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

class PostStats {
  const PostStats({
    this.reactions = const {},
    this.comments = 0,
    this.favorites = 0,
    this.shares = 0,
    this.gifts = 0,
  });

  final Map<String, int> reactions;
  final int comments;
  final int favorites;
  final int shares;
  final int gifts;

  int get totalReactions => reactions.values.fold(0, (a, b) => a + b);

  factory PostStats.fromJson(Map<String, dynamic> json) => PostStats(
    reactions: json['reactions'] is Map
        ? {
            for (final e in (json['reactions'] as Map).entries)
              e.key.toString(): _int(e.value),
          }
        : const {},
    comments: _int(json['comments']),
    favorites: _int(json['favorites']),
    shares: _int(json['shares']),
    gifts: _int(json['gifts']),
  );

  Map<String, dynamic> toJson() => {
    'reactions': reactions,
    'comments': comments,
    'favorites': favorites,
    'shares': shares,
    'gifts': gifts,
  };

  PostStats copyWith({
    Map<String, int>? reactions,
    int? comments,
    int? favorites,
    int? shares,
    int? gifts,
  }) => PostStats(
    reactions: reactions ?? this.reactions,
    comments: comments ?? this.comments,
    favorites: favorites ?? this.favorites,
    shares: shares ?? this.shares,
    gifts: gifts ?? this.gifts,
  );
}

/// The signed-in user's own state on a post.
class PostViewer {
  const PostViewer({this.reaction, this.favorited = false, this.seen = false});
  final Reaction? reaction;
  final bool favorited;
  final bool seen;

  factory PostViewer.fromJson(Map<String, dynamic> json) => PostViewer(
    reaction: Reaction.fromName(json['reaction']),
    favorited: json['favorited'] as bool? ?? false,
    seen: json['seen'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'reaction': reaction?.name,
    'favorited': favorited,
    'seen': seen,
  };
}

/// Why a post is in the timeline.
class PostReason {
  const PostReason({required this.kind, this.label = ''});

  /// `source`, `author`, `writer` (a member you follow wrote it),
  /// `favorite`, `topic` or `new`.
  final String kind;
  final String label;

  factory PostReason.fromJson(Map<String, dynamic> json) => PostReason(
    kind: json['kind'] as String? ?? '',
    label: json['label'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'kind': kind, 'label': label};

  /// The small line shown above a timeline post.
  String get text => switch (kind) {
    'source' => 'From $label',
    'author' => 'Because you follow $label',
    'writer' => 'From $label, who you follow',
    'favorite' => '$label favourited this',
    'topic' => 'In $label, one of your topics',
    _ => 'New on Reborn',
  };
}

/// Every published card is a post. The timeline also carries summary posts
/// (a whole book or topic, read part by part): those have [summary] set and
/// a stand-in [card] made from it, and are never reacted to, marked seen or
/// played in Listen mode as a card.
class Post {
  const Post({
    required this.id,
    required this.card,
    this.publishedAt,
    this.stats = const PostStats(),
    this.viewer,
    this.reason,
    this.summary,
  });

  /// A summary post in the timeline.
  factory Post.fromSummary(Summary s) =>
      Post(id: 'summary:${s.id}', card: s.standInCard, summary: s);

  /// Set on summary posts only.
  final Summary? summary;

  bool get isSummary => summary != null;

  final String id;
  final IdeaCard card;
  final DateTime? publishedAt;
  final PostStats stats;

  /// Present only when signed in.
  final PostViewer? viewer;

  /// Present only in the timeline.
  final PostReason? reason;

  /// A post for a card known only from the library (e.g. offline).
  factory Post.fromCard(IdeaCard card) => Post(id: card.id, card: card);

  factory Post.fromJson(Map<String, dynamic> json) {
    if (json['kind'] == 'summary' && json['summary'] is Map<String, dynamic>) {
      return Post.fromSummary(
        Summary.fromJson(json['summary'] as Map<String, dynamic>),
      );
    }
    final card = IdeaCard.fromJson(json['card'] as Map<String, dynamic>);
    return Post(
      id: json['id'] as String? ?? card.id,
      card: card,
      publishedAt: _date(json['published_at']),
      stats: json['stats'] is Map<String, dynamic>
          ? PostStats.fromJson(json['stats'] as Map<String, dynamic>)
          : const PostStats(),
      viewer: json['viewer'] is Map<String, dynamic>
          ? PostViewer.fromJson(json['viewer'] as Map<String, dynamic>)
          : null,
      reason: json['reason'] is Map<String, dynamic>
          ? PostReason.fromJson(json['reason'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => summary != null
      ? {'id': id, 'kind': 'summary', 'summary': summary!.toJson()}
      : {
          'id': id,
          'published_at': publishedAt?.toUtc().toIso8601String(),
          'card': card.toJson(),
          'stats': stats.toJson(),
          if (viewer != null) 'viewer': viewer!.toJson(),
          if (reason != null) 'reason': reason!.toJson(),
        };

  Reaction? get myReaction => viewer?.reaction;
  bool get favorited => viewer?.favorited ?? false;

  Post copyWith({PostStats? stats, PostViewer? viewer}) => Post(
    id: id,
    card: card,
    publishedAt: publishedAt,
    stats: stats ?? this.stats,
    viewer: viewer ?? this.viewer,
    reason: reason,
    summary: summary,
  );

  /// Sets (or with null clears) the viewer's reaction, adjusting counts.
  Post withReaction(Reaction? next) {
    final prev = myReaction;
    final counts = Map<String, int>.of(stats.reactions);
    if (prev != null) {
      final n = (counts[prev.name] ?? 0) - 1;
      if (n > 0) {
        counts[prev.name] = n;
      } else {
        counts.remove(prev.name);
      }
    }
    if (next != null) counts[next.name] = (counts[next.name] ?? 0) + 1;
    final v = viewer ?? const PostViewer();
    return copyWith(
      stats: stats.copyWith(reactions: counts),
      viewer: PostViewer(reaction: next, favorited: v.favorited, seen: v.seen),
    );
  }

  Post withFavorite(bool on) {
    if (on == favorited) return this;
    final v = viewer ?? const PostViewer();
    return copyWith(
      stats: stats.copyWith(
        favorites: (stats.favorites + (on ? 1 : -1)).clamp(0, 1 << 30),
      ),
      viewer: PostViewer(reaction: v.reaction, favorited: on, seen: v.seen),
    );
  }
}

/// A page of posts (`{"posts":[Post],"next_cursor"}`).
/// Where the reader is in a summary; [position] is the zero-based part.
class SummaryProgress {
  const SummaryProgress({
    this.started = false,
    this.position = 0,
    this.finished = false,
  });
  final bool started;
  final int position;
  final bool finished;

  factory SummaryProgress.fromJson(Map<String, dynamic> json) =>
      SummaryProgress(
        started: json['started'] as bool? ?? false,
        position: (json['position'] as num?)?.toInt() ?? 0,
        finished: json['finished'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'started': started,
    'position': position,
    'finished': finished,
  };

  /// Where "Continue" opens: the saved part, or the start once finished.
  int resumeIndex(int parts) {
    if (!started || finished || parts <= 0) return 0;
    return position.clamp(0, parts - 1);
  }
}

/// A full summary post: a whole book or topic read part by part, each part
/// a card. Book summaries cover a public-domain or openly licensed book in
/// full ([coverage] "full") or an in-copyright book's key ideas in our own
/// words ("key-ideas"); topic summaries ("topic") draw from several books.
class Summary {
  const Summary({
    required this.id,
    required this.kind,
    required this.title,
    this.description = '',
    required this.topic,
    this.topicName = '',
    this.coverage = 'full',
    this.source,
    this.authors = const [],
    this.sourceCount = 0,
    this.partCount = 0,
    this.minutes = 0,
    this.viewer,
    this.cover,
  });

  final String id;
  final String kind;
  final String title;
  final String description;
  final String topic;
  final String topicName;
  final String coverage;

  /// The book, for book summaries.
  final Source? source;
  final List<String> authors;
  final int sourceCount;
  final int partCount;
  final int minutes;

  /// Present only when signed in.
  final SummaryProgress? viewer;

  /// A guide's cover picture, when it has one.
  final CardImage? cover;

  bool get isBook => kind == 'book';

  factory Summary.fromJson(Map<String, dynamic> json) => Summary(
    id: json['id'] as String? ?? '',
    kind: json['kind'] as String? ?? 'book',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    topicName: json['topic_name'] as String? ?? '',
    coverage: json['coverage'] as String? ?? 'full',
    source: json['source'] is Map<String, dynamic>
        ? Source.fromJson(json['source'] as Map<String, dynamic>)
        : null,
    authors: _stringList(json['authors']),
    sourceCount: (json['source_count'] as num?)?.toInt() ?? 0,
    partCount: (json['part_count'] as num?)?.toInt() ?? 0,
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    viewer: json['viewer'] is Map<String, dynamic>
        ? SummaryProgress.fromJson(json['viewer'] as Map<String, dynamic>)
        : null,
    cover: json['cover'] is Map<String, dynamic>
        ? CardImage.fromJson(json['cover'] as Map<String, dynamic>)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'description': description,
    'topic': topic,
    'topic_name': topicName,
    'coverage': coverage,
    if (source != null) 'source': source!.toJson(),
    'authors': authors,
    'source_count': sourceCount,
    'part_count': partCount,
    'minutes': minutes,
    if (viewer != null) 'viewer': viewer!.toJson(),
    if (cover != null) 'cover': cover!.toJson(),
  };

  /// The label above the title.
  String get coverageLabel => switch (coverage) {
    'key-ideas' => 'Key ideas summary',
    'guide' => 'Complete guide',
    'topic' => 'Topic summary',
    _ => 'Full summary',
  };

  /// "by Robert Greene", or "From 5 sources, including Seneca, NHS and more".
  String get byline {
    String names(List<String> xs) => xs.length <= 1
        ? (xs.isEmpty ? '' : xs.first)
        : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
    if (isBook) return authors.isEmpty ? '' : 'by ${names(authors)}';
    final from = 'From $sourceCount ${sourceCount == 1 ? 'source' : 'sources'}';
    if (authors.isEmpty) return from;
    final shown = authors.take(2).toList();
    return '$from, including ${names(authors.length > 2 ? [...shown, 'more'] : shown)}';
  }

  /// "30 parts · 18 min".
  String get meta =>
      '$partCount ${partCount == 1 ? 'part' : 'parts'} · $minutes min';

  /// Stands in for a card where the timeline expects one.
  IdeaCard get standInCard => IdeaCard(
    id: 'summary:$id',
    title: title,
    body: description,
    applyIt: '',
    topic: topic,
    source:
        source ??
        Source(
          id: '',
          title: title,
          authors: authors,
          kind: 'summary',
          url: '',
          licence: '',
          attribution: '',
        ),
    credit: '',
  );

  Summary withViewer(SummaryProgress? p) => Summary(
    id: id,
    kind: kind,
    title: title,
    description: description,
    topic: topic,
    topicName: topicName,
    coverage: coverage,
    source: source,
    authors: authors,
    sourceCount: sourceCount,
    partCount: partCount,
    minutes: minutes,
    viewer: p,
    cover: cover,
  );
}

/// GET /v1/summaries/{id}: the summary and its parts in reading order.
class SummaryDetail {
  const SummaryDetail({required this.summary, required this.parts});
  final Summary summary;
  final List<IdeaCard> parts;

  factory SummaryDetail.fromJson(Map<String, dynamic> json) => SummaryDetail(
    summary: Summary.fromJson(json),
    parts: parseCards(json['parts']),
  );

  Map<String, dynamic> toJson() => {
    ...summary.toJson(),
    'parts': parts.map((c) => c.toJson()).toList(),
  };
}

class SummaryPage {
  const SummaryPage({required this.summaries, this.nextCursor});
  final List<Summary> summaries;
  final String? nextCursor;

  factory SummaryPage.fromJson(Map<String, dynamic> json) => SummaryPage(
    summaries: (json['summaries'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Summary.fromJson)
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'summaries': summaries.map((s) => s.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}

class PostPage {
  const PostPage({required this.posts, this.nextCursor});
  final List<Post> posts;
  final String? nextCursor;

  factory PostPage.fromJson(Map<String, dynamic> json) => PostPage(
    posts: (json['posts'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Post.fromJson)
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'posts': posts.map((p) => p.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}

/// `{"id","handle","display_name"}`, e.g. a comment's author.
class UserSummary {
  const UserSummary({
    required this.id,
    required this.handle,
    required this.displayName,
  });
  final String id;
  final String handle;
  final String displayName;

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
    id: json['id'] as String? ?? '',
    handle: json['handle'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'display_name': displayName,
  };

  /// The display name, or the handle when there is none.
  String get name => displayName.isEmpty ? '@$handle' : displayName;
}

/// A public profile.
class Profile {
  const Profile({
    required this.id,
    required this.handle,
    required this.displayName,
    this.bio = '',
    this.followers = 0,
    this.following = 0,
    this.favorites = 0,
    this.isFollowing = false,
    this.isMe = false,
  });

  final String id;
  final String handle;
  final String displayName;
  final String bio;
  final int followers;
  final int following;
  final int favorites;
  final bool isFollowing;
  final bool isMe;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String? ?? '',
    handle: json['handle'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    bio: json['bio'] as String? ?? '',
    followers: _int(json['followers']),
    following: _int(json['following']),
    favorites: _int(json['favorites']),
    isFollowing: json['is_following'] as bool? ?? false,
    isMe: json['is_me'] as bool? ?? false,
  );

  Profile withFollow(FollowState f) => Profile(
    id: id,
    handle: handle,
    displayName: displayName,
    bio: bio,
    followers: f.followers,
    following: following,
    favorites: favorites,
    isFollowing: f.isFollowing,
    isMe: isMe,
  );
}

/// What follow/unfollow return, and the `follow` of a source.
class FollowState {
  const FollowState({this.followers = 0, this.isFollowing = false});
  final int followers;
  final bool isFollowing;

  factory FollowState.fromJson(Map<String, dynamic> json) => FollowState(
    followers: _int(json['followers']),
    isFollowing: json['is_following'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'followers': followers,
    'is_following': isFollowing,
  };
}

/// What can be followed.
enum FollowKind { user, source, author }

/// One entry of GET /v1/me/following.
class FollowItem {
  const FollowItem({
    required this.kind,
    required this.target,
    required this.label,
    this.handle,
  });

  final String kind;
  final String target;
  final String label;
  final String? handle;

  factory FollowItem.fromJson(Map<String, dynamic> json) => FollowItem(
    kind: json['kind'] as String? ?? '',
    target: json['target'] as String? ?? '',
    label: json['label'] as String? ?? '',
    handle: json['handle'] as String?,
  );
}

/// A source in a list (the library's books, an author's books).
class SourceSummary {
  const SourceSummary({
    required this.id,
    required this.title,
    this.authors = const [],
    this.kind = '',
    this.cardCount = 0,
    this.videoCount = 0,
    this.topics = const [],
  });

  final String id;
  final String title;
  final List<String> authors;
  final String kind;
  final int cardCount;

  /// Cards with an explainer video.
  final int videoCount;

  /// Topic slugs of its published cards.
  final List<String> topics;

  factory SourceSummary.fromJson(Map<String, dynamic> json) => SourceSummary(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    authors: _stringList(json['authors']),
    kind: json['kind'] as String? ?? '',
    cardCount: _int(json['card_count']),
    videoCount: _int(json['video_count']),
    topics: _stringList(json['topics']),
  );
}

/// A page of GET /v1/sources.
class SourceListPage {
  const SourceListPage({required this.sources, this.nextCursor});
  final List<SourceSummary> sources;
  final String? nextCursor;

  factory SourceListPage.fromJson(Map<String, dynamic> json) => SourceListPage(
    sources: (json['sources'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SourceSummary.fromJson)
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );
}

/// An author in the library's list (GET /v1/authors).
class AuthorSummary {
  const AuthorSummary({
    required this.name,
    this.sources = 0,
    this.cardCount = 0,
    this.videoCount = 0,
    this.topics = const [],
    this.followers = 0,
  });

  final String name;

  /// How many of their books are in the library.
  final int sources;
  final int cardCount;
  final int videoCount;
  final List<String> topics;
  final int followers;

  factory AuthorSummary.fromJson(Map<String, dynamic> json) => AuthorSummary(
    name: json['name'] as String? ?? '',
    sources: _int(json['sources']),
    cardCount: _int(json['card_count']),
    videoCount: _int(json['video_count']),
    topics: _stringList(json['topics']),
    followers: _int(json['followers']),
  );
}

/// A page of GET /v1/authors.
class AuthorListPage {
  const AuthorListPage({required this.authors, this.nextCursor});
  final List<AuthorSummary> authors;
  final String? nextCursor;

  factory AuthorListPage.fromJson(Map<String, dynamic> json) => AuthorListPage(
    authors: (json['authors'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthorSummary.fromJson)
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );
}

class AuthorPage {
  const AuthorPage({
    required this.name,
    required this.sources,
    this.cards = const [],
    this.cardCount = 0,
    this.videoCount = 0,
    this.follow = const FollowState(),
  });
  final String name;
  final List<SourceSummary> sources;

  /// Every published card by them, ordered by book then card.
  final List<IdeaCard> cards;
  final int cardCount;
  final int videoCount;
  final FollowState follow;

  factory AuthorPage.fromJson(Map<String, dynamic> json) => AuthorPage(
    name: json['name'] as String? ?? '',
    sources: (json['sources'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SourceSummary.fromJson)
        .toList(),
    cards: parseCards(json['cards']),
    cardCount: _int(json['card_count']),
    videoCount: _int(json['video_count']),
    follow: FollowState.fromJson(json),
  );
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    this.parentId,
    required this.body,
    required this.author,
    this.createdAt,
  });

  final String id;
  final String postId;
  final String? parentId;
  final String body;
  final UserSummary author;
  final DateTime? createdAt;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as String? ?? '',
    postId: json['post_id'] as String? ?? '',
    parentId: json['parent_id'] as String?,
    body: json['body'] as String? ?? '',
    author: UserSummary.fromJson(
      (json['author'] as Map<String, dynamic>?) ?? const {},
    ),
    createdAt: _date(json['created_at']),
  );
}

/// A comment in the moderators' queue: its reports, and whether it is
/// already hidden (three reports hide it until a moderator decides).
class ReportedComment {
  const ReportedComment({
    required this.comment,
    required this.status,
    required this.reports,
    this.reasons = const [],
  });

  final Comment comment;

  /// `visible` or `hidden`.
  final String status;
  final int reports;
  final List<String> reasons;

  String get id => comment.id;
  bool get hidden => status == 'hidden';

  factory ReportedComment.fromJson(Map<String, dynamic> json) =>
      ReportedComment(
        comment: Comment.fromJson(json),
        status: json['status'] as String? ?? 'visible',
        reports: _int(json['reports']),
        reasons: (json['reasons'] as List? ?? const [])
            .whereType<String>()
            .where((r) => r.isNotEmpty)
            .toList(),
      );

  ReportedComment withStatus(String status) => ReportedComment(
    comment: comment,
    status: status,
    reports: reports,
    reasons: reasons,
  );
}

class CommentPage {
  const CommentPage({required this.comments, this.nextCursor});
  final List<Comment> comments;
  final String? nextCursor;

  factory CommentPage.fromJson(Map<String, dynamic> json) => CommentPage(
    comments: (json['comments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Comment.fromJson)
        .toList(),
    nextCursor: json['next_cursor'] as String?,
  );
}

/// A top-level comment with its replies (one level deep).
class CommentThread {
  const CommentThread(this.comment, this.replies);
  final Comment comment;
  final List<Comment> replies;
}

/// Groups comments (oldest first) into top-level threads. A reply whose
/// parent isn't loaded is shown as top level.
List<CommentThread> threadComments(List<Comment> comments) {
  final top = <Comment>[];
  final replies = <String, List<Comment>>{};
  final ids = comments.map((c) => c.id).toSet();
  for (final c in comments) {
    if (c.parentId != null && ids.contains(c.parentId)) {
      replies.putIfAbsent(c.parentId!, () => []).add(c);
    } else {
      top.add(c);
    }
  }
  return [for (final c in top) CommentThread(c, replies[c.id] ?? const [])];
}

/// An amount in cents as "$4.99", "£1.20" or "CHF 3.00".
String moneyLabel(int cents, [String currency = 'usd']) {
  final symbol = switch (currency.toLowerCase()) {
    'usd' => r'$',
    'gbp' => '£',
    'eur' => '€',
    _ => '${currency.toUpperCase()} ',
  };
  return '$symbol${(cents / 100).toStringAsFixed(2)}';
}

class GiftTier {
  const GiftTier({
    required this.id,
    required this.name,
    required this.amountCents,
    required this.currency,
    required this.productId,
  });

  final String id;
  final String name;
  final int amountCents;
  final String currency;
  final String productId;

  factory GiftTier.fromJson(Map<String, dynamic> json) => GiftTier(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    amountCents: _int(json['amount_cents']),
    currency: json['currency'] as String? ?? 'usd',
    productId: json['product_id'] as String? ?? '',
  );

  /// e.g. "$4.99" (used when the store has no localized price).
  String get displayPrice => moneyLabel(amountCents, currency);
}

class GiftTiers {
  const GiftTiers({required this.tiers, this.providers = const {}});
  final List<GiftTier> tiers;

  /// `stripe`, `apple`, `google` -> whether that provider is set up.
  final Map<String, bool> providers;

  bool enabled(String provider) => providers[provider] ?? false;

  factory GiftTiers.fromJson(Map<String, dynamic> json) => GiftTiers(
    tiers: (json['tiers'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GiftTier.fromJson)
        .toList(),
    providers: json['providers'] is Map
        ? {
            for (final e in (json['providers'] as Map).entries)
              e.key.toString(): e.value == true,
          }
        : const {},
  );
}

class Gift {
  const Gift({
    required this.id,
    required this.postId,
    required this.tier,
    this.amountCents = 0,
    this.currency = 'usd',
    this.provider = '',
    this.status = '',
  });

  final String id;
  final String postId;
  final String tier;
  final int amountCents;
  final String currency;
  final String provider;
  final String status;

  factory Gift.fromJson(Map<String, dynamic> json) => Gift(
    id: json['id'] as String? ?? '',
    postId: json['post_id'] as String? ?? '',
    tier: json['tier'] as String? ?? '',
    amountCents: _int(json['amount_cents']),
    currency: json['currency'] as String? ?? 'usd',
    provider: json['provider'] as String? ?? '',
    status: json['status'] as String? ?? '',
  );
}

// ---------------------------------------------------------------------------
// Notifications, streaks, referrals, blocking, discover, circles, premium and
// the moderator dashboard.

/// One inbox item. (Named to avoid Flutter's `Notification`.)
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.text,
    this.actor,
    this.postId,
    this.commentId,
    this.circleId,
    this.readAt,
    this.createdAt,
  });

  final String id;

  /// `daily`, `reply`, `follow`, `circle` or `reward`.
  final String kind;
  final String text;
  final UserSummary? actor;
  final String? postId;
  final String? commentId;
  final String? circleId;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get read => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        text: json['text'] as String? ?? '',
        actor: json['actor'] is Map<String, dynamic>
            ? UserSummary.fromJson(json['actor'] as Map<String, dynamic>)
            : null,
        postId: json['post_id'] as String?,
        commentId: json['comment_id'] as String?,
        circleId: json['circle_id'] as String?,
        readAt: _date(json['read_at']),
        createdAt: _date(json['created_at']),
      );

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    kind: kind,
    text: text,
    actor: actor,
    postId: postId,
    commentId: commentId,
    circleId: circleId,
    readAt: readAt ?? at,
    createdAt: createdAt,
  );
}

class NotificationsPage {
  const NotificationsPage({required this.items, this.unread = 0});
  final List<AppNotification> items;
  final int unread;

  factory NotificationsPage.fromJson(Map<String, dynamic> json) =>
      NotificationsPage(
        items: (json['notifications'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AppNotification.fromJson)
            .toList(),
        unread: _int(json['unread']),
      );
}

/// Where a notification (inbox item or push) leads, or null.
String? notificationLocation({
  String? postId,
  String? commentId,
  String? circleId,
  String? actorHandle,
}) {
  if (circleId != null && circleId.isNotEmpty) {
    return '/circles/${Uri.encodeComponent(circleId)}';
  }
  if (postId != null && postId.isNotEmpty) {
    final p = Uri.encodeComponent(postId);
    return commentId != null && commentId.isNotEmpty
        ? '/posts/$p/comments'
        : '/cards/$p';
  }
  if (actorHandle != null && actorHandle.isNotEmpty) {
    return '/users/${Uri.encodeComponent(actorHandle)}';
  }
  return null;
}

class DayCount {
  const DayCount({required this.day, this.ideas = 0});
  final String day;
  final int ideas;

  factory DayCount.fromJson(Map<String, dynamic> json) =>
      DayCount(day: json['day'] as String? ?? '', ideas: _int(json['ideas']));
}

class Streak {
  const Streak({
    this.current = 0,
    this.longest = 0,
    this.goal = 3,
    this.today = 0,
    this.goalMet = false,
    this.lastDays = const [],
  });

  final int current;
  final int longest;
  final int goal;
  final int today;
  final bool goalMet;

  /// The last 7 local days, oldest first.
  final List<DayCount> lastDays;

  factory Streak.fromJson(Map<String, dynamic> json) => Streak(
    current: _int(json['current']),
    longest: _int(json['longest']),
    goal: _int(json['goal']),
    today: _int(json['today']),
    goalMet: json['goal_met'] as bool? ?? false,
    lastDays: (json['last_days'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DayCount.fromJson)
        .toList(),
  );
}

class Referrals {
  const Referrals({
    required this.code,
    required this.link,
    this.invited = 0,
    this.rewarded = 0,
    this.rewardDays = 0,
  });

  final String code;
  final String link;
  final int invited;
  final int rewarded;
  final int rewardDays;

  factory Referrals.fromJson(Map<String, dynamic> json) => Referrals(
    code: json['code'] as String? ?? '',
    link: json['link'] as String? ?? '',
    invited: _int(json['invited']),
    rewarded: _int(json['rewarded']),
    rewardDays: _int(json['reward_days']),
  );
}

/// Someone the user blocked (`block`) or muted (`mute`).
class BlockedUser {
  const BlockedUser({required this.user, required this.kind});
  final UserSummary user;
  final String kind;

  bool get muted => kind == 'mute';

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    user: UserSummary.fromJson(json),
    kind: json['kind'] as String? ?? 'block',
  );
}

class PopularBook {
  const PopularBook({required this.source, this.followers = 0});
  final SourceSummary source;
  final int followers;

  factory PopularBook.fromJson(Map<String, dynamic> json) => PopularBook(
    source: SourceSummary.fromJson(json),
    followers: _int(json['followers']),
  );
}

class PopularAuthor {
  const PopularAuthor({
    required this.name,
    this.followers = 0,
    this.sources = 0,
  });
  final String name;
  final int followers;
  final int sources;

  factory PopularAuthor.fromJson(Map<String, dynamic> json) => PopularAuthor(
    name: json['name'] as String? ?? '',
    followers: _int(json['followers']),
    sources: _int(json['sources']),
  );
}

List<Post> _posts(Object? v) => (v as List? ?? const [])
    .whereType<Map<String, dynamic>>()
    .map(Post.fromJson)
    .toList();

class DiscoverPage {
  const DiscoverPage({
    this.trending = const [],
    this.newPosts = const [],
    this.books = const [],
    this.authors = const [],
    this.circles = const [],
  });

  final List<Post> trending;
  final List<Post> newPosts;
  final List<PopularBook> books;
  final List<PopularAuthor> authors;
  final List<Circle> circles;

  factory DiscoverPage.fromJson(Map<String, dynamic> json) => DiscoverPage(
    trending: _posts(json['trending']),
    newPosts: _posts(json['new']),
    books: (json['books'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PopularBook.fromJson)
        .toList(),
    authors: (json['authors'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PopularAuthor.fromJson)
        .toList(),
    circles: parseCircles(json['circles']),
  );
}

/// A discussion group for one book, up to 50 members.
class Circle {
  const Circle({
    required this.id,
    required this.name,
    this.description = '',
    required this.sourceId,
    required this.sourceTitle,
    this.owner,
    this.members = 0,
    this.isMember = false,
    this.role,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String sourceId;
  final String sourceTitle;
  final UserSummary? owner;
  final int members;
  final bool isMember;

  /// `owner` or `member` when the viewer is in it.
  final String? role;
  final DateTime? createdAt;

  bool get isOwner => role == 'owner';

  factory Circle.fromJson(Map<String, dynamic> json) {
    final source = json['source'] is Map<String, dynamic>
        ? json['source'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return Circle(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sourceId: source['id'] as String? ?? '',
      sourceTitle: source['title'] as String? ?? '',
      owner: json['owner'] is Map<String, dynamic>
          ? UserSummary.fromJson(json['owner'] as Map<String, dynamic>)
          : null,
      members: _int(json['members']),
      isMember: json['is_member'] as bool? ?? false,
      role: json['role'] as String?,
      createdAt: _date(json['created_at']),
    );
  }
}

List<Circle> parseCircles(Object? v) => (v as List? ?? const [])
    .whereType<Map<String, dynamic>>()
    .map(Circle.fromJson)
    .toList();

class CircleMessage {
  const CircleMessage({
    required this.id,
    required this.circleId,
    required this.body,
    this.postId,
    required this.author,
    this.createdAt,
  });

  final String id;
  final String circleId;
  final String body;

  /// An idea from the circle's book, attached to the message.
  final String? postId;
  final UserSummary author;
  final DateTime? createdAt;

  factory CircleMessage.fromJson(Map<String, dynamic> json) => CircleMessage(
    id: json['id'] as String? ?? '',
    circleId: json['circle_id'] as String? ?? '',
    body: json['body'] as String? ?? '',
    postId: json['post_id'] as String?,
    author: UserSummary.fromJson(
      (json['author'] as Map<String, dynamic>?) ?? const {},
    ),
    createdAt: _date(json['created_at']),
  );
}

/// A member of a book circle (`GET /v1/circles/{id}/members`).
class CircleMember {
  const CircleMember({
    required this.id,
    required this.handle,
    required this.displayName,
    this.role = 'member',
    this.joinedAt,
  });

  final String id;
  final String handle;
  final String displayName;

  /// `owner` or `member`.
  final String role;
  final DateTime? joinedAt;

  bool get isOwner => role == 'owner';
  String get name => displayName.isNotEmpty ? displayName : '@$handle';

  factory CircleMember.fromJson(Map<String, dynamic> json) => CircleMember(
    id: json['id'] as String? ?? '',
    handle: json['handle'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    joinedAt: _date(json['joined_at']),
  );
}

/// A public stash with its owner and cards.
class PublicStash {
  const PublicStash({required this.stash, this.owner, required this.cards});
  final Stash stash;
  final UserSummary? owner;
  final List<IdeaCard> cards;

  factory PublicStash.fromJson(Map<String, dynamic> json) {
    final s = (json['stash'] as Map<String, dynamic>?) ?? const {};
    return PublicStash(
      stash: Stash.fromJson(s),
      owner: s['owner'] is Map<String, dynamic>
          ? UserSummary.fromJson(s['owner'] as Map<String, dynamic>)
          : null,
      cards: parseCards(json['cards']),
    );
  }
}

class PremiumPlan {
  const PremiumPlan({
    required this.id,
    required this.name,
    required this.amountCents,
    required this.currency,
    required this.interval,
    required this.productId,
  });

  final String id;
  final String name;
  final int amountCents;
  final String currency;

  /// `month` or `year`.
  final String interval;
  final String productId;

  factory PremiumPlan.fromJson(Map<String, dynamic> json) => PremiumPlan(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    amountCents: _int(json['amount_cents']),
    currency: json['currency'] as String? ?? 'usd',
    interval: json['interval'] as String? ?? '',
    productId: json['product_id'] as String? ?? '',
  );

  String get displayPrice => GiftTier(
    id: id,
    name: name,
    amountCents: amountCents,
    currency: currency,
    productId: productId,
  ).displayPrice;
}

class PremiumSubscription {
  const PremiumSubscription({
    required this.provider,
    required this.plan,
    required this.status,
    this.expiresAt,
  });
  final String provider;
  final String plan;
  final String status;
  final DateTime? expiresAt;

  factory PremiumSubscription.fromJson(Map<String, dynamic> json) =>
      PremiumSubscription(
        provider: json['provider'] as String? ?? '',
        plan: json['plan'] as String? ?? '',
        status: json['status'] as String? ?? '',
        expiresAt: _date(json['expires_at']),
      );
}

class PremiumStatus {
  const PremiumStatus({
    this.plans = const [],
    this.providers = const {},
    this.premium = false,
    this.premiumUntil,
    this.subscription,
  });

  final List<PremiumPlan> plans;
  final Map<String, bool> providers;
  final bool premium;
  final DateTime? premiumUntil;
  final PremiumSubscription? subscription;

  bool enabled(String provider) => providers[provider] ?? false;

  factory PremiumStatus.fromJson(Map<String, dynamic> json) => PremiumStatus(
    plans: (json['plans'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PremiumPlan.fromJson)
        .toList(),
    providers: json['providers'] is Map
        ? {
            for (final e in (json['providers'] as Map).entries)
              e.key.toString(): e.value == true,
          }
        : const {},
    premium: json['premium'] as bool? ?? false,
    premiumUntil: _date(json['premium_until']),
    subscription: json['subscription'] is Map<String, dynamic>
        ? PremiumSubscription.fromJson(
            json['subscription'] as Map<String, dynamic>,
          )
        : null,
  );
}

/// GET /v1/admin/stats. Sections are kept as maps of numbers; [daily] and
/// [topPosts] are typed for the chart and list.
class AdminStats {
  const AdminStats({
    this.users = const {},
    this.retention = const {},
    this.engagement = const {},
    this.moderation = const {},
    this.content = const {},
    this.gifts = const [],
    this.subscriptions = const [],
    this.daily = const [],
    this.topPosts = const [],
  });

  final Map<String, num> users;
  final Map<String, num> retention;
  final Map<String, num> engagement;
  final Map<String, num> moderation;
  final Map<String, num> content;

  /// `{"provider","currency","amount_cents","count"}` for the last 30 days.
  final List<Map<String, dynamic>> gifts;

  /// `{"provider","count"}` active subscriptions.
  final List<Map<String, dynamic>> subscriptions;
  final List<DailyStat> daily;
  final List<TopPost> topPosts;

  static Map<String, num> _nums(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            if (e.value is num) e.key.toString(): e.value as num,
        }
      : const {};

  static List<Map<String, dynamic>> _maps(Object? v) =>
      (v as List? ?? const []).whereType<Map<String, dynamic>>().toList();

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    final revenue = json['revenue'] is Map ? json['revenue'] as Map : const {};
    return AdminStats(
      users: _nums(json['users']),
      retention: _nums(json['retention']),
      engagement: _nums(json['engagement']),
      moderation: _nums(json['moderation']),
      content: _nums(json['content']),
      gifts: _maps(revenue['gifts_30d']),
      subscriptions: _maps(revenue['subscriptions']),
      daily: _maps(json['daily']).map(DailyStat.fromJson).toList(),
      topPosts: _maps(json['top_posts']).map(TopPost.fromJson).toList(),
    );
  }
}

class DailyStat {
  const DailyStat({required this.day, this.signups = 0, this.active = 0});
  final String day;
  final int signups;
  final int active;

  factory DailyStat.fromJson(Map<String, dynamic> json) => DailyStat(
    day: json['day'] as String? ?? '',
    signups: _int(json['signups']),
    active: _int(json['active']),
  );
}

class TopPost {
  const TopPost({required this.id, required this.title, this.score = 0});
  final String id;
  final String title;
  final int score;

  factory TopPost.fromJson(Map<String, dynamic> json) => TopPost(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    score: _int(json['score']),
  );
}
