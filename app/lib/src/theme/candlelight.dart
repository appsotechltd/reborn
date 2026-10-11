import 'package:flutter/material.dart';

/// Candlelight: Reborn's design tokens (chosen 2026-10-11), in dark and light.
///
/// Every colour the app uses comes from here, through [ThemeData] (built by
/// [buildCandlelightTheme]) or the [Candlelight] theme extension for the
/// extras Material has no slot for. Spec: design/candlelight.md.
@immutable
class CandlelightTokens {
  const CandlelightTokens({
    required this.brightness,
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.inset,
    required this.nav,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.ghostLine,
    required this.amberText,
    required this.react,
    required this.chipOnBg,
    required this.chipOnFg,
    required this.success,
    required this.danger,
    required this.amberContainer,
    required this.onAmberContainer,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.cardShadow,
  });

  final Brightness brightness;
  final Color bg;
  final Color card;
  final Color cardBorder;
  final Color inset;
  final Color nav;
  final Color ink;
  final Color ink2;
  final Color muted;
  final Color line;
  final Color ghostLine;

  /// Amber for text, tags and links. Never [amber] on a light background.
  final Color amberText;

  /// Active reaction icon and count.
  final Color react;
  final Color chipOnBg;
  final Color chipOnFg;
  final Color success;
  final Color danger;

  /// A soft amber wash for highlighted rows (today's idea, your messages).
  final Color amberContainer;
  final Color onAmberContainer;
  final Color dangerContainer;
  final Color onDangerContainer;
  final List<BoxShadow> cardShadow;

  /// Button fill, identical in both modes.
  static const amber = Color(0xFFE9A23B);
  static const onAmber = Color(0xFF1A1209);

  /// Quotes and avatars.
  static const oxblood = Color(0xFF9E3B2E);
  static const onOxblood = Color(0xFFF2E8D8);

  /// Films stay dark in both modes.
  static const videoBase = Color(0xFF14110E);
  static const videoFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.35, 1],
    colors: [Color(0x0014110E), Color(0xEB14110E)],
  );

  static const radiusCard = 18.0;
  static const radiusInset = 9.0;

  static const dark = CandlelightTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF14110E),
    card: Color(0xFF1F1A15),
    cardBorder: Color(0xFF3A3027),
    inset: Color(0xFF2A231C),
    nav: Color(0xFF14110E),
    ink: Color(0xFFF2E8D8),
    ink2: Color(0xFFD9CDBA),
    muted: Color(0xFFA89A86),
    line: Color(0xFF3A3027),
    ghostLine: Color(0xFF4A3E32),
    amberText: Color(0xFFE9A23B),
    react: Color(0xFFE9A23B),
    chipOnBg: Color(0xFFE9A23B),
    chipOnFg: Color(0xFF1A1209),
    success: Color(0xFF7FB36A),
    danger: Color(0xFFE0664F),
    amberContainer: Color(0xFF3A2B17),
    onAmberContainer: Color(0xFFF6DDB3),
    dangerContainer: Color(0xFF3D1E18),
    onDangerContainer: Color(0xFFF4C6BC),
    cardShadow: [],
  );

  static const light = CandlelightTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF1EFEA),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE4DED3),
    inset: Color(0xFFF6F2EA),
    nav: Color(0xFFFAF8F4),
    ink: Color(0xFF1C1814),
    ink2: Color(0xFF3A332B),
    muted: Color(0xFF6E6458),
    line: Color(0xFFDDD7CC),
    ghostLine: Color(0xFFCFC6B8),
    amberText: Color(0xFF9A5B0E),
    react: Color(0xFFC9821F),
    chipOnBg: Color(0xFF1C1814),
    chipOnFg: Color(0xFFF2E8D8),
    success: Color(0xFF3F7A3A),
    danger: Color(0xFFB3412F),
    amberContainer: Color(0xFFFBEBD0),
    onAmberContainer: Color(0xFF4A2D06),
    dangerContainer: Color(0xFFF7DDD7),
    onDangerContainer: Color(0xFF5C1A10),
    // CSS: 0 10px 24px -18px rgba(60,40,10,0.35)
    cardShadow: [
      BoxShadow(
        color: Color(0x593C280A),
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -18,
      ),
    ],
  );
}

/// Font families bundled in assets/fonts (SIL Open Font License).
const kDisplayFont = 'Fraunces';
const kBodyFont = 'Figtree';

/// Theme extension for Candlelight colours Material has no slot for.
@immutable
class Candlelight extends ThemeExtension<Candlelight> {
  const Candlelight({
    required this.inset,
    required this.muted,
    required this.ink2,
    required this.line,
    required this.amber,
    required this.onAmber,
    required this.amberText,
    required this.oxblood,
    required this.onOxblood,
    required this.react,
    required this.success,
    required this.cardShadow,
  });

