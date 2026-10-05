import 'package:flutter/material.dart';

import '../budget/budget.dart';
import '../theme/tide_theme.dart';
import 'vessel_geometry.dart';

/// The spoken label of a category pebble: name, spend, limit, and "over
/// limit" when the category has reached or passed its limit.
String pebbleSemanticLabel(CategoryPosition position) {
  final spent = formatRupees(position.spentMinor);
  final limit = formatRupees(position.limitMinor);
  final over = position.overLimit ? ', over limit' : '';
  return '${position.category.name}, $spent of $limit$over';
}

/// One category on the Vessel: an organic rounded shape showing the name and
/// the month's spend. Display-only.
///
/// It grows with the share of the limit used. Over the limit it sinks by
/// [pebbleSunkOffset] and its outline turns coral.
class CategoryPebble extends StatelessWidget {
  const CategoryPebble({
    super.key,
    required this.position,
    required this.growth,
    this.duration = const Duration(milliseconds: 600),
  });

  final CategoryPosition position;

  /// The most this pebble may grow beyond the minimum; see [pebbleGrowthFor].
  final double growth;

  /// How long size, offset and outline changes take. Zero in still water.
  final Duration duration;

  /// The key of the visible body of the pebble for [categoryId]. Its size is
  /// the pebble's diameter and its position includes the sunk offset.
  static Key bodyKey(String categoryId) =>
      ValueKey<String>('pebble-$categoryId');

  /// The pebble's outline: the category colour, or coral over the limit.
  static Color outlineColor(CategoryPosition position) => position.overLimit
      ? TideColors.coral
      : Color(position.category.colorValue);

  @override
  Widget build(BuildContext context) {
    final diameter = pebbleDiameter(position.share, growth: growth);
    final drop = position.overLimit ? pebbleSunkOffset : 0.0;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(minScaleFactor: 1, maxScaleFactor: 1.3);

    return Semantics(
      container: true,
      label: pebbleSemanticLabel(position),
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, drop, 0),
          child: AnimatedContainer(
            key: bodyKey(position.category.id),
            duration: duration,
            curve: Curves.easeOut,
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: TideColors.pebbleFill,
              border: Border.all(color: outlineColor(position), width: 1.5),
              // The prototype's 48% 52% 46% 54% / 56% 46% 54% 44%.
              borderRadius: BorderRadius.only(
                topLeft: Radius.elliptical(diameter * .48, diameter * .56),
                topRight: Radius.elliptical(diameter * .52, diameter * .46),
                bottomRight: Radius.elliptical(diameter * .46, diameter * .54),
                bottomLeft: Radius.elliptical(diameter * .54, diameter * .44),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    position.category.name,
                    style: TideText.pebbleName,
                    textScaler: scaler,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatRupees(position.spentMinor),
                    style: TideText.pebbleAmount,
                    textScaler: scaler,
                    maxLines: 1,
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

/// The pebbles laid out in rows of [perRow], each row bottom-aligned and
/// centred. A row holding an over-limit pebble keeps room beneath it for the
/// pebble to sink into, so it never lands on the row below.
class PebbleField extends StatelessWidget {
  const PebbleField({
    super.key,
    required this.categories,
    required this.width,
    this.duration = const Duration(milliseconds: 600),
  });

  final List<CategoryPosition> categories;

  /// The width available to a row.
  final double width;

  final Duration duration;

  static const int perRow = 3;
  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    final growth = pebbleGrowthFor(width, perRow: perRow, gap: gap);
    final rows = <Widget>[];
    for (var start = 0; start < categories.length; start += perRow) {
      final end = (start + perRow).clamp(0, categories.length);
      final row = categories.sublist(start, end);
      final sinks = row.any((p) => p.overLimit);
      if (start > 0) rows.add(const SizedBox(height: gap));
      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, position) in row.indexed) ...[
              if (i > 0) const SizedBox(width: gap),
              CategoryPebble(
                position: position,
                growth: growth,
                duration: duration,
              ),
            ],
          ],
        ),
      );
      rows.add(
        AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          height: sinks ? pebbleSunkOffset : 0,
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}
