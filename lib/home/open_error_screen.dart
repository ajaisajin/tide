import 'package:flutter/material.dart';

import '../theme/tide_theme.dart';

/// Shown instead of the app when the saved data cannot be opened. It says
/// so and offers Retry; it offers no way to start again from nothing.
class OpenErrorScreen extends StatelessWidget {
  const OpenErrorScreen({super.key, required this.onRetry});

  /// Runs start-up again. Null while a retry is under way.
  final VoidCallback? onRetry;

  static const retryKey = ValueKey<String>('open-error-retry');

  static const title = 'Tide’s data could not be opened';
  static const detail =
      'Your saved data has been left exactly as it is. Nothing has been '
      'deleted or replaced.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TideText.body(size: 20, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: TideText.body(size: 14, color: TideColors.soft),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    button: true,
                    enabled: onRetry != null,
                    onTap: onRetry,
                    label: 'Retry',
                    excludeSemantics: true,
                    child: Material(
                      key: retryKey,
                      color: TideColors.text,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onRetry,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 48,
                            minWidth: 120,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                'Retry',
                                style: TideText.body(
                                  size: 15,
                                  weight: FontWeight.w600,
                                  color: TideColors.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
