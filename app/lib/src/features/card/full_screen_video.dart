import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Text and icons on films are white-ish whatever the app's mode.
const kFilmInk = Color(0xFFFFFFFF);

/// A small round control on a film (mute, pause, full screen): dark glass,
/// white icon.
class FilmButton extends StatelessWidget {
  const FilmButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    color: kFilmInk,
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xB314110E),
      minimumSize: const Size(40, 40),
      fixedSize: const Size(40, 40),
      padding: EdgeInsets.zero,
    ),
  );
}

/// The full-screen button on a playing film.
class FullScreenButton extends StatelessWidget {
  const FullScreenButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilmButton(
    key: const ValueKey('video-fullscreen'),
    tooltip: 'Full screen',
    icon: Icons.fullscreen_rounded,
    onPressed: onPressed,
  );
}

/// Shows a film on a black screen of its own, with the system bars hidden
/// (they come back with a swipe), and a button to leave. The phone can be
/// turned for landscape films. Resolves when the reader leaves.
Future<void> showFullScreenVideo(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, _, _) => _FullScreenPage(builder: builder),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _FullScreenPage extends StatefulWidget {
  const _FullScreenPage({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_FullScreenPage> createState() => _FullScreenPageState();
}

class _FullScreenPageState extends State<_FullScreenPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('video-fullscreen-page'),
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(child: Center(child: widget.builder(context))),
        Positioned(
          left: 8,
          top: 8,
          child: SafeArea(
            child: FilmButton(
              key: const ValueKey('video-exit-fullscreen'),
              tooltip: 'Exit full screen',
              icon: Icons.fullscreen_exit_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ],
    ),
  );
}
