import 'package:flutter/material.dart';
/// Text size chosen in the app (1 = normal). main.dart saves and restores it.
final textScaleSetting = ValueNotifier<double>(1.0);

/// True for the optional light theme. The app is rebuilt from the top when it changes.
final lightThemeSetting = ValueNotifier<bool>(false);
bool get _light => lightThemeSetting.value;

Color get surfaceColor => _light ? const Color(0xFFF2F2F2) : const Color(0xFF1E1E1E);
Color get panelColor => _light ? const Color(0xFFFFFFFF) : const Color(0xFF2A2A2A);
Color get textColor => _light ? const Color(0xFF1E1E1E) : const Color(0xFFE6E6E6);
Color get accentColor => _light ? const Color(0xFF1F63C0) : const Color(0xFF4C9FFF);
// Secondary text, checked for contrast on the panel color in both themes.
Color get hintColor => _light ? const Color(0xFF595959) : const Color(0xFFA8A8A8);

/// Dark neutral gray so photo colors read true; one accent color for the active control.
ThemeData _build({required bool light}) => ThemeData(
  brightness: light ? Brightness.light : Brightness.dark,
  colorScheme: (light ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
    primary: light ? const Color(0xFF1F63C0) : const Color(0xFF4C9FFF),
    secondary: light ? const Color(0xFF1F63C0) : const Color(0xFF4C9FFF),
    surface: light ? const Color(0xFFF2F2F2) : const Color(0xFF1E1E1E),
    onSurface: light ? const Color(0xFF1E1E1E) : const Color(0xFFE6E6E6),
    onPrimary: light ? Colors.white : const Color(0xFF0B1A2B),
  ),
  scaffoldBackgroundColor: light ? const Color(0xFFF2F2F2) : const Color(0xFF1E1E1E),
  canvasColor: light ? Colors.white : const Color(0xFF2A2A2A),
  dividerColor: light ? const Color(0xFFD0D0D0) : const Color(0xFF3A3A3A),
  // A clearly visible ring/fill on whatever the Tab key lands on.
  focusColor: light ? const Color(0x661F63C0) : const Color(0x664C9FFF),
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    // 24 px radius makes every slider 48 px tall: a full-size touch target.
    overlayShape: RoundSliderOverlayShape(overlayRadius: 24),
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
  ),
  expansionTileTheme: ExpansionTileThemeData(
    shape: const Border(),
    collapsedShape: const Border(),
    iconColor: light ? const Color(0xFF1E1E1E) : const Color(0xFFE6E6E6),
    collapsedIconColor: light ? const Color(0xFF1E1E1E) : const Color(0xFFE6E6E6),
    textColor: light ? const Color(0xFF1E1E1E) : const Color(0xFFE6E6E6),
  ),
  // Touch targets stay at least 48 px on both layouts.
  materialTapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
);

final pressFrameDarkTheme = _build(light: false);
final pressFrameLightTheme = _build(light: true);
ThemeData get pressFrameTheme => _light ? pressFrameLightTheme : pressFrameDarkTheme;
