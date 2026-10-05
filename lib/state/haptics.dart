import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tide's haptic vocabulary, over Flutter's built-in [HapticFeedback].
///
/// Everything that vibrates the phone goes through [hapticsProvider], so a
/// test can override it with a subclass that records the calls.
class TideHaptics {
  const TideHaptics();

  /// One amount-ring step.
  void tick() => HapticFeedback.selectionClick();

  /// An entry was recorded.
  void success() => HapticFeedback.mediumImpact();

  /// Filing was refused (no amount set).
  void refused() => HapticFeedback.vibrate();
}

final hapticsProvider = Provider<TideHaptics>((ref) => const TideHaptics());
