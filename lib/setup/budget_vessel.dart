import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget/budget.dart';
import '../log/number_pad.dart';
import '../state/haptics.dart';
import '../theme/tide_theme.dart';
import '../vessel/liquid_motion.dart';
import '../vessel/liquid_painter.dart';
import '../vessel/still_water.dart';

/// The spoken summary of the budget vessel: the budget, the income it is a
/// share of, and what is set aside.
String budgetVesselSemanticLabel({
  required int incomeMinor,
  required int budgetMinor,
}) {
  final setAside = incomeMinor > budgetMinor ? incomeMinor - budgetMinor : 0;
  return 'Budget vessel, ${formatRupees(budgetMinor)} '
      'of ${formatRupees(incomeMinor)} income, '
      '${formatRupees(setAside)} set aside';
}

/// The vessel used to choose a budget: the budget and set-aside figures over
/// a tank of the Vessel's liquid whose level is the budget's share of income.
///
/// Dragging in the tank moves the level to the finger, in the steps of
/// [budgetForLevel], with a haptic tick for each step. Tapping the budget
/// figure swaps the tank for the number pad, for an exact amount of ₹1 up to
/// the income. A screen reader gets the tank as an adjustable value.
///
/// The widget is controlled: it shows [budgetMinor] and reports every change
/// through [onChanged], and holds no budget of its own. It reads no store and
/// no budget state. It needs a bounded height, about 420 logical pixels or
/// more for the number pad to be comfortable.
class BudgetVessel extends ConsumerStatefulWidget {
  const BudgetVessel({
    super.key,
    required this.incomeMinor,
    required this.budgetMinor,
    required this.onChanged,
    this.onTypingChanged,
  });

  /// The monthly income, in paise: what a full vessel stands for.
  final int incomeMinor;

  /// The budget to show, in paise.
  final int budgetMinor;

  /// Called with the new budget, in paise, when a drag, a screen reader
  /// action or an accepted typed amount changes it. Never called with an
  /// amount below ₹0 or above [incomeMinor].
  final ValueChanged<int> onChanged;

  /// Called with true when the number pad opens and false when it closes.
  /// A typed amount is not reported until Done accepts it, so a screen can
  /// hold back its own Confirm or Save while this is true.
  final ValueChanged<bool>? onTypingChanged;

  /// The budget figure; tapping it opens the number pad. While typing it
  /// shows the amount typed so far.
  static const budgetKey = ValueKey<String>('budget-vessel-budget');

  /// The set-aside line under the budget figure.
  static const setAsideKey = ValueKey<String>('budget-vessel-set-aside');

  /// The tank: the area a drag is measured in. Its top is a full vessel and
  /// its bottom an empty one.
  static const tankKey = ValueKey<String>('budget-vessel-tank');

  /// The `CustomPaint` that draws the liquid. Its painter is a
  /// [VesselPainter], as on the home screen.
  static const liquidCanvasKey = ValueKey<String>('budget-vessel-liquid');

  /// The refusal message under the typed amount.
  static const messageKey = ValueKey<String>('budget-vessel-message');

  static const typedDoneKey = ValueKey<String>('budget-vessel-typed-done');
  static const typedCancelKey = ValueKey<String>('budget-vessel-typed-cancel');

  /// Said when a typed budget is more than the income.
  static String aboveIncomeMessage(int incomeMinor) =>
      'Budget cannot be more than your income of ${formatRupees(incomeMinor)}';

  /// Said when a typed budget is less than ₹1.
  static final belowMinimumMessage =
      'Budget must be at least ${formatRupees(minAmountMinor)}';

  @override
  ConsumerState<BudgetVessel> createState() => _BudgetVesselState();
}

