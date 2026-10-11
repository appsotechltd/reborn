// Reborn AI, the premium assistant: wallet, rates, top-up packs and chat
// messages (docs/API.md, "Reborn AI").

import 'models.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

/// "1 unit" / "1,300 units".
String unitsLabel(int n) {
  final s = n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$s ${n == 1 ? 'unit' : 'units'}';
}

class AIWallet {
  const AIWallet({
    required this.monthlyUnits,
    required this.allowanceUsed,
    required this.allowanceLeft,
    required this.topupUnits,
    required this.remaining,
    required this.resetsAt,
  });

  final int monthlyUnits;
  final int allowanceUsed;
  final int allowanceLeft;
  final int topupUnits;
  final int remaining;
  final DateTime? resetsAt;

  factory AIWallet.fromJson(Map<String, dynamic> json) => AIWallet(
    monthlyUnits: _int(json['monthly_units']),
    allowanceUsed: _int(json['allowance_used']),
    allowanceLeft: _int(json['allowance_left']),
    topupUnits: _int(json['topup_units']),
    remaining: _int(json['remaining']),
    resetsAt: DateTime.tryParse(json['resets_at'] as String? ?? ''),
  );

  /// Share of the monthly allowance still unused, 0..1.
  double get allowanceShare => monthlyUnits <= 0
      ? 0
      : (allowanceLeft / monthlyUnits).clamp(0, 1).toDouble();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "240 of 250 units left this month, plus 600 units from top-ups".
  String get summary {
    final monthly = monthlyUnits > 0
        ? '$allowanceLeft of ${unitsLabel(monthlyUnits)} left this month'
        : '';
    final topup = topupUnits > 0
        ? '${unitsLabel(topupUnits)} from top-ups'
        : '';
    if (monthly.isNotEmpty && topup.isNotEmpty) return '$monthly, plus $topup';
    if (monthly.isNotEmpty) return monthly;
    if (topup.isNotEmpty) return topup;
    return 'No AI units left';
  }

  /// "Resets 1 Nov".
  String get resetLabel {
    final r = resetsAt?.toUtc();
    return r == null ? '' : 'Resets ${r.day} ${_months[r.month - 1]}';
  }
}

class AIRate {
  const AIRate({required this.kind, required this.units, required this.per});
  final String kind;
  final int units;
  final String per;

  factory AIRate.fromJson(Map<String, dynamic> json) => AIRate(
    kind: json['kind'] as String? ?? '',
    units: _int(json['units']),
    per: json['per'] as String? ?? '',
  );

  String get label => switch (kind) {
    'text' => 'Each reply',
    'chart' => 'A chart or graph',
    'voice' => 'Voice',
    'sketch' => 'A sketch',
    'illustration' => 'An illustration',
    'picture' => 'A photo-like picture',
    _ => kind,
  };

  String get cost => kind == 'voice'
      ? '${unitsLabel(units)} per 30 spoken words'
      : unitsLabel(units);
}

class UnitPack {
  const UnitPack({
    required this.id,
    required this.name,
    required this.units,
    required this.amountCents,
    required this.currency,
    required this.productId,
  });

  final String id;
  final String name;
  final int units;
  final int amountCents;
  final String currency;
  final String productId;

  factory UnitPack.fromJson(Map<String, dynamic> json) => UnitPack(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    units: _int(json['units']),
    amountCents: _int(json['amount_cents']),
    currency: json['currency'] as String? ?? 'usd',
    productId: json['product_id'] as String? ?? '',
  );

  /// The server's price, used when the store has no localized one.
  String get displayPrice => GiftTier(
    id: id,
    name: name,
    amountCents: amountCents,
    currency: currency,
    productId: productId,
  ).displayPrice;
}

class AIStatus {
  const AIStatus({
    required this.available,
    required this.premium,
    required this.wallet,
    required this.rates,
    required this.packs,
    required this.providers,
  });

  final bool available;
  final bool premium;
  final AIWallet? wallet;
  final List<AIRate> rates;
  final List<UnitPack> packs;
  final Map<String, bool> providers;