  factory Candlelight.from(CandlelightTokens t) => Candlelight(
    inset: t.inset,
    muted: t.muted,
    ink2: t.ink2,
    line: t.line,
    amber: CandlelightTokens.amber,
    onAmber: CandlelightTokens.onAmber,
    amberText: t.amberText,
    oxblood: CandlelightTokens.oxblood,
    onOxblood: CandlelightTokens.onOxblood,
    react: t.react,
    success: t.success,
    cardShadow: t.cardShadow,
  );

  final Color inset;
  final Color muted;
  final Color ink2;
  final Color line;
  final Color amber;
  final Color onAmber;
  final Color amberText;
  final Color oxblood;
  final Color onOxblood;
  final Color react;
  final Color success;
  final List<BoxShadow> cardShadow;

  /// The Candlelight extension of the nearest theme (dark tokens if absent).
  static Candlelight of(BuildContext context) =>
      Theme.of(context).extension<Candlelight>() ??
      Candlelight.from(CandlelightTokens.dark);

  @override
  Candlelight copyWith({
    Color? inset,
    Color? muted,
    Color? ink2,
    Color? line,
    Color? amber,
    Color? onAmber,
    Color? amberText,
    Color? oxblood,
    Color? onOxblood,
    Color? react,
    Color? success,
    List<BoxShadow>? cardShadow,
  }) => Candlelight(
    inset: inset ?? this.inset,
    muted: muted ?? this.muted,
    ink2: ink2 ?? this.ink2,
    line: line ?? this.line,
    amber: amber ?? this.amber,
    onAmber: onAmber ?? this.onAmber,
    amberText: amberText ?? this.amberText,
    oxblood: oxblood ?? this.oxblood,
    onOxblood: onOxblood ?? this.onOxblood,
    react: react ?? this.react,
    success: success ?? this.success,
    cardShadow: cardShadow ?? this.cardShadow,
  );

  @override
  Candlelight lerp(Candlelight? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return Candlelight(
      inset: c(inset, other.inset),
      muted: c(muted, other.muted),
      ink2: c(ink2, other.ink2),
      line: c(line, other.line),
      amber: c(amber, other.amber),
      onAmber: c(onAmber, other.onAmber),
      amberText: c(amberText, other.amberText),
      oxblood: c(oxblood, other.oxblood),
      onOxblood: c(onOxblood, other.onOxblood),
      react: c(react, other.react),
      success: c(success, other.success),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? [],
    );
  }
}

ColorScheme _scheme(CandlelightTokens t) => ColorScheme(
  brightness: t.brightness,
  // primary is the amber that is safe as text/icons on this mode's surfaces;
  // filled buttons and chips use the amber fill through their own themes.
  primary: t.amberText,
  onPrimary: t.brightness == Brightness.dark
      ? CandlelightTokens.onAmber
      : Colors.white,
  primaryContainer: t.amberContainer,
  onPrimaryContainer: t.onAmberContainer,
  secondary: CandlelightTokens.oxblood,
  onSecondary: CandlelightTokens.onOxblood,
  secondaryContainer: t.inset,
  onSecondaryContainer: t.ink,
  tertiary: t.success,
  onTertiary: t.brightness == Brightness.dark ? t.bg : Colors.white,
  tertiaryContainer: t.inset,
  onTertiaryContainer: t.ink2,
  error: t.danger,
  onError: t.brightness == Brightness.dark ? t.bg : Colors.white,
  errorContainer: t.dangerContainer,
  onErrorContainer: t.onDangerContainer,
  surface: t.bg,
  onSurface: t.ink,
  onSurfaceVariant: t.muted,
  surfaceDim: t.bg,
  surfaceBright: t.card,
  surfaceContainerLowest: t.card,
  surfaceContainerLow: t.card,
  surfaceContainer: t.card,
  surfaceContainerHigh: t.inset,
  surfaceContainerHighest: t.inset,
  outline: t.ghostLine,
  outlineVariant: t.line,
  shadow: const Color(0xFF3C280A),
  scrim: Colors.black,
  inverseSurface: t.brightness == Brightness.dark
      ? const Color(0xFFF2E8D8)
      : const Color(0xFF1C1814),
  onInverseSurface: t.brightness == Brightness.dark
      ? const Color(0xFF1C1814)
      : const Color(0xFFF2E8D8),
  inversePrimary: t.brightness == Brightness.dark
      ? const Color(0xFF9A5B0E)
      : CandlelightTokens.amber,
  surfaceTint: Colors.transparent,
);

