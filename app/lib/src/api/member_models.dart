// Member cards, the card studio, and writer earnings and subscriptions
// (docs/API.md, "Member cards, categories and the card studio" and "Writer
// earnings and subscriptions").

import 'ai_models.dart';
import 'models.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

Map<String, bool> _flags(Object? v) => v is Map
    ? {for (final e in v.entries) e.key.toString(): e.value == true}
    : const {};

/// Who a member card is shown to, in display order.
const kAudiences = ['everyone', 'followers', 'subscribers', 'private'];

/// "Everyone", "Followers", "Subscribers", "Only me", "Hidden".
String audienceLabel(String? audience) => switch (audience) {
  'followers' => 'Followers',
  'subscribers' => 'Subscribers',
  'private' => 'Only me',
  'hidden' => 'Hidden',
  _ => 'Everyone',
};

/// Limits on a member card, as the API checks them.
const kCardTitleMax = 120;
const kCardBodyMax = 1500;
const kCardApplyItMax = 400;
const kCategoryNameMax = 40;
const kPitchMax = 300;

/// `GET /v1/me/cards`.
class MyCardsPage {
  const MyCardsPage({required this.cards, this.nextCursor});
  final List<IdeaCard> cards;
  final String? nextCursor;

  factory MyCardsPage.fromJson(Map<String, dynamic> json) => MyCardsPage(
    cards: parseCards(json['cards']),
    nextCursor: json['next_cursor']?.toString(),
  );
}

/// `GET /v1/users/{handle}/cards`: the cards the viewer may see, and (on the
/// first page) the writer's categories that hold any.
class UserCardsPage {
  const UserCardsPage({
    required this.posts,
    this.categories = const [],
    this.nextCursor,
  });
  final List<Post> posts;
  final List<CardCategory> categories;
  final String? nextCursor;

  factory UserCardsPage.fromJson(Map<String, dynamic> json) => UserCardsPage(
    posts: _maps(json['posts']).map(Post.fromJson).toList(),
    categories: _maps(json['categories']).map(CardCategory.fromJson).toList(),
    nextCursor: json['next_cursor']?.toString(),
  );
}

/// A member card in the moderators' list.
class ReportedCard {
  const ReportedCard({
    required this.card,
    required this.status,
    required this.reports,
    this.reasons = const [],
  });

  final IdeaCard card;
  final String status;
  final int reports;
  final List<String> reasons;

  bool get hidden => status == 'hidden';

  factory ReportedCard.fromJson(Map<String, dynamic> json) => ReportedCard(
    card: IdeaCard.fromJson(json['card'] as Map<String, dynamic>),
    status: json['status'] as String? ?? '',
    reports: _int(json['reports']),
    reasons: (json['reasons'] as List? ?? const [])
        .whereType<String>()
        .where((r) => r.isNotEmpty)
        .toList(),
  );
}

// ---------------------------------------------------------------------------
// The card studio

class StudioVoice {
  const StudioVoice({required this.id, required this.name});
  final String id;
  final String name;

  factory StudioVoice.fromJson(Map<String, dynamic> json) => StudioVoice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );
}

/// The card studio's image styles, cheapest first.
enum StudioStyle {
  sketch('Sketch', 2),
  illustration('Illustration', 4),
  picture('Photo-like', 12);

  const StudioStyle(this.label, this.defaultUnits);
  final String label;

  /// The price when `GET /v1/studio` hasn't said.
  final int defaultUnits;
}

/// `GET /v1/studio`: prices, voices and the member's wallet.
class StudioStatus {
  const StudioStatus({
    this.available = false,
    this.rates = const [],
    this.videoScenes = 4,
    this.voices = const [],
    this.monthlyUnits = 250,
    this.premium = false,
    this.wallet,
  });

  final bool available;
  final List<AIRate> rates;
  final int videoScenes;
  final List<StudioVoice> voices;
  final int monthlyUnits;
  final bool premium;
  final AIWallet? wallet;

  factory StudioStatus.fromJson(Map<String, dynamic> json) => StudioStatus(
    available: json['available'] == true,
    rates: _maps(json['rates']).map(AIRate.fromJson).toList(),
    videoScenes: (json['video_scenes'] as num?)?.toInt() ?? 4,
    voices: _maps(json['voices']).map(StudioVoice.fromJson).toList(),
    monthlyUnits: (json['monthly_units'] as num?)?.toInt() ?? 250,
    premium: json['premium'] == true,
    wallet: json['wallet'] is Map<String, dynamic>
        ? AIWallet.fromJson(json['wallet'] as Map<String, dynamic>)
        : null,
  );

  StudioStatus withWallet(AIWallet wallet) => StudioStatus(
    available: available,
    rates: rates,
    videoScenes: videoScenes,
    voices: voices,
    monthlyUnits: monthlyUnits,
    premium: premium,
    wallet: wallet,
  );

  int _rate(String kind, int fallback) {
    for (final r in rates) {
      if (r.kind == kind && r.units > 0) return r.units;
    }
    return fallback;
  }

