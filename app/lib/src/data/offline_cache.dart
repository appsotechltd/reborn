import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// JSON cache in shared_preferences (works on web and mobile).
///
/// Keys are namespaced under `cache.` so they can be cleared together.
class OfflineCache {
  OfflineCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'cache.';

  static String feedKey(List<String>? topics, String? cursor) =>
      'feed.${(topics == null || topics.isEmpty) ? '_' : ([...topics]..sort()).join(',')}.${cursor ?? '_'}';
  static const dailyKey = 'daily';
  static const topicsKey = 'topics';
  static const stashesKey = 'stashes';
  static String stashKey(String id) => 'stash.$id';
  static String cardKey(String id) => 'card.$id';
  static String sourceKey(String id) => 'source.$id';
  static String timelineKey(List<String>? topics, String? cursor) =>
      'timeline.${(topics == null || topics.isEmpty) ? '_' : ([...topics]..sort()).join(',')}.${cursor ?? '_'}';
  static String postKey(String id) => 'post.$id';

  Future<void> write(String key, Object? json) =>
      _prefs.setString('$_prefix$key', jsonEncode(json));

  /// Returns the decoded JSON stored at [key], or null if missing/corrupt.
  dynamic read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> remove(String key) => _prefs.remove('$_prefix$key');

  Future<void> putCard(IdeaCard card) => write(cardKey(card.id), card.toJson());

  Future<void> putCards(Iterable<IdeaCard> cards) async {
    for (final c in cards) {
      await putCard(c);
    }
  }

  IdeaCard? getCard(String id) {
    final json = read(cardKey(id));
    return json is Map<String, dynamic> ? IdeaCard.fromJson(json) : null;
  }

  /// Removes everything cached for the signed-in user (stashes, and posts
  /// and timeline pages, which carry the user's reactions).
  Future<void> clearUserData() async {
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith('$_prefix$stashesKey') ||
          k.startsWith('${_prefix}stash.') ||
          k.startsWith('${_prefix}timeline.') ||
          k.startsWith('${_prefix}post.')) {
        await _prefs.remove(k);
      }
    }
  }
}
