import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'router.dart';
import 'theme.dart';
import 'tv/tv_mode.dart';
import 'widgets/common.dart';

class RebornApp extends ConsumerWidget {
  const RebornApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tv = ref.watch(isTvProvider);
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Reborn',
      debugShowCheckedModeBanner: false,
      theme: tv ? tvTheme(lightTheme) : lightTheme,
      darkTheme: tv ? tvTheme(darkTheme) : darkTheme,
      // TVs are dark rooms: dark unless the reader picked Light.
      themeMode: tv && mode == ThemeMode.system ? ThemeMode.dark : mode,
      routerConfig: router,
      shortcuts: tv ? tvShortcuts() : null,
      actions: tv
          ? {
              ...WidgetsApp.defaultActions,
              TvBackIntent: TvBackAction(() {
                if (router.canPop()) router.pop();
              }),
            }
          : null,
      builder: (context, child) {
        final frame = _OfflineFrame(child: child ?? const SizedBox());
        return tv ? _TvFrame(child: frame) : frame;
      },
    );
  }
}

/// The 10-foot frame: bigger type, content kept inside the overscan-safe
/// area, and an amber ring on whatever the remote has focused.
class _TvFrame extends StatelessWidget {
  const _TvFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = tvOverscan(mq.size);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: TvFocusRing(
        child: Padding(
          padding: inset,
          child: MediaQuery(
            data: mq.copyWith(
              size: inset.deflateSize(mq.size),
              textScaler: TextScaler.linear(tvTextScale(mq.size)),
              navigationMode: NavigationMode.directional,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Shows the Offline banner above every screen while cached data is served.
class _OfflineFrame extends ConsumerWidget {
  const _OfflineFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider);
    if (!offline) return child;
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
