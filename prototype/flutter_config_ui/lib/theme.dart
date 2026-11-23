import 'package:material_ui/material_ui.dart';

const Color accentColor = Color(0xFF6C8CFF);
const Color violetColor = Color(0xFFB18CFF);
const Color successColor = Color(0xFF3DDC97);
const Color warningColor = Color(0xFFFFB86C);
const Color dangerColor = Color(0xFFFF6B7A);

ThemeData buildPrototypeTheme(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  final Color surface = isDark
      ? const Color(0xFF17181C)
      : const Color(0xFFF7F8FC);
  final Color panel = isDark ? const Color(0xFF1D1F25) : Colors.white;
  final Color border = isDark
      ? const Color(0xFF30333C)
      : const Color(0xFFE2E5ED);
  final Color text = isDark ? const Color(0xFFE9EAF0) : const Color(0xFF1A1C22);

  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: brightness,
      ).copyWith(
        primary: accentColor,
        secondary: violetColor,
        surface: surface,
        surfaceContainerHighest: panel,
        outline: border,
      );

  final ThemeData base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Noto Sans CJK SC',
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF111216)
        : const Color(0xFFF2F4F9),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    dividerColor: border,
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF17191F) : const Color(0xFFF7F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accentColor),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        side: BorderSide(color: border),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2D35) : const Color(0xFF1F2229),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
    ),
  );
}

Color panelColorOf(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1D1F25)
      : Colors.white;
}

Color borderColorOf(BuildContext context) => Theme.of(context).dividerColor;

Color inputFillColorOf(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF17191F)
      : const Color(0xFFF7F8FC);
}

Color mutedColorOf(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

TextStyle mutedStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: mutedColorOf(context), height: 1.45) ??
      TextStyle(fontSize: 12, color: mutedColorOf(context), height: 1.45);
}

TextStyle labelStyle(BuildContext context) {
  return Theme.of(context).textTheme.labelSmall?.copyWith(
        color: mutedColorOf(context),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ) ??
      TextStyle(
        fontSize: 11,
        color: mutedColorOf(context),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      );
}

TextStyle titleStyle(BuildContext context, {double size = 16}) {
  return TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: Theme.of(context).textTheme.titleMedium?.color,
    height: 1.25,
  );
}
