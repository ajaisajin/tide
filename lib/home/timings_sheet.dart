import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../log/amount.dart';
import '../log/timing.dart';
import '../state/timing_state.dart';
import '../theme/tide_theme.dart';

/// The small "Timings" control on the home screen. A test instrument, not a
/// product feature: it opens the time-to-log summary.
class TimingsButton extends StatelessWidget {
  const TimingsButton({super.key});

  static const buttonKey = ValueKey<String>('timings-button');

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      onTap: () => showTimingsSheet(context),
      label: 'Timings, test instrument',
      excludeSemantics: true,
      child: InkWell(
        key: buttonKey,
        onTap: () => showTimingsSheet(context),
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: TideColors.muted,
                ),
                const SizedBox(height: 3),
                Text(
                  'Timings',
                  maxLines: 1,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                  style: TideText.hint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showTimingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF171F2E),
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const TimingsSheet(),
  );
}

/// Count and median time-to-log for each amount method and overall.
class TimingsSheet extends ConsumerWidget {
  const TimingsSheet({super.key});

  static const clearKey = ValueKey<String>('timings-clear');

  static Key rowKey(String name) => ValueKey<String>('timings-row-$name');

  static String countLabel(int count) =>
      count == 1 ? '1 entry' : '$count entries';

  static String medianLabel(TimingStat stat) =>
      stat.median == null ? '—' : formatSeconds(stat.median!);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(timingSummaryProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('TEST INSTRUMENT', style: TideText.eyebrow),
            const SizedBox(height: 4),
            Text('Time to log', style: TideText.title),
            const SizedBox(height: 6),
            Text(
              'From the log flow opening to an expense being filed, by the '
              'control that set the amount last. Median of each.',
              style: TideText.body(size: 13, color: TideColors.muted),
            ),
            const SizedBox(height: 14),
            for (final m in AmountMethod.values)
              _Row(name: m.label, stat: summary.of(m)),
            const Divider(color: Color(0x33EEF2F5), height: 17),
            _Row(name: 'Overall', stat: summary.overall, strong: true),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                onTap: () => ref.read(timingsProvider.notifier).clear(),
                label: 'Clear timings',
                excludeSemantics: true,
                child: Material(
                  key: clearKey,
                  color: const Color(0x14EEF2F5),
                  shape: const StadiumBorder(
                    side: BorderSide(color: Color(0x2EEEF2F5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => ref.read(timingsProvider.notifier).clear(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 44,
                        minWidth: 88,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            'Clear',
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
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.stat, this.strong = false});

  final String name;
  final TimingStat stat;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final count = TimingsSheet.countLabel(stat.count);
    final median = TimingsSheet.medianLabel(stat);
    return Semantics(
      container: true,
      label: stat.median == null
          ? '$name: $count'
          : '$name: $count, median $median',
      child: ExcludeSemantics(
        child: Padding(
          key: TimingsSheet.rowKey(name),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  name,
                  style: TideText.body(
                    size: 16,
                    weight: strong ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  count,
                  style: TideText.body(size: 14, color: TideColors.soft),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  median,
                  textAlign: TextAlign.right,
                  style: TideText.display(
                    size: 18,
                    weight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
