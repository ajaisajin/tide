import 'package:flutter/material.dart';

import '../theme/tide_theme.dart';

/// The number pad: digits 0 to 9 and delete, as large keys that share
/// whatever space they are given.
class NumberPad extends StatelessWidget {
  const NumberPad({super.key, required this.onDigit, required this.onDelete});

  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;

  static Key digitKey(int digit) => ValueKey<String>('pad-$digit');
  static const deleteKey = ValueKey<String>('pad-delete');

  static const double gap = 8;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> keys) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, k) in keys.indexed) ...[
            if (i > 0) const SizedBox(width: gap),
            Expanded(child: k),
          ],
        ],
      ),
    );
    Widget digit(int d) => _PadKey(
      key: digitKey(d),
      label: '$d',
      onTap: () => onDigit(d),
      child: Text('$d', style: _digitStyle),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row([digit(1), digit(2), digit(3)]),
        const SizedBox(height: gap),
        row([digit(4), digit(5), digit(6)]),
        const SizedBox(height: gap),
        row([digit(7), digit(8), digit(9)]),
        const SizedBox(height: gap),
        row([
          const SizedBox.shrink(),
          digit(0),
          _PadKey(
            key: deleteKey,
            label: 'Delete',
            onTap: onDelete,
            quiet: true,
            child: const Icon(
              Icons.backspace_outlined,
              size: 24,
              color: TideColors.soft,
            ),
          ),
        ]),
      ],
    );
  }

  static final _digitStyle = TideText.display(
    size: 28,
    weight: FontWeight.w600,
    height: 1.1,
  );
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      onTap: onTap,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: quiet ? Colors.transparent : const Color(0x12EEF2F5),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          splashColor: const Color(0x22EEF2F5),
          highlightColor: const Color(0x18EEF2F5),
          child: Center(
            // Digits are already large; they do not grow with the text scale.
            child: MediaQuery.withNoTextScaling(child: child),
          ),
        ),
      ),
    );
  }
}