  int imageUnits(StudioStyle style) => _rate(style.name, style.defaultUnits);

  /// A one-minute card (about 150 words) read aloud.
  int get minuteAudioUnits => _rate('audio', 3);

  /// An illustrated video of a one-minute card.
  int get minuteVideoUnits => _rate(
    'video',
    1 + videoScenes * imageUnits(StudioStyle.illustration) + minuteAudioUnits,
  );

  /// What the monthly allowance buys: "about 12 videos, 62 illustrations or
  /// 83 one-minute audios".
  String get allowanceLine {
    final ill = imageUnits(StudioStyle.illustration);
    return '${monthlyUnits ~/ minuteVideoUnits} videos, '
        '${monthlyUnits ~/ ill} illustrations or '
        '${monthlyUnits ~/ minuteAudioUnits} one-minute audios';
  }

  /// The card read aloud: one unit per started 50 words.
  int audioUnits(String title, String body, String applyIt) =>
      studioAudioUnits(title, body, applyIt);

  /// A unit to plan the scenes, an illustration per scene, and the narration.
  int videoUnits(String title, String body, String applyIt) =>
      1 +
      videoScenes * imageUnits(StudioStyle.illustration) +
      studioAudioUnits(title, body, applyIt);
}

/// What the narration of a member card reads (as the server builds it).
String studioSpokenText(String title, String body, String applyIt) {
  final b = StringBuffer('$title.\n\n$body');
  if (applyIt.isNotEmpty) b.write('\n\nApply it. $applyIt');
  return b.toString();
}

/// One unit per started 50 words of narration, at least one.
int studioAudioUnits(String title, String body, String applyIt) {
  final words = wordCount(studioSpokenText(title, body, applyIt));
  final units = (words + 49) ~/ 50;
  return units < 1 ? 1 : units;
}

/// What a studio action returns: the card with its new media, what it cost
/// and the wallet after.
class StudioResult {
  const StudioResult({
    required this.card,
    required this.units,
    required this.wallet,
  });
  final IdeaCard card;
  final int units;
  final AIWallet? wallet;

  factory StudioResult.fromJson(Map<String, dynamic> json) => StudioResult(
    card: IdeaCard.fromJson(json['card'] as Map<String, dynamic>),
    units: _int(json['units']),
    wallet: json['wallet'] is Map<String, dynamic>
        ? AIWallet.fromJson(json['wallet'] as Map<String, dynamic>)
        : null,
  );
}

// ---------------------------------------------------------------------------
// Writer earnings and subscriptions

/// A monthly price a writer can choose.
class WriterTier {
  const WriterTier({
    required this.id,
    required this.amountCents,
    this.currency = 'usd',
    this.productId = '',
  });

  /// `month_199`, `month_499` or `month_999`.
  final String id;
  final int amountCents;
  final String currency;

  /// The app store product: a 30-day pass.
  final String productId;

  /// "$4.99".
  String get displayPrice => moneyLabel(amountCents, currency);

  factory WriterTier.fromJson(Map<String, dynamic> json) => WriterTier(
    id: json['id'] as String? ?? '',
    amountCents: _int(json['amount_cents']),
    currency: json['currency'] as String? ?? 'usd',
    productId: json['product_id'] as String? ?? '',
  );
}

/// The writer tiers, used until `GET /v1/me/plan` loads.
const kWriterTiers = [
  WriterTier(
    id: 'month_199',
    amountCents: 199,
    productId: 'reborn.writer.month199',
  ),
  WriterTier(
    id: 'month_499',
    amountCents: 499,
    productId: 'reborn.writer.month499',
  ),
  WriterTier(
    id: 'month_999',
    amountCents: 999,
    productId: 'reborn.writer.month999',
  ),
];

/// A writer's own subscription offer.
class WriterPlan {
  const WriterPlan({
    required this.tier,
    this.enabled = false,
    this.pitch = '',
    this.subscribers = 0,
  });
  final String tier;
  final bool enabled;
  final String pitch;
  final int subscribers;

  factory WriterPlan.fromJson(Map<String, dynamic> json) => WriterPlan(
    tier: json['tier'] as String? ?? '',
    enabled: json['enabled'] == true,
    pitch: json['pitch'] as String? ?? '',
    subscribers: _int(json['subscribers']),
  );
}

/// `GET /v1/me/plan`.
class MyWriterPlan {
  const MyWriterPlan({
    this.plan,
    this.tiers = kWriterTiers,
    this.commissionPercent = 30,
    this.storeFeePercent = 15,
  });
  final WriterPlan? plan;
  final List<WriterTier> tiers;
  final int commissionPercent;
  final int storeFeePercent;

  factory MyWriterPlan.fromJson(Map<String, dynamic> json) {
    final tiers = _maps(json['tiers']).map(WriterTier.fromJson).toList();
    return MyWriterPlan(
      plan: json['plan'] is Map<String, dynamic>
          ? WriterPlan.fromJson(json['plan'] as Map<String, dynamic>)
          : null,
      tiers: tiers.isEmpty ? kWriterTiers : tiers,
      commissionPercent: (json['commission_percent'] as num?)?.toInt() ?? 30,
      storeFeePercent: (json['store_fee_percent'] as num?)?.toInt() ?? 15,
    );
  }
}

