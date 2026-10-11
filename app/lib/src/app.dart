import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'router.dart';
import 'theme.dart';
import 'widgets/common.dart';

class RebornApp extends ConsumerWidget {
  const RebornApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Reborn',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          _OfflineFrame(child: child ?? const SizedBox()),
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
