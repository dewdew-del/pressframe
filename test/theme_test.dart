import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/ui/theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  tearDown(() => lightThemeSetting.value = false);

  for (final light in [false, true]) {
    test('${light ? 'light' : 'dark'} theme: text, hint and accent are readable on the panel', () {
      lightThemeSetting.value = light;
      expect(contrast(textColor, panelColor), greaterThan(4.5));
      expect(contrast(hintColor, panelColor), greaterThan(4.5));
      expect(contrast(accentColor, panelColor), greaterThan(4.5));
      expect(pressFrameTheme.brightness, light ? Brightness.light : Brightness.dark);
    });
  }
}
