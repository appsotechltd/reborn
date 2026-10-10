import '../../api/models.dart';

/// A piece of an agent reply: plain text or a citation of a card.
sealed class ReplySegment {
  const ReplySegment();
}

class TextSegment extends ReplySegment {
  const TextSegment(this.text);
  final String text;
}

class CitationSegment extends ReplySegment {
  const CitationSegment(this.card);
  final IdeaCard card;
}

final _citation = RegExp(r'\[([^\[\]\s]+)\]');

/// Splits [reply] into text and citations. Only `[id]` markers whose id is in
/// [citations] become citations; anything else stays as text.
List<ReplySegment> parseReply(String reply, List<IdeaCard> citations) {
  final byId = {for (final c in citations) c.id: c};
  final out = <ReplySegment>[];
  var last = 0;
  for (final m in _citation.allMatches(reply)) {
    final card = byId[m.group(1)];
    if (card == null) continue;
    if (m.start > last) out.add(TextSegment(reply.substring(last, m.start)));
    out.add(CitationSegment(card));
    last = m.end;
  }
  if (last < reply.length) out.add(TextSegment(reply.substring(last)));
  return out;
}
