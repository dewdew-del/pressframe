import 'package:flutter/material.dart';
/// Text size chosen in the app (1 = normal). main.dart saves and restores it.
final textScaleSetting = ValueNotifier<double>(1.0);

const surfaceColor = Color(0xFF1E1E1E);
const panelColor = Color(0xFF2A2A2A);
const textColor = Color(0xFFE6E6E6);
const accentColor = Color(0xFF4C9FFF);
// Secondary text. Lighter than the first draft so it passes contrast on the panel color.
const hintColor = Color(0xFFA8A8A8);

/// Dark neutral gray so photo colors read true; one accent color for the active control.
final ThemeData pressFrameTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: accentColor,
    secondary: accentColor,
    surface: surfaceColor,
    onSurface: textColor,
    onPrimary: Color(0xFF0B1A2B),
  ),
  scaffoldBackgroundColor: surfaceColor,
  canvasColor: panelColor,
  dividerColor: const Color(0xFF3A3A3A),
  // A clearly visible ring/fill on whatever the Tab key lands on.
  focusColor: const Color(0x664C9FFF),
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    // 24 px radius makes every slider 48 px tall: a full-size touch target.
    overlayShape: RoundSliderOverlayShape(overlayRadius: 24),
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
  ),
  expansionTileTheme: const ExpansionTileThemeData(
    shape: Border(),
    collapsedShape: Border(),
    iconColor: textColor,
    collapsedIconColor: textColor,
    textColor: textColor,
  ),
  // Touch targets stay at least 48 px on both layouts.
  materialTapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
);
