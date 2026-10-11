import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../theme.dart';

/// Forces the TV layout on or off at build time:
/// `--dart-define=REBORN_TV=1` (or `0`). Empty means "detect".
const _tvDefine = String.fromEnvironment('REBORN_TV');

/// The build-time or URL override, if any: `REBORN_TV`, or `?tv=1` / `?tv=0`
/// on the web, so the TV layout can be previewed in a browser.
bool? tvOverrideFromEnvironment([Uri? url]) {
  bool? parse(String? v) => switch (v) {
    '1' || 'true' || 'on' => true,
    '0' || 'false' || 'off' => false,
    _ => null,
  };
  final define = parse(_tvDefine);
  if (define != null) return define;
  if (kIsWeb || url != null) {
    return parse((url ?? Uri.base).queryParameters['tv']);
  }
  return null;
}

const _deviceChannel = MethodChannel('reborn/device');

/// True on an Android TV (leanback / television UI mode). The override
/// wins; elsewhere, and if the check fails, false.
Future<bool> detectTv() async {
  final forced = tvOverrideFromEnvironment();
  if (forced != null) return forced;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await _deviceChannel.invokeMethod<bool>('isTv') ?? false;
  } catch (_) {
    return false;
  }
}

/// What the device reported at start-up (see [detectTv]); overridden in
/// `main()`.
final tvDetectedProvider = Provider<bool>((_) => false);

/// The reader's TV layout choice in Settings.
enum TvLayout { auto, on, off }

class TvLayoutController extends Notifier<TvLayout> {
  static const prefsKey = 'appearance.tv_layout';

  @override
  TvLayout build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(prefsKey);
    return TvLayout.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => TvLayout.auto,
    );
  }

  Future<void> set(TvLayout mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == TvLayout.auto) {
      await prefs.remove(prefsKey);
    } else {
      await prefs.setString(prefsKey, mode.name);
    }
  }
}

final tvLayoutProvider = NotifierProvider<TvLayoutController, TvLayout>(
  TvLayoutController.new,
);

/// Whether the 10-foot TV layout is on.
final isTvProvider = Provider<bool>(
  (ref) => switch (ref.watch(tvLayoutProvider)) {
    TvLayout.on => true,
    TvLayout.off => false,
    TvLayout.auto => ref.watch(tvDetectedProvider),
  },
);

/// Text scale on TV: 1.25 at the usual 960x540 dp of a 1080p TV, growing
/// to 1.5 on screens that report more room (a 1920-wide browser preview).
double tvTextScale(Size size) =>
    (1.25 * size.shortestSide / 540).clamp(1.25, 1.5);

/// Overscan-safe inset: 5% of each side, per the Android TV guidelines.
EdgeInsets tvOverscan(Size size) => EdgeInsets.symmetric(
  horizontal: size.width * 0.05,
  vertical: size.height * 0.05,
);

/// Back on the remote (or Escape / browser back on a keyboard).
class TvBackIntent extends Intent {
  const TvBackIntent();
}

/// Remote and keyboard keys on TV: the arrows move focus (also on the web,
/// where they'd scroll by default), Select / Enter activate, Back goes back.
Map<ShortcutActivator, Intent> tvShortcuts() {
  final tv = <LogicalKeyboardKey, Intent>{
    LogicalKeyboardKey.arrowUp: const DirectionalFocusIntent(
      TraversalDirection.up,
    ),
    LogicalKeyboardKey.arrowDown: const DirectionalFocusIntent(
      TraversalDirection.down,
    ),
    LogicalKeyboardKey.arrowLeft: const DirectionalFocusIntent(
      TraversalDirection.left,
    ),
    LogicalKeyboardKey.arrowRight: const DirectionalFocusIntent(
      TraversalDirection.right,
    ),
    for (final key in const [
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.mediaPlayPause,
    ])
      key: const ActivateIntent(),
    for (final key in const [
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.goBack,
      LogicalKeyboardKey.browserBack,
      LogicalKeyboardKey.gameButtonB,
    ])
      key: const TvBackIntent(),
  };
  // Activators don't compare equal, so drop the defaults for these keys
  // rather than adding a second, shadowed entry.
  bool replaced(ShortcutActivator a) =>
      a is SingleActivator &&
      !a.control &&
      !a.shift &&
      !a.alt &&
      !a.meta &&
      tv.containsKey(a.trigger);
  return {
    for (final e in WidgetsApp.defaultShortcuts.entries)
      if (!replaced(e.key)) e.key: e.value,
    for (final e in tv.entries) SingleActivator(e.key): e.value,
  };
}

/// Back: closes the innermost dialog, menu or page that can close.
class TvBackAction extends Action<TvBackIntent> {
  TvBackAction(this.fallback);

  /// Used when nothing near the focus can pop (e.g. the router).
  final VoidCallback fallback;

  @override
  Object? invoke(TvBackIntent intent) {
    final context = FocusManager.instance.primaryFocus?.context;
    final nav = context == null ? null : Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.maybePop();
    } else {
      fallback();
    }
    return null;
  }
}

/// Marks a widget that draws its own focus highlight, so [TvFocusRing]
/// leaves it alone.
class OwnFocusHighlight {
  static final _nodes = Expando<bool>('own focus highlight');
  static void mark(FocusNode node) => _nodes[node] = true;
  static bool has(FocusNode node) => _nodes[node] ?? false;
}

/// Draws an amber ring around whatever has focus, for every focusable
/// element (buttons, list rows, chips, the navigation rail), so it's
/// always clear where the remote is. Follows the focus as it scrolls.
class TvFocusRing extends StatefulWidget {
  const TvFocusRing({super.key, required this.child});
  final Widget child;

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing> {
  Rect? _rect;
  final _key = GlobalKey();

  /// Frames left to re-measure after something moved (a focus change, a
  /// scroll, a page transition). Bounded, so the app can go idle.
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_poke);
    _poke();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_poke);
    super.dispose();
  }

  void _poke() {
    final idle = _frames == 0;
    _frames = 40;
    if (idle) _tick();
  }

  void _tick() {
    if (!mounted || _frames == 0) return;
    _frames--;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _check();
      _tick();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _check() {
    if (!mounted) return;
    Rect? next;
    final node = FocusManager.instance.primaryFocus;
    final box = _key.currentContext?.findRenderObject();
    if (node != null &&
        node is! FocusScopeNode &&
        node.context != null &&
        node.context!.mounted &&
        !OwnFocusHighlight.has(node) &&
        box is RenderBox &&
        box.hasSize) {
      final r = node.rect;
      final area = box.size.width * box.size.height;
      // Not for big containers that only hold focus (a page, a list).
      if (r.width * r.height < area * 0.5 && !r.isEmpty) {
        final origin = box.localToGlobal(Offset.zero);
        next = r.shift(-origin);
      }
    }
    if (next != _rect) setState(() => _rect = next);
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Stack(
      key: _key,
      children: [
        NotificationListener<Notification>(
          onNotification: (n) {
            if (n is ScrollNotification || n is SizeChangedLayoutNotification) {
              _poke();
            }
            return false;
          },
          child: widget.child,
        ),
        if (rect != null)
          Positioned.fromRect(
            rect: rect.inflate(4),
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('tv-focus-ring'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CandlelightTokens.amber, width: 3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The theme on TV: an amber focus wash on every Material control (the
/// ring is drawn by [TvFocusRing]).
ThemeData tvTheme(ThemeData base) => base.copyWith(
  focusColor: CandlelightTokens.amber.withValues(alpha: 0.22),
  visualDensity: VisualDensity.standard,
);
