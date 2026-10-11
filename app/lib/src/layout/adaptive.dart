import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Material 3 window size classes, by window width.
///
/// - compact: under 600 (phones in portrait)
/// - medium: 600 to 839 (tablets in portrait, foldables, phones in landscape)
/// - expanded: 840 to 1199 (tablets in landscape, small laptops)
/// - large: 1200 and up (desktops, big tablets in landscape)
enum WindowSize {
  compact,
  medium,
  expanded,
  large;

  static const mediumMin = 600.0;
  static const expandedMin = 840.0;
  static const largeMin = 1200.0;

  static WindowSize forWidth(double width) {
    if (width >= largeMin) return large;
    if (width >= expandedMin) return expanded;
    if (width >= mediumMin) return medium;
    return compact;
  }

  static WindowSize of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == compact;

  /// Expanded or large: room for a list and its detail side by side.
  bool get isTwoPane => index >= expanded.index;
}

/// The item selected in a list/detail screen (e.g. the post open on the
/// right of Discover on a landscape tablet), keyed by screen.
class PaneSelection extends Notifier<Object?> {
  PaneSelection(this.scope);
  final String scope;

  @override
  Object? build() => null;

  void select(Object? value) => state = value;
}

final paneSelectionProvider =
    NotifierProvider.family<PaneSelection, Object?, String>(PaneSelection.new);

/// A list on the left and the selected item on the right. Used on expanded
/// and large windows; compact and medium windows show the list alone and
/// push the detail as its own screen.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.list,
    required this.detail,
    this.listWidth = 400,
  });

  final Widget list;

  /// The selected item, or a placeholder when nothing is selected.
  final Widget detail;
  final double listWidth;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('two-pane'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(width: listWidth, child: list),
      const VerticalDivider(width: 1),
      Expanded(child: detail),
    ],
  );
}

/// Hosts a detail screen (which has its own app bar) in the right pane.
/// It gets its own navigator so its app bar shows no back button: the list
/// stays on screen, so there's nothing to go back to.
class DetailPane extends StatelessWidget {
  const DetailPane({super.key, required this.id, required this.child});

  /// Changing it replaces the page (a new selection).
  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => HeroControllerScope.none(
    child: Navigator(
      key: ValueKey('detail-pane-$id'),
      pages: [MaterialPage<void>(key: ValueKey(id), child: child)],
      onDidRemovePage: (_) {},
    ),
  );
}

/// The right pane before anything is picked.
class EmptyDetail extends StatelessWidget {
  const EmptyDetail({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ColoredBox(
      key: const ValueKey('empty-detail'),
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: muted),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// On expanded and large windows: [list] beside the [selected] item's
/// detail (or [empty]); otherwise [list] alone.
class ListDetail extends StatelessWidget {
  const ListDetail({
    super.key,
    required this.list,
    required this.selectedId,
    required this.detail,
    required this.empty,
  });

  final Widget list;
  final String? selectedId;
  final Widget Function() detail;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (!WindowSize.of(context).isTwoPane) return list;
    final id = selectedId;
    return TwoPane(
      list: list,
      detail: id == null ? empty : DetailPane(id: id, child: detail()),
    );
  }
}