class _BudgetVesselState extends ConsumerState<BudgetVessel>
    with SingleTickerProviderStateMixin {
  /// The most rupees the pad will take: the largest income there can be.
  static const int _maxTypedRupees = maxAmountMinor ~/ paisePerRupee;

  final _motion = LiquidMotion(color: TideColors.teal);

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  ui.FragmentShader? _shader;
  bool _still = false;

  /// The budget last shown or reported. It runs ahead of the widget's own
  /// between a report and the parent's rebuild.
  late int _budget = widget.budgetMinor;

  double _tankHeight = 0;
  int? _pointer;
  double _downY = 0;
  bool _dragging = false;
  bool _jumpNextLevel = false;

  /// The rupees typed so far; null while the pad is closed.
  int? _typedRupees;
  bool _nextDigitReplaces = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadShader();
  }

  @override
  void didUpdateWidget(BudgetVessel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _budget = widget.budgetMinor;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion.dispose();
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    final program = await ref.read(liquidProgramLoaderProvider)();
    if (program == null || !mounted) return;
    setState(() => _shader = program.fragmentShader());
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _motion.tick(dt);
  }

  /// Applies the still-water flag: stops or starts the ticker.
  void _setStill(bool still) {
    _still = still;
    _motion.still = still;
    if (still) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  /// Reports [next] with one haptic tick for each step between it and the
  /// budget showing now.
  void _stepTo(int next) {
    final income = widget.incomeMinor;
    final haptics = ref.read(hapticsProvider);
    var at = _budget;
    while (at != next) {
      final up = next > at;
      final stepped = up
          ? stepBudgetUp(budgetMinor: at, incomeMinor: income)
          : stepBudgetDown(budgetMinor: at, incomeMinor: income);
      if (stepped == at) break;
      // A typed budget between steps may be the nearer stop.
      at = (up ? stepped > next : stepped < next) ? next : stepped;
      haptics.tick();
    }
    if (next == _budget) return;
    _budget = next;
    widget.onChanged(next);
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downY = event.localPosition.dy;
    _dragging = false;
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _tankHeight <= 0) return;
    final y = event.localPosition.dy;
    // A touch that does not travel is not a drag and changes nothing.
    if (!_dragging && (y - _downY).abs() < kTouchSlop) return;
    _dragging = true;
    final next = budgetForLevel(
      level: 1 - y / _tankHeight,
      incomeMinor: widget.incomeMinor,
    );
    if (next == _budget) return;
    // The surface stays under the finger rather than springing after it.
    _jumpNextLevel = true;
    _stepTo(next);
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _dragging = false;
  }

  void _startTyping() {
    setState(() {
      _typedRupees = _budget ~/ paisePerRupee;
      _nextDigitReplaces = true;
      _message = null;
    });
    widget.onTypingChanged?.call(true);
  }

  void _stopTyping() {
    setState(() {
      _typedRupees = null;
      _message = null;
    });
    widget.onTypingChanged?.call(false);
  }

  /// A pad digit. The first one replaces the amount, later ones append, and
  /// one that would pass ₹99,99,999 is ignored.
  void _pressDigit(int digit) {
    final next = _nextDigitReplaces ? digit : _typedRupees! * 10 + digit;
    if (next > _maxTypedRupees) return;
    setState(() {
      _typedRupees = next;
      _nextDigitReplaces = false;
      _message = null;
    });
  }

  void _pressDelete() {
    setState(() {
      _typedRupees = _typedRupees! ~/ 10;
      _nextDigitReplaces = false;
      _message = null;
    });
  }

  /// Done: takes the typed amount as the budget, or says why not.
  void _acceptTyped() {
    final typed = rupees(_typedRupees!);
    final check = checkTypedBudget(
      budgetMinor: typed,
      incomeMinor: widget.incomeMinor,
    );
    final refusal = switch (check) {
      BudgetCheck.ok => null,
      BudgetCheck.aboveIncome => BudgetVessel.aboveIncomeMessage(
        widget.incomeMinor,
      ),
      BudgetCheck.belowMinimum ||
      BudgetCheck.notWholeRupees => BudgetVessel.belowMinimumMessage,
    };
    if (refusal != null) {
      ref.read(hapticsProvider).refused();
      // The next digit starts a new amount; delete still edits this one.
      setState(() {
        _message = refusal;
        _nextDigitReplaces = true;
      });
      return;
    }
    _stopTyping();
    if (typed == _budget) return;
    _budget = typed;
    widget.onChanged(typed);
  }

  @override
  Widget build(BuildContext context) {
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        ref.watch(slowFramesProvider);
    if (still != _still || (!still && !_ticker.isActive)) _setStill(still);

    final income = widget.incomeMinor;
    final budget = _budget;
    final typed = _typedRupees;
    final setAside = income > budget ? income - budget : 0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Figures(
          amountMinor: typed == null ? budget : rupees(typed),
          incomeMinor: income,
          setAsideMinor: setAside,
          typing: typed != null,
          message: _message,
          onTapBudget: typed == null ? _startTyping : null,
        ),
        const SizedBox(height: 14),
        Expanded(child: typed == null ? _tank(still) : _pad()),
      ],
    );
    if (typed == null) return content;
    // The figures and the pad normally fill the space exactly. With very
    // large text on a very small screen they cannot, and then they scroll
    // rather than overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: content),
        ),
      ),
    );
  }

  Widget _tank(bool still) {
    final income = widget.incomeMinor;
    final budget = _budget;
    final shader = _shader;
    final VesselPainter painter = still
        ? StillLiquidPainter(_motion)
        : shader != null
        ? ShaderLiquidPainter(shader, _motion)
        : PathLiquidPainter(_motion);
    final up = stepBudgetUp(budgetMinor: budget, incomeMinor: income);
    final down = stepBudgetDown(budgetMinor: budget, incomeMinor: income);
    final radius = BorderRadius.circular(28);

    return Semantics(
      container: true,
      label: budgetVesselSemanticLabel(
        incomeMinor: income,
        budgetMinor: budget,
      ),
      onIncrease: up == budget ? null : () => _stepTo(up),
      onDecrease: down == budget ? null : () => _stepTo(down),
      child: ExcludeSemantics(
        // Claims the touch at once, so dragging the level never scrolls a
        // screen small enough to need scrolling.
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (_) {},
                ),
          },
          child: Listener(
            key: BudgetVessel.tankKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: const Color(0x33EEF2F5)),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _tankHeight = constraints.maxHeight;
                    _motion.setLevel(
                      _tankHeight *
                          levelForBudget(
                            budgetMinor: budget,
                            incomeMinor: income,
                          ),
                      animate: !_jumpNextLevel,
                    );
                    _jumpNextLevel = false;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0x0AEEF2F5)),
                        RepaintBoundary(
                          child: CustomPaint(
                            key: BudgetVessel.liquidCanvasKey,
                            painter: painter,
                            size: Size.infinite,
                          ),
                        ),
                        if (budget <= 0)
                          Center(
                            child: Text(
                              'Drag up to fill',
                              style: TideText.hint,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: _PadAction(
                key: BudgetVessel.typedCancelKey,
                label: 'Cancel',
                onTap: _stopTyping,
              ),
            ),
            Flexible(
              child: _PadAction(
                key: BudgetVessel.typedDoneKey,
                label: 'Done',
                color: TideColors.teal,
                onTap: _acceptTyped,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 232,
                maxHeight: 356,
                maxWidth: 380,
              ),
              child: NumberPad(onDigit: _pressDigit, onDelete: _pressDelete),
            ),
          ),
        ),
      ],
    );
  }
}

