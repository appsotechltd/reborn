import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';

/// A summary and its parts (kept for reading offline). Re-fetched on
/// sign-in/out: the reader's place is personal.
final summaryProvider = FutureProvider.autoDispose
    .family<Fetched<SummaryDetail>, String>((ref, id) {
      ref.watch(sessionProvider.select((s) => s.token));
      return ref.watch(repositoryProvider).summary(id);
    });

/// Every summary: topic summaries first, then books by title.
final summariesProvider = FutureProvider.autoDispose<Fetched<SummaryPage>>((
  ref,
) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).summaries();
});

/// This device's place in each summary, so a signed-out reader (or one
/// offline) picks up where they stopped. Signed in, the place is also saved
/// to the account.
class SummaryPlaces extends Notifier<Map<String, SummaryProgress>> {
  static const prefsKey = 'summary.places';

  @override
  Map<String, SummaryProgress> build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(prefsKey);
    if (raw == null) return const {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const {};
      return {
        for (final e in json.entries)
          if (e.value is Map<String, dynamic>)
            e.key: SummaryProgress.fromJson(e.value as Map<String, dynamic>),
      };
    } on FormatException {
      return const {};
    }
  }

  /// Keeps the place; finishing sticks, so rereading a part doesn't undo it.
  Future<void> save(String id, int position, {bool finished = false}) async {
    final p = SummaryProgress(
      started: true,
      position: position,
      finished: finished || (state[id]?.finished ?? false),
    );
    state = {...state, id: p};
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          prefsKey,
          jsonEncode({for (final e in state.entries) e.key: e.value.toJson()}),
        );
    if (ref.read(sessionProvider).signedIn) {
      await ref
          .read(repositoryProvider)
          .setSummaryProgress(id, position, finished: finished);
    }
  }
}

final summaryPlacesProvider =
    NotifierProvider<SummaryPlaces, Map<String, SummaryProgress>>(
      SummaryPlaces.new,
    );

/// The place we know of: the account's when it has one, else this device's.
SummaryProgress? bestProgress(SummaryProgress? server, SummaryProgress? local) {
  if (server != null && server.started) {
    // This device may be further along than the copy the feed was given.
    if (local != null && local.started && !server.finished) {
      return local.finished || local.position > server.position
          ? local
          : server;
    }
    return server;
  }
  return local;
}
