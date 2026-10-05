import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../budget/budget.dart';

/// Tide's colour tokens, taken from the design prototype.
abstract final class TideColors {
  /// The background of every screen.
  static const ink = Color(0xFF0E1420);

  /// Liquid in the "Calm water" band.
  static const teal = Color(0xFF2BB5A6);

  /// Liquid in the "Running lower" band.
  static const amber = Color(0xFFE9A23B);

  /// Liquid in the "Nearly dry" band, the overspent band, and every warning.
  static const coral = Color(0xFFE86A5A);

  /// Primary text.
  static const text = Color(0xFFEEF2F5);

  /// Labels and hints.
  static const muted = Color(0xFF8C97A8);

  /// Secondary text.
  static const soft = Color(0xFFB7C0CC);

  /// The remaining amount while overspent: text tinted toward coral.
  static const overspentInk = Color(0xFFF2B5AC);

  /// The dark translucent fill of pebbles and chips that sit over the liquid.
  static const pebbleFill = Color(0xA80E1420);

  /// The liquid (or warning) colour for a status band.
  static Color forBand(StatusBand band) => switch (band) {
    StatusBand.calmWater => teal,
    StatusBand.runningLower => amber,
    StatusBand.nearlyDry => coral,
    StatusBand.belowTheLine => coral,
  };
}

/// Tide's font families and text styles.
///
/// Both families ship as variable fonts, so every style sets the weight axis
/// through `fontVariations` as well as `fontWeight`; build new styles with
/// [display] and [body] rather than `TextStyle(fontFamily: ...)`.
abstract final class TideText {
  static const displayFamily = 'Bricolage Grotesque';
  static const bodyFamily = 'DM Sans';

  /// A style in the display face (Bricolage Grotesque).
  static TextStyle display({
    required double size,
    FontWeight weight = FontWeight.w700,
    Color color = TideColors.text,
    double height = 1.05,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: displayFamily,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [
      FontVariation('wght', weight.value.toDouble()),
      FontVariation('opsz', size.clamp(12, 96).toDouble()),
    ],
    color: color,
    height: height,
    letterSpacing: letterSpacing ?? -0.02 * size,
  );

  /// A style in the text face (DM Sans).
  static TextStyle body({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = TideColors.text,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: bodyFamily,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [
      FontVariation('wght', weight.value.toDouble()),
      FontVariation('opsz', size.clamp(9, 40).toDouble()),
    ],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  /// The remaining amount on the Vessel: the largest text in the app.
  static final hero = display(size: 60);

  /// The amount being entered in the log flow.
  static final amount = display(size: 48);

  /// A screen or sheet title.
  static final title = display(size: 22, weight: FontWeight.w600, height: 1.2);

  /// Small spaced capitals above the hero number ("OCTOBER · RUNNING LOWER").
  static final eyebrow = body(
    size: 12,
    weight: FontWeight.w600,
    color: TideColors.muted,
    letterSpacing: 1.2,
  );

  /// The line under the hero number.
  static final sub = body(size: 15, color: TideColors.soft);

  /// Chips and buttons.
  static final chip = body(size: 13, weight: FontWeight.w500);

  /// Ordinary text.
  static final bodyText = body(size: 14, height: 1.35);

  /// A pebble's category name.
  static final pebbleName = body(size: 12, weight: FontWeight.w600);

  /// A pebble's amount.
  static final pebbleAmount = body(size: 11, color: Color(0xD9EEF2F5));

  /// Hints such as "Pull down to log".
  static final hint = body(
    size: 12,
    weight: FontWeight.w500,
    color: TideColors.muted,
  );
}

/// The app theme: dark, ink background, DM Sans throughout.
ThemeData tideTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: TideColors.teal,
    brightness: Brightness.dark,
    surface: TideColors.ink,
    onSurface: TideColors.text,
    primary: TideColors.teal,
    error: TideColors.coral,
  );
  final base = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: TideColors.ink,
    fontFamily: TideText.bodyFamily,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: TideColors.text,
      displayColor: TideColors.text,
    ),
  );
}

/// Light status-bar and navigation-bar icons over transparent bars, for the
/// edge-to-edge ink background.
const tideSystemUi = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);
