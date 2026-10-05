import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/confirmation_state.dart';
import '../theme/tide_theme.dart';

/// The confirmation shown on the home screen after an entry is recorded:
/// what was logged, how long it took, and Undo while it can still be undone.
class ConfirmationToast extends ConsumerWidget {
  const ConfirmationToast({super.key});

  static const toastKey = ValueKey<String>('confirmation-toast');
  static const undoKey = ValueKey<String>('confirmation-undo');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final confirmation = ref.watch(confirmationProvider);
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.3),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: confirmation == null
          ? const SizedBox.shrink()
          : _Toast(
              key: ValueKey<int>(confirmation.serial),
              confirmation: confirmation,
              onUndo: () => ref.read(confirmationProvider.notifier).undo(),
              onDismiss: () =>
                  ref.read(confirmationProvider.notifier).dismiss(),
            ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({
    super.key,
    required this.confirmation,
    required this.onUndo,
    required this.onDismiss,
  });

  final Confirmation confirmation;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = confirmation;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5);
    final message = TideText.body(
      size: 14,
      weight: FontWeight.w600,
      color: TideColors.ink,
      height: 1.25,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      onDismiss: onDismiss,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Container(
          key: ConfirmationToast.toastKey,
          constraints: const BoxConstraints(minHeight: 52, maxWidth: 480),
          padding: const EdgeInsets.fromLTRB(20, 4, 4, 4),
          decoration: BoxDecoration(
            color: TideColors.text,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text.rich(
                    TextSpan(
                      text: c.message,
                      children: [
                        if (c.detail != null)
                          TextSpan(
                            text: ' · ${c.detail}',
                            style: message.copyWith(
                              color: const Color(0xFF4A5567),
                              fontWeight: FontWeight.w500,
                              fontVariations: const [
                                FontVariation('wght', 500),
                              ],
                            ),
                          ),
                      ],
                    ),
                    style: message,
                    textScaler: scaler,
                  ),
                ),
              ),
              if (c.canUndo) ...[
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  onTap: onUndo,
                  label: 'Undo',
                  excludeSemantics: true,
                  child: Material(
                    key: ConfirmationToast.undoKey,
                    color: TideColors.ink,
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onUndo,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 44,
                          minWidth: 72,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              'Undo',
                              textScaler: scaler,
                              style: TideText.body(
                                size: 14,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
