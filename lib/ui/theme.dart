import 'package:flutter/material.dart';

const surfaceColor = Color(0xFF1E1E1E);
const panelColor = Color(0xFF2A2A2A);
const textColor = Color(0xFFE6E6E6);
const accentColor = Color(0xFF4C9FFF);

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
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
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