TextTheme _text(CandlelightTokens t) {
  TextStyle display(double size, double height) => TextStyle(
    fontFamily: kDisplayFont,
    fontWeight: FontWeight.w600,
    fontSize: size,
    height: height,
    letterSpacing: -0.01 * size,
    color: t.ink,
  );
  TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
    double spacing = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: kBodyFont,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: spacing,
    color: color ?? t.ink,
  );
  return TextTheme(
    displayLarge: display(52, 1.1),
    displayMedium: display(42, 1.1),
    displaySmall: display(34, 1.15),
    headlineLarge: display(30, 1.2),
    headlineMedium: display(28, 1.2),
    headlineSmall: display(22, 1.22),
    titleLarge: display(21, 1.25),
    titleMedium: body(16, weight: FontWeight.w600, height: 1.35),
    titleSmall: body(14, weight: FontWeight.w600, height: 1.35),
    bodyLarge: body(17, height: 1.6, color: t.ink2),
    bodyMedium: body(15, height: 1.5),
    bodySmall: body(13, height: 1.4, color: t.muted),
    labelLarge: body(14, weight: FontWeight.w600, height: 1.3),
    labelMedium: body(12, weight: FontWeight.w500, height: 1.3),
    labelSmall: body(11, weight: FontWeight.w500, height: 1.3),
  );
}

/// Full Material theme for one mode of Candlelight.
ThemeData buildCandlelightTheme(CandlelightTokens t) {
  final scheme = _scheme(t);
  final text = _text(t);
  final dark = t.brightness == Brightness.dark;
  const pill = StadiumBorder();
  final pillPadding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10);
  final buttonText = text.labelLarge!.copyWith(fontSize: 15);
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CandlelightTokens.radiusCard),
    side: BorderSide(color: t.cardBorder),
  );
  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    fontFamily: kBodyFont,
    textTheme: text,
    primaryTextTheme: text,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    cardColor: t.card,
    dividerColor: t.line,
    splashFactory: InkRipple.splashFactory,
    extensions: [Candlelight.from(t)],
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: t.muted),
      actionsIconTheme: IconThemeData(color: t.muted),
      titleTextStyle: text.titleLarge,
    ),
    // Light mode gets a faint warm shadow; elevation draws it from shadowColor.
    cardTheme: CardThemeData(
      color: t.card,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 1.5,
      shadowColor: dark ? Colors.transparent : const Color(0x553C280A),
      shape: cardShape,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      showCheckmark: false,
      backgroundColor: Colors.transparent,
      selectedColor: t.chipOnBg,
      disabledColor: Colors.transparent,
      color: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.chipOnBg : Colors.transparent,
      ),
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? const BorderSide(color: Colors.transparent)
            : BorderSide(color: t.line),
      ),
      labelStyle: text.labelLarge!.copyWith(
        fontSize: 13,
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.chipOnFg : t.muted,
        ),
      ),
      iconTheme: IconThemeData(color: t.muted, size: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      elevation: 0,
      pressElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        padding: WidgetStatePropertyAll(pillPadding),
        textStyle: WidgetStatePropertyAll(buttonText),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? t.inset
              : CandlelightTokens.amber,
        ),
        foregroundColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? t.muted
              : CandlelightTokens.onAmber,
        ),
        overlayColor: WidgetStatePropertyAll(
          CandlelightTokens.onAmber.withValues(alpha: 0.08),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: pill,
        padding: pillPadding,
        textStyle: buttonText,
        elevation: 0,
        backgroundColor: CandlelightTokens.amber,
        foregroundColor: CandlelightTokens.onAmber,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        padding: pillPadding,
        textStyle: buttonText,
        foregroundColor: t.ink,
        side: BorderSide(color: t.ghostLine),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        textStyle: buttonText,
        foregroundColor: t.amberText,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: CandlelightTokens.amber,
      foregroundColor: CandlelightTokens.onAmber,
      elevation: 1,
      shape: StadiumBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        side: WidgetStatePropertyAll(BorderSide(color: t.line)),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        backgroundColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.chipOnBg : Colors.transparent,
        ),
        foregroundColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.chipOnFg : t.muted,
        ),
        iconColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.chipOnFg : t.muted,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.nav,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: t.amberContainer,
      indicatorShape: pill,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? t.amberText : t.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium!.copyWith(
          color: s.contains(WidgetState.selected) ? t.amberText : t.muted,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.nav,
      indicatorColor: t.amberContainer,
      indicatorShape: pill,
      selectedIconTheme: IconThemeData(color: t.amberText),
      unselectedIconTheme: IconThemeData(color: t.muted),
      selectedLabelTextStyle: text.labelMedium!.copyWith(
        color: t.amberText,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: text.labelMedium!.copyWith(color: t.muted),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.amberText,
      unselectedLabelColor: t.muted,
      indicatorColor: t.amberText,
      dividerColor: t.line,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: t.inset,
      border: inputBorder(t.line),
      enabledBorder: inputBorder(t.line),
      focusedBorder: inputBorder(t.amberText, 1.5),
      errorBorder: inputBorder(t.danger),
      focusedErrorBorder: inputBorder(t.danger, 1.5),
      labelStyle: TextStyle(color: t.muted),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (s) => TextStyle(
          color: s.contains(WidgetState.error)
              ? t.danger
              : s.contains(WidgetState.focused)
              ? t.amberText
              : t.muted,
        ),
      ),
      hintStyle: TextStyle(color: t.muted),
      helperStyle: text.bodySmall,
      prefixStyle: TextStyle(color: t.muted),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.amberText,
      selectionColor: CandlelightTokens.amber.withValues(alpha: 0.35),
      selectionHandleColor: CandlelightTokens.amber,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.card,
      modalBackgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.ghostLine,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CandlelightTokens.radiusCard),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium!.copyWith(color: t.ink2),
      iconColor: t.amberText,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.line),
      ),
      textStyle: text.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: text.bodyMedium,
      menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(t.card)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium!.copyWith(
        color: scheme.onInverseSurface,
      ),
      // The snack bar is inverted, so its action uses the other mode's amber.
      actionTextColor: dark
          ? CandlelightTokens.light.amberText
          : CandlelightTokens.amber,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.muted,
      titleTextStyle: text.bodyLarge!.copyWith(
        color: t.ink,
        fontSize: 16,
        height: 1.35,
      ),
      subtitleTextStyle: text.bodyMedium!.copyWith(
        color: t.muted,
        fontSize: 14,
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 24),
    iconTheme: IconThemeData(color: t.muted),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: CandlelightTokens.amber,
      linearTrackColor: t.inset,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? CandlelightTokens.onAmber
            : t.muted,
      ),
      trackColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? CandlelightTokens.amber
            : t.inset,
      ),
      trackOutlineColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? CandlelightTokens.amber
            : t.ghostLine,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? CandlelightTokens.amber
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(CandlelightTokens.onAmber),
      side: BorderSide(color: t.ghostLine, width: 1.5),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.amberText : t.muted,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: CandlelightTokens.amber,
      thumbColor: CandlelightTokens.amber,
      inactiveTrackColor: t.inset,
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: CandlelightTokens.oxblood,
      textColor: CandlelightTokens.onOxblood,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: text.bodySmall!.copyWith(color: scheme.onInverseSurface),
    ),
  );
}

