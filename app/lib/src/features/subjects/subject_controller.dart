import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../summary/summary_controller.dart';

/// The subjects in a topic ('' for every subject). Re-fetched on
/// sign-in/out: the reader's progress is personal.
final subjectsProvider = FutureProvider.autoDispose
    .family<Fetched<List<Subject>>, String>((ref, topic) {
      ref.watch(sessionProvider.select((s) => s.token));
      return ref.watch(repositoryProvider).subjects(topic);
    });

/// A subject and its guides in order.
final subjectProvider = FutureProvider.autoDispose
    .family<Fetched<SubjectDetail>, String>((ref, id) {
      ref.watch(sessionProvider.select((s) => s.token));
      return ref.watch(repositoryProvider).subject(id);
    });

/// Where the reader is in each guide of a subject: the account's place or
/// this device's, whichever is further (see [bestProgress]).
List<SummaryProgress?> guideProgress(
  List<Summary> guides,
  Map<String, SummaryProgress> local,
) => [for (final g in guides) bestProgress(g.viewer, local[g.id])];

/// The guide to read next: the first one not finished, or null when every
/// guide is.
int? nextGuide(List<SummaryProgress?> progress) {
  final i = progress.indexWhere((p) => !(p?.finished ?? false));
  return i < 0 ? null : i;
}