/// The budget figure, which opens the number pad, and under it what is set
/// aside, or while typing the income or the reason an amount was refused.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.amountMinor,
    required this.incomeMinor,
    required this.setAsideMinor,
    required this.typing,
    required this.message,
    required this.onTapBudget,
  });

  final int amountMinor;
  final int incomeMinor;
  final int setAsideMinor;
  final bool typing;
  final String? message;
  final VoidCallback? onTapBudget;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final heroScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.35);

    // A fixed height, so that a figure wide enough to be scaled down does
    // not change the tank's height under a dragging finger.
    final figure = SizedBox(
      height: heroScaler.scale(TideText.hero.fontSize!) * TideText.hero.height!,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              formatRupees(amountMinor),
              key: BudgetVessel.budgetKey,
              maxLines: 1,
              softWrap: false,
              textScaler: heroScaler,
              style: TideText.hero,
            ),
            if (!typing) ...[
              const SizedBox(width: 10),
              const Icon(
                Icons.edit_outlined,
                size: 20,
                color: TideColors.muted,
              ),
            ],
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text('BUDGET', style: TideText.eyebrow)),
        const SizedBox(height: 8),
        if (typing)
          Semantics(
            label: 'Budget typed so far, ${formatRupees(amountMinor)}',
            excludeSemantics: true,
            child: figure,
          )
        else
          Semantics(
            button: true,
            onTap: onTapBudget,
            label: 'Type the budget',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapBudget,
              child: figure,
            ),
          ),
        const SizedBox(height: 6),
        if (message != null)
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: BudgetVessel.messageKey,
              style: TideText.sub.copyWith(color: TideColors.coral),
            ),
          )
        else if (typing)
          Text('of ${formatRupees(incomeMinor)} income', style: TideText.sub)
        else
          // The vessel's own label says both of these.
          ExcludeSemantics(
            child: Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  '${formatRupees(setAsideMinor)} set aside',
                  key: BudgetVessel.setAsideKey,
                  style: TideText.sub,
                ),
                Text('·', style: TideText.sub),
                Text(
                  'of ${formatRupees(incomeMinor)} income',
                  style: TideText.sub,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Cancel or Done above the number pad.
class _PadAction extends StatelessWidget {
  const _PadAction({
    super.key,
    required this.label,
    required this.onTap,
    this.color = TideColors.soft,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Semantics(
      button: true,
      onTap: onTap,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TideText.body(
                      size: 15,
                      weight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
