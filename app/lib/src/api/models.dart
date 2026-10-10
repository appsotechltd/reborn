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
  };

  /// Text read aloud by the Listen button.
  String get spokenText => '$title.\n\n$body\n\nApply it. $applyIt';
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
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final String handle;
  final String bio;
  final List<String> topics;

  bool get isModerator => role == 'moderator';

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    handle: json['handle'] as String? ?? '',
    bio: json['bio'] as String? ?? '',
    topics: _stringList(json['topics']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'handle': handle,
    'display_name': displayName,
    'bio': bio,
    'role': role,
    'topics': topics,
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
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final int cardCount;
  final DateTime? createdAt;

  factory Stash.fromJson(Map<String, dynamic> json) => Stash(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    cardCount: (json['card_count'] as num?)?.toInt() ?? 0,
    createdAt: _date(json['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'card_count': cardCount,
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
  });
  final Source source;
  final List<IdeaCard> cards;
  final FollowState follow;

  factory SourceDetail.fromJson(Map<String, dynamic> json) => SourceDetail(
    source: Source.fromJson(json['source'] as Map<String, dynamic>),
    cards: parseCards(json['cards']),
    follow: json['follow'] is Map<String, dynamic>
        ? FollowState.fromJson(json['follow'] as Map<String, dynamic>)
        : const FollowState(),
  );

  Map<String, dynamic> toJson() => {
    'source': source.toJson(),
    'cards': cards.map((c) => c.toJson()).toList(),
    'follow': follow.toJson(),
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

  /// `source`, `author`, `favorite`, `topic` or `new`.
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
    'favorite' => '$label favourited this',
    'topic' => label,
    _ => 'New on Reborn',
  };
}

/// Every published card is a post.
class Post {
  const Post({
    required this.id,
    required this.card,
    this.publishedAt,
    this.stats = const PostStats(),
    this.viewer,
    this.reason,
  });

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

  Map<String, dynamic> toJson() => {
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

/// A source in a list (e.g. an author's books).
class SourceSummary {
  const SourceSummary({
    required this.id,
    required this.title,
    this.authors = const [],
    this.kind = '',
    this.cardCount = 0,
  });

  final String id;
  final String title;
  final List<String> authors;
  final String kind;
  final int cardCount;

  factory SourceSummary.fromJson(Map<String, dynamic> json) => SourceSummary(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    authors: _stringList(json['authors']),
    kind: json['kind'] as String? ?? '',
    cardCount: _int(json['card_count']),
  );
}

class AuthorPage {
  const AuthorPage({
    required this.name,
    required this.sources,
    this.follow = const FollowState(),
  });
  final String name;
  final List<SourceSummary> sources;
  final FollowState follow;

  factory AuthorPage.fromJson(Map<String, dynamic> json) => AuthorPage(
    name: json['name'] as String? ?? '',
    sources: (json['sources'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SourceSummary.fromJson)
        .toList(),
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
  String get displayPrice {
    final symbol = switch (currency.toLowerCase()) {
      'usd' => r'$',
      'gbp' => '£',
      'eur' => '€',
      _ => '${currency.toUpperCase()} ',
    };
    return '$symbol${(amountCents / 100).toStringAsFixed(2)}';
  }
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