/// A member's subscription to a writer.
class WriterSubscription {
  const WriterSubscription({
    required this.writer,
    required this.tier,
    this.provider = '',
    this.renews = false,
    this.expiresAt,
    this.active = false,
  });
  final UserSummary writer;
  final String tier;

  /// `stripe`, `apple` or `google`.
  final String provider;

  /// A web subscription that renews each month; app passes never do.
  final bool renews;
  final DateTime? expiresAt;
  final bool active;

  factory WriterSubscription.fromJson(Map<String, dynamic> json) =>
      WriterSubscription(
        writer: UserSummary.fromJson(
          json['writer'] as Map<String, dynamic>? ?? const {},
        ),
        tier: json['tier'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        renews: json['renews'] == true,
        expiresAt: _date(json['expires_at']),
        active: json['active'] == true,
      );
}

/// `GET /v1/users/{handle}/plan`: what a writer sells, and the viewer's
/// subscription to them.
class WriterOffer {
  const WriterOffer({
    this.pitch = '',
    this.subscribers = 0,
    this.tier,
    this.lockedCards = 0,
    this.subscription,
    this.providers = const {},
  });

  final String pitch;
  final int subscribers;

  /// Null when the writer doesn't sell subscriptions.
  final WriterTier? tier;

  /// Cards the viewer can't see yet (subscriber-only or followers-only).
  final int lockedCards;
  final WriterSubscription? subscription;
  final Map<String, bool> providers;

  bool get sells => tier != null;
  bool get subscribed => subscription?.active ?? false;
  bool enabled(String provider) => providers[provider] ?? false;

  factory WriterOffer.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] is Map<String, dynamic>
        ? json['plan'] as Map<String, dynamic>
        : null;
    return WriterOffer(
      pitch: plan?['pitch'] as String? ?? '',
      subscribers: _int(plan?['subscribers']),
      tier: plan != null && json['tier'] is Map<String, dynamic>
          ? WriterTier.fromJson(json['tier'] as Map<String, dynamic>)
          : null,
      lockedCards: _int(json['locked_cards']),
      subscription: json['subscription'] is Map<String, dynamic>
          ? WriterSubscription.fromJson(
              json['subscription'] as Map<String, dynamic>,
            )
          : null,
      providers: _flags(json['providers']),
    );
  }
}

/// A gift or subscription payment a writer earned from.
class EarningItem {
  const EarningItem({
    required this.kind,
    this.postId = '',
    this.postTitle = '',
    this.tier = '',
    this.amountCents = 0,
    this.authorCents = 0,
    this.currency = 'usd',
    this.from,
    this.paidAt,
  });

  /// `gift` or `subscription`.
  final String kind;
  final String postId;
  final String postTitle;
  final String tier;
  final int amountCents;

  /// The writer's share.
  final int authorCents;
  final String currency;
  final UserSummary? from;
  final DateTime? paidAt;

  factory EarningItem.fromJson(Map<String, dynamic> json) => EarningItem(
    kind: json['kind'] as String? ?? '',
    postId: json['post_id'] as String? ?? '',
    postTitle: json['post_title'] as String? ?? '',
    tier: json['tier'] as String? ?? '',
    amountCents: _int(json['amount_cents']),
    authorCents: _int(json['author_cents']),
    currency: json['currency'] as String? ?? 'usd',
    from: json['from'] is Map<String, dynamic>
        ? UserSummary.fromJson(json['from'] as Map<String, dynamic>)
        : null,
    paidAt: _date(json['paid_at']),
  );
}

/// `GET /v1/me/earnings`.
class Earnings {
  const Earnings({
    this.totalCents = 0,
    this.thisMonthCents = 0,
    this.gifts = 0,
    this.subscribers = 0,
    this.currency = 'usd',
    this.recent = const [],
    this.commissionPercent = 30,
    this.storeFeePercent = 15,
  });

  final int totalCents;
  final int thisMonthCents;
  final int gifts;
  final int subscribers;
  final String currency;
  final List<EarningItem> recent;
  final int commissionPercent;
  final int storeFeePercent;

  factory Earnings.fromJson(Map<String, dynamic> json) {
    final e = json['earnings'] as Map<String, dynamic>? ?? const {};
    return Earnings(
      totalCents: _int(e['total_cents']),
      thisMonthCents: _int(e['this_month_cents']),
      gifts: _int(e['gifts']),
      subscribers: _int(e['subscribers']),
      currency: e['currency'] as String? ?? 'usd',
      recent: _maps(e['recent']).map(EarningItem.fromJson).toList(),
      commissionPercent: (json['commission_percent'] as num?)?.toInt() ?? 30,
      storeFeePercent: (json['store_fee_percent'] as num?)?.toInt() ?? 15,
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "14 Nov 2026".
String shortDate(DateTime? t) {
  if (t == null) return '';
  final l = t.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}
