import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../data/providers.dart';

class AskEntry {
  const AskEntry(this.message, [this.citations = const []]);
  final ChatMessage message;
  final List<IdeaCard> citations;
}

class AskState {
  const AskState({this.entries = const [], this.sending = false, this.error});
  final List<AskEntry> entries;
  final bool sending;
  final String? error;
}

class AskController extends Notifier<AskState> {
  @override
  AskState build() {
    // A new account starts a new conversation.
    ref.watch(sessionProvider.select((s) => s.token));
    return const AskState();
  }

  /// Sends [text] with the full history. On failure the message is removed
  /// and returned so the input can be restored.
  Future<String?> send(String text) async {
    final content = text.trim();
    if (content.isEmpty || state.sending) return null;
    final entries = [
      ...state.entries,
      AskEntry(ChatMessage(role: 'user', content: content)),
    ];
    state = AskState(entries: entries, sending: true);
    try {
      final reply = await ref
          .read(repositoryProvider)
          .chat(entries.map((e) => e.message).toList());
      state = AskState(
        entries: [
          ...entries,
          AskEntry(
            ChatMessage(role: 'assistant', content: reply.reply),
            reply.citations,
          ),
        ],
      );
      return null;
    } catch (e) {
      state = AskState(
        entries: state.entries.sublist(0, entries.length - 1),
        error: _message(e),
      );
      return content;
    }
  }

  void clear() => state = const AskState();

  static String _message(Object e) {
    if (e is ApiException) {
      if (e.isNetwork) return "You're offline. Ask needs a connection.";
      if (e.isRateLimited) {
        return "You've reached this hour's limit for questions. Try again a bit later.";
      }
      if (e.statusCode == 503 || e.code == 'agent_unavailable') {
        return 'Ask is unavailable right now. Browse or search the library in the meantime.';
      }
      return e.message;
    }
    return 'Something went wrong.';
  }
}

final askProvider = NotifierProvider<AskController, AskState>(
  AskController.new,
);
