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
    this.topics = const [],
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final List<String> topics;

  bool get isModerator => role == 'moderator';

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    topics: _stringList(json['topics']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
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
  const SourceDetail({required this.source, required this.cards});
  final Source source;
  final List<IdeaCard> cards;

  factory SourceDetail.fromJson(Map<String, dynamic> json) => SourceDetail(
    source: Source.fromJson(json['source'] as Map<String, dynamic>),
    cards: parseCards(json['cards']),
  );

  Map<String, dynamic> toJson() => {
    'source': source.toJson(),
    'cards': cards.map((c) => c.toJson()).toList(),
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
