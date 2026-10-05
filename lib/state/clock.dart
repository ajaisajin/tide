import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the current moment.
typedef Clock = DateTime Function();

/// The app's clock. Read the time as `ref.watch(clockProvider)()`.
///
/// Tests fix the date with
/// `clockProvider.overrideWithValue(() => DateTime(2026, 10, 5))`.
final clockProvider = Provider<Clock>((ref) => DateTime.now);
