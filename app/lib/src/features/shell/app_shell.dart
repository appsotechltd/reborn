import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../layout/adaptive.dart';
import '../../theme.dart';
import '../../tv/tv_mode.dart';
import '../listen/listen_ui.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Dest('Home', Icons.home_outlined, Icons.home),
  _Dest('Discover', Icons.explore_outlined, Icons.explore),
  _Dest('Collections', Icons.bookmarks_outlined, Icons.bookmarks),
  _Dest('Review', Icons.refresh_outlined, Icons.refresh),
  _Dest('Ask', Icons.forum_outlined, Icons.forum),
];

/// Bottom navigation on phones (compact windows), a navigation rail from
/// medium windows (tablets) up, and a big focusable rail on TV.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  void _go(int i) => navigationShell.goBranch(
    i,
    initialLocation: i == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tv = ref.watch(isTvProvider);
    if (tv) return _TvShell(navigationShell: navigationShell, go: _go);
    final wide = !WindowSize.of(context).isCompact;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              key: const ValueKey('rail'),
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Icon(
                  Icons.auto_stories,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: navigationShell),
                  const ListenMiniPlayer(),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: navigationShell,
      // The Listen mini-player docks above the tabs while Listen mode is on.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListenMiniPlayer(),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _go,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lets TV content hand focus to the navigation rail (each tab's pages
/// live in their own navigator, so the arrows can't cross on their own).
class TvNav extends InheritedWidget {
  const TvNav({super.key, required this.focusRail, required super.child});

  final VoidCallback focusRail;

  static TvNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvNav>();

  @override
  bool updateShouldNotify(TvNav old) => false;
}

/// The TV shell: a rail of tabs (and Settings) on the left, the tab on the
/// right. Right from the rail goes into the tab (back to where focus was);
/// left from the tab's left edge comes back to the rail.
class _TvShell extends StatefulWidget {
  const _TvShell({required this.navigationShell, required this.go});
  final StatefulNavigationShell navigationShell;
  final void Function(int) go;

  @override
  State<_TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<_TvShell> {
  final _rail = FocusScopeNode(debugLabel: 'tv-rail');
  final _content = FocusScopeNode(debugLabel: 'tv-content');

  @override
  void dispose() {
    _rail.dispose();
    _content.dispose();
    super.dispose();
  }

  static bool _active(FocusNode n) {
    final c = n.context;
    return c != null && c.mounted && TickerMode.valuesOf(c).enabled;
  }

  void _focusRail() {
    final items = _rail.traversalDescendants.toList();
    if (items.isEmpty) return;
    final i = widget.navigationShell.currentIndex;
    items[i.clamp(0, items.length - 1)].requestFocus();
  }

  /// The rail's items, top to bottom (tabs, then Settings).
  List<FocusNode> get _railItems {
    final items = _rail.traversalDescendants
        .where((n) => n is! FocusScopeNode && n.canRequestFocus)
        .toList();
    items.sort((a, b) => a.rect.top.compareTo(b.rect.top));
    return items;
  }

  void _moveInRail(int step) {
    final items = _railItems;
    if (items.isEmpty) return;
    final at = items.indexOf(FocusManager.instance.primaryFocus!);
    final next = at < 0
        ? widget.navigationShell.currentIndex
        : (at + step).clamp(0, items.length - 1);
    items[next].requestFocus();
  }

  /// Whether [n] belongs to a tab's app bar (search, bell, avatar): those
  /// are reached with Up from the content, not by entering the tab.
  static bool _inAppBar(FocusNode n) =>
      n.context?.findAncestorWidgetOfExactType<AppBar>() != null;

  void _focusContent() {
    _content.requestFocus();
    final now = FocusManager.instance.primaryFocus;
    // Back to the item this tab last had, if there was one (a page's focus
    // scope is not an item: nothing would show focus).
    if (now != null &&
        now is! FocusScopeNode &&
        _active(now) &&
        !_inAppBar(now)) {
      return;
    }
    // Nothing to go back to in this tab: its top-left item.
    final candidates = _content.traversalDescendants
        .where(
          (n) =>
              n is! FocusScopeNode &&
              _active(n) &&
              !n.rect.isEmpty &&
              !_inAppBar(n),
        )
        .toList();
    if (candidates.isEmpty) {
      // Nothing to land on yet: keep focus visible on the rail.
      _focusRail();
      return;
    }
    candidates.sort((a, b) {
      final dy = a.rect.top.compareTo(b.rect.top);
      return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
    });
    candidates.first.requestFocus();
  }

  bool _down(KeyEvent e) => e is KeyDownEvent || e is KeyRepeatEvent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Focus(
            skipTraversal: true,
            canRequestFocus: false,
            onKeyEvent: (_, e) {
              if (!_down(e)) return KeyEventResult.ignored;
              final key = e.logicalKey;
              if (key == LogicalKeyboardKey.arrowRight) {
                _focusContent();
                return KeyEventResult.handled;
              }
              // Up and Down walk the rail and stop at its ends: they never
              // jump out to the tab's app bar. Left has nowhere to go.
              if (key == LogicalKeyboardKey.arrowDown ||
                  key == LogicalKeyboardKey.arrowUp) {
                _moveInRail(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: FocusScope(
              node: _rail,
              child: NavigationRail(
                key: const ValueKey('tv-rail'),
                selectedIndex: widget.navigationShell.currentIndex,
                onDestinationSelected: (i) {
                  widget.go(i);
                  // Straight into the tab, ready for the arrows.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _focusContent();
                    // A newly shown tab's page can claim focus for its own
                    // scope a frame later, which shows nothing: try again.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted &&
                          FocusManager.instance.primaryFocus
                              is FocusScopeNode) {
                        _focusContent();
                      }
                    });
                  });
                },
                labelType: NavigationRailLabelType.all,
                groupAlignment: 0,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Icon(
                    Icons.auto_stories,
                    color: CandlelightTokens.amber,
                  ),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: IconButton(
                    key: const ValueKey('tv-settings'),
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Focus(
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: (_, e) {
                if (!_down(e) || e.logicalKey != LogicalKeyboardKey.arrowLeft) {
                  return KeyEventResult.ignored;
                }
                final focus = FocusManager.instance.primaryFocus;
                // From a real item, move left within the tab, but only if
                // focus really ends up further left; otherwise (or from no
                // item at all) go to the rail. Left never moves right.
                if (focus != null && focus is! FocusScopeNode) {
                  final from = focus.rect.center.dx;
                  if (focus.focusInDirection(TraversalDirection.left)) {
                    final to = FocusManager.instance.primaryFocus;
                    if (to != null &&
                        to is! FocusScopeNode &&
                        to.rect.center.dx < from) {
                      return KeyEventResult.handled;
                    }
                  }
                }
                _focusRail();
                return KeyEventResult.handled;
              },
              child: FocusScope(
                node: _content,
                child: TvNav(
                  focusRail: _focusRail,
                  child: widget.navigationShell,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