/// Amber fill for filled icon buttons (send), the same in both modes.
final ButtonStyle amberIconButtonStyle = IconButton.styleFrom(
  backgroundColor: CandlelightTokens.amber,
  foregroundColor: CandlelightTokens.onAmber,
  disabledBackgroundColor: CandlelightTokens.amber.withValues(alpha: 0.4),
  disabledForegroundColor: CandlelightTokens.onAmber.withValues(alpha: 0.5),
);

final ThemeData lightTheme = buildCandlelightTheme(CandlelightTokens.light);
final ThemeData darkTheme = buildCandlelightTheme(CandlelightTokens.dark);

/// "Reborn." in Fraunces 600, the full stop in amber.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontFamily: kDisplayFont,
      fontWeight: FontWeight.w600,
      fontSize: size,
      letterSpacing: -0.01 * size,
      height: 1.1,
      color: theme.colorScheme.onSurface,
    );
    return Semantics(
      label: 'Reborn',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: 'Reborn',
          children: [
            TextSpan(
              text: '.',
              style: TextStyle(color: Candlelight.of(context).amberText),
            ),
          ],
        ),
        style: style,
      ),
    );
  }
}

/// Uppercase small-caps category tag in amber text, with no fill.
class CategoryTag extends StatelessWidget {
  const CategoryTag(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontFamily: kBodyFont,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 11 * 0.12,
      height: 1.3,
      color: color ?? Candlelight.of(context).amberText,
    ),
  );
}

/// A person's initial on an oxblood disc.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.radius = 20});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: CandlelightTokens.oxblood,
      foregroundColor: CandlelightTokens.onOxblood,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: kBodyFont,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.85,
          color: CandlelightTokens.onOxblood,
        ),
      ),
    );
  }
}