  factory AIStatus.fromJson(Map<String, dynamic> json) => AIStatus(
    available: json['available'] == true,
    premium: json['premium'] == true,
    wallet: json['wallet'] is Map<String, dynamic>
        ? AIWallet.fromJson(json['wallet'] as Map<String, dynamic>)
        : null,
    rates: _maps(json['rates']).map(AIRate.fromJson).toList(),
    packs: _maps(json['packs']).map(UnitPack.fromJson).toList(),
    providers: {
      for (final e
          in (json['providers'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: e.value == true,
    },
  );
}

class AIChartSeries {
  const AIChartSeries({required this.name, required this.values});
  final String name;
  final List<double> values;

  factory AIChartSeries.fromJson(Map<String, dynamic> json) => AIChartSeries(
    name: json['name'] as String? ?? '',
    values: (json['values'] as List? ?? const [])
        .map((v) => (v as num?)?.toDouble() ?? 0)
        .toList(),
  );
}

class AIChartData {
  const AIChartData({
    required this.kind,
    required this.title,
    required this.unit,
    required this.labels,
    required this.series,
  });

  /// bar, line or pie.
  final String kind;
  final String title;
  final String unit;
  final List<String> labels;
  final List<AIChartSeries> series;

  factory AIChartData.fromJson(Map<String, dynamic> json) => AIChartData(
    kind: json['kind'] as String? ?? 'bar',
    title: json['title'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    labels: (json['labels'] as List? ?? const [])
        .map((l) => l.toString())
        .toList(),
    series: _maps(json['series']).map(AIChartSeries.fromJson).toList(),
  );

  /// Spoken summary for screen readers.
  String get description {
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    final parts = [
      for (var i = 0; i < labels.length; i++)
        '${labels[i]} ${series.map((s) => i < s.values.length ? fmt(s.values[i]) : '0').join(' / ')}',
    ];
    return '$title: ${parts.join(', ')}${unit.isEmpty ? '' : ' ($unit)'}';
  }
}

/// A picture or chart in a reply.
class AIAttachment {
  const AIAttachment({
    required this.type,
    this.style = '',
    this.url = '',
    this.alt = '',
    this.width = 0,
    this.height = 0,
    this.chart,
  });

  /// image or chart.
  final String type;
  final String style;
  final String url;
  final String alt;
  final int width;
  final int height;
  final AIChartData? chart;

  factory AIAttachment.fromJson(Map<String, dynamic> json) => AIAttachment(
    type: json['type'] as String? ?? '',
    style: json['style'] as String? ?? '',
    url: json['url'] as String? ?? '',
    alt: json['alt'] as String? ?? '',
    width: _int(json['width']),
    height: _int(json['height']),
    chart: json['chart'] is Map<String, dynamic>
        ? AIChartData.fromJson(json['chart'] as Map<String, dynamic>)
        : null,
  );
}

class AIMessage {
  const AIMessage({
    required this.id,
    required this.role,
    required this.content,
    this.voice = false,
    this.citations = const [],
    this.attachments = const [],
    this.units = 0,
  });

  final String id;

  /// user or assistant.
  final String role;
  final String content;
  final bool voice;
  final List<IdeaCard> citations;
  final List<AIAttachment> attachments;
  final int units;

  bool get isUser => role == 'user';

  factory AIMessage.fromJson(Map<String, dynamic> json) => AIMessage(
    id: json['id'] as String? ?? '',
    role: json['role'] as String? ?? 'assistant',
    content: json['content'] as String? ?? '',
    voice: json['voice'] == true,
    citations: parseCards(json['citations']),
    attachments: _maps(json['attachments']).map(AIAttachment.fromJson).toList(),
    units: _int(json['units']),
  );

  AIMessage withUnits(int units) => AIMessage(
    id: id,
    role: role,
    content: content,
    voice: voice,
    citations: citations,
    attachments: attachments,
    units: units,
  );
}

class AIConversation {
  const AIConversation({required this.id, required this.title});
  final String id;
  final String title;

  factory AIConversation.fromJson(Map<String, dynamic> json) => AIConversation(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
  );
}

/// The result of sending a message: both sides of the exchange and the new balance.
class AITurn {
  const AITurn({
    required this.conversation,
    required this.userMessage,
    required this.message,
    required this.wallet,
    this.transcript,
  });

  final AIConversation conversation;
  final AIMessage userMessage;
  final AIMessage message;
  final AIWallet wallet;
  final String? transcript;

  factory AITurn.fromJson(Map<String, dynamic> json) => AITurn(
    conversation: AIConversation.fromJson(
      json['conversation'] as Map<String, dynamic>? ?? const {},
    ),
    userMessage: AIMessage.fromJson(
      json['user_message'] as Map<String, dynamic>? ?? const {},
    ),
    message: AIMessage.fromJson(
      json['message'] as Map<String, dynamic>? ?? const {},
    ),
    wallet: AIWallet.fromJson(
      json['wallet'] as Map<String, dynamic>? ?? const {},
    ),
    transcript: json['transcript'] as String?,
  );
}

class AISpeech {
  const AISpeech({
    required this.url,
    required this.units,
    required this.wallet,
  });
  final String url;
  final int units;
  final AIWallet wallet;

  factory AISpeech.fromJson(Map<String, dynamic> json) => AISpeech(
    url: json['url'] as String? ?? '',
    units: _int(json['units']),
    wallet: AIWallet.fromJson(
      json['wallet'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

class AITopUp {
  const AITopUp({required this.id, required this.units, required this.status});
  final String id;
  final int units;
  final String status;

  factory AITopUp.fromJson(Map<String, dynamic> json) => AITopUp(
    id: json['id'] as String? ?? '',
    units: _int(json['units']),
    status: json['status'] as String? ?? '',
  );
}
