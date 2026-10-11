import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/ai_models.dart';
import '../../api/api_client.dart';
import '../../data/providers.dart';
import 'topup_service.dart';

class AIChatState {
  const AIChatState({
    this.conversationId,
    this.messages = const [],
    this.sending = false,
    this.pending,
    this.error,
    this.outOfUnits = false,
    this.wallet,
    this.speech = const {},
  });

  final String? conversationId;
  final List<AIMessage> messages;
  final bool sending;

  /// What the member just sent, shown until the reply arrives. For a voice
  /// message it is empty until the server returns the transcript.
  final String? pending;
  final String? error;
  final bool outOfUnits;

  /// The newest balance from a reply; null until the first one.
  final AIWallet? wallet;

  /// Audio of replies read aloud, by message id.
  final Map<String, String> speech;

  AIChatState copyWith({
    String? conversationId,
    List<AIMessage>? messages,
    bool? sending,
    String? Function()? pending,
    String? Function()? error,
    bool? outOfUnits,
    AIWallet? wallet,
    Map<String, String>? speech,
  }) => AIChatState(
    conversationId: conversationId ?? this.conversationId,
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    pending: pending == null ? this.pending : pending(),
    error: error == null ? this.error : error(),
    outOfUnits: outOfUnits ?? this.outOfUnits,
    wallet: wallet ?? this.wallet,
    speech: speech ?? this.speech,
  );
}

class AIChatController extends Notifier<AIChatState> {
  @override
  AIChatState build() {
    // A new account starts a new chat.
    ref.watch(sessionProvider.select((s) => s.token));
    return const AIChatState();
  }

  /// Sends [text]. On failure returns it so the input can be restored.
  Future<String?> send(String text) async {
    final content = text.trim();
    if (content.isEmpty || state.sending) return null;
    state = state.copyWith(
      sending: true,
      pending: () => content,
      error: () => null,
      outOfUnits: false,
    );
    try {
      final turn = await ref
          .read(repositoryProvider)
          .aiChat(content, conversationId: state.conversationId);
      _apply(turn);
      return null;
    } catch (e) {
      _fail(e);
      return content;
    }
  }

  /// Sends a recorded voice message (WAV).
  Future<void> sendVoice(Uint8List wav) async {
    if (state.sending) return;
    state = state.copyWith(
      sending: true,
      pending: () => '',
      error: () => null,
      outOfUnits: false,
    );
    try {
      final turn = await ref
          .read(repositoryProvider)
          .aiVoice(wav, 'voice.wav', conversationId: state.conversationId);
      _apply(turn);
    } catch (e) {
      _fail(e);
    }
  }

  /// Reads a reply aloud; returns the audio URL, or null on failure.
  Future<String?> speak(String messageId) async {
    final known = state.speech[messageId];
    if (known != null) return known;
    try {
      final s = await ref.read(repositoryProvider).aiSpeech(messageId);
      state = state.copyWith(
        wallet: s.wallet,
        speech: {...state.speech, messageId: s.url},
      );
      return s.url;
    } catch (e) {
      _fail(e, keepSending: true);
      return null;
    }
  }

  Future<void> open(AIConversation c) async {
    state = AIChatState(
      conversationId: c.id,
      sending: true,
      wallet: state.wallet,
    );
    try {
      final messages = await ref.read(repositoryProvider).aiConversation(c.id);
      state = state.copyWith(messages: messages, sending: false);
    } catch (e) {
      _fail(e);
    }
  }

  void newChat() => state = AIChatState(wallet: state.wallet);

  Future<void> delete(String id) async {
    await ref.read(repositoryProvider).deleteAIConversation(id);
    if (state.conversationId == id) newChat();
  }

  void dismissError() =>
      state = state.copyWith(error: () => null, outOfUnits: false);

  void _apply(AITurn turn) {
    state = state.copyWith(
      conversationId: turn.conversation.id,
      messages: [...state.messages, turn.userMessage, turn.message],
      sending: false,
      pending: () => null,
      wallet: turn.wallet,
    );
  }

  void _fail(Object e, {bool keepSending = false}) {
    final out = e is ApiException && e.code == 'out_of_units';
    if (out || (e is ApiException && e.code == 'premium_required')) {
      ref.invalidate(aiStatusProvider);
    }
    state = state.copyWith(
      sending: keepSending ? state.sending : false,
      pending: keepSending ? null : () => null,
      error: () => out ? null : message(e),
      outOfUnits: out,
    );
  }

  static String message(Object e) {
    if (e is ApiException) {
      if (e.isNetwork) return "You're offline. Reborn AI needs a connection.";
      if (e.isRateLimited) {
        return "You've sent a lot this hour. Try again a bit later.";
      }
      if (e.code == 'premium_required') {
        return 'Reborn AI is part of Reborn Premium.';
      }
      if (e.statusCode == 503 || e.code == 'ai_unavailable') {
        return 'Reborn AI is unavailable right now. Please try again soon.';
      }
      return e.message;
    }
    return 'Something went wrong.';
  }
}

final aiChatProvider = NotifierProvider<AIChatController, AIChatState>(
  AIChatController.new,
);

/// The member's earlier chats, newest first.
final aiConversationsProvider =
    FutureProvider.autoDispose<List<AIConversation>>((ref) {
      ref.watch(sessionProvider.select((s) => s.token));
      return ref.watch(repositoryProvider).aiConversations();
    });
