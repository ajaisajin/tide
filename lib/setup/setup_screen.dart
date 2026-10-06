import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget/budget.dart';
import '../log/number_pad.dart';
import '../state/budget_state.dart';
import '../state/haptics.dart';
import '../theme/tide_theme.dart';
import 'budget_vessel.dart';

/// First-run setup, shown by the root widget until a budget has been saved.
///
/// It has two steps on one screen. The first asks for the monthly income
/// with the number pad, ₹1 to ₹99,99,999. The second shows that income, the
/// [BudgetVessel] to choose the budget as a share of it, and Confirm. The
/// income line on the second step leads back to the first.
///
/// Nothing is saved until Confirm, which completes setup through
/// `BudgetNotifier.completeSetup`; the root widget then shows the home screen
/// by itself. If that save fails the screen stays as it is and says so.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  /// The income figure: the amount typed so far on the first step, and the
  /// income the budget is a share of on the second.
  static const incomeKey = ValueKey<String>('setup-income');

  /// Next, under the income pad: takes the typed income and shows the vessel.
  static const incomeNextKey = ValueKey<String>('setup-income-next');

  /// The income line above the vessel; tapping it goes back to the pad.
  static const changeIncomeKey = ValueKey<String>('setup-change-income');

  static const confirmKey = ValueKey<String>('setup-confirm');

  /// The line above Confirm.
  static const messageKey = ValueKey<String>('setup-message');

  /// The scroll view of whichever step is showing.
  static const scrollKey = ValueKey<String>('setup-scroll');

  /// Said above Confirm while the budget is ₹0.
  static const noBudgetMessage = 'Fill the vessel to set your budget';

  /// Said above Confirm once there is a budget to confirm.
  static const readyMessage = 'You can change this later';

  /// What is said when setup could not be saved.
  static const saveFailedMessage = 'That could not be saved. Try again.';

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  /// The most rupees the pad will take: the largest income there can be.
  static const int _maxIncomeRupees = maxAmountMinor ~/ paisePerRupee;

  /// True on the first step, the income pad.
  bool _enteringIncome = true;

  /// The rupees typed so far on the income pad.
  int _typedRupees = 0;
  bool _nextDigitReplaces = true;

  /// The income taken by Next, in paise. 0 until there is one.
  int _incomeMinor = 0;

  int _budgetMinor = 0;

  /// True while the vessel's own pad is open on an amount not yet accepted.
  bool _typingBudget = false;

  /// True from the Confirm tap until the save has failed. After a save that
  /// worked it stays true until the home screen replaces this one.
  bool _saving = false;
  bool _saveFailed = false;

  bool get _incomeTypedOk => checkIncome(rupees(_typedRupees)).isOk;

  /// Setup can be confirmed only with an income and a budget of at least ₹1
  /// that is no more than the income.
  bool get _canConfirm =>
      !_typingBudget &&
      checkIncome(_incomeMinor).isOk &&
      checkTypedBudget(
        budgetMinor: _budgetMinor,
        incomeMinor: _incomeMinor,
      ).isOk;

  /// A pad digit. The first one replaces the amount, later ones append, and
  /// one that would pass ₹99,99,999 is ignored.
  void _pressDigit(int digit) {
    final next = _nextDigitReplaces ? digit : _typedRupees * 10 + digit;
    if (next > _maxIncomeRupees) return;
    setState(() {
      _typedRupees = next;
      _nextDigitReplaces = false;
    });
  }

  void _pressDelete() {
    setState(() {
      _typedRupees = _typedRupees ~/ 10;
      _nextDigitReplaces = false;
    });
  }

  /// Next: takes the typed income and shows the vessel. A budget chosen for
  /// a larger income comes down to the new one.
  void _acceptIncome() {
    if (!_incomeTypedOk) return;
    setState(() {
      _incomeMinor = rupees(_typedRupees);
      _budgetMinor = math.min(_budgetMinor, _incomeMinor);
      _enteringIncome = false;
      _saveFailed = false;
    });
  }

  /// Back to the income pad, showing the income as it stands.
  void _changeIncome() {
    if (_saving) return;
    setState(() {
      _typedRupees = _incomeMinor ~/ paisePerRupee;
      _nextDigitReplaces = true;
      _enteringIncome = true;
      // The vessel's pad goes with the vessel, and whatever was in it.
      _typingBudget = false;
      _saveFailed = false;
    });
  }

  void _setBudget(int budgetMinor) {
    if (_saving) return;
    setState(() {
      _budgetMinor = budgetMinor;
      _saveFailed = false;
    });
  }

  void _setTypingBudget(bool typing) {
    if (typing == _typingBudget) return;
    setState(() => _typingBudget = typing);
  }

  /// Confirm: saves the income, the budget and the default limits. A second
  /// tap while the save is in flight does nothing. If the save fails nothing
  /// was set up: the screen stays with what was entered and says so.
  Future<void> _confirm() async {
    if (_saving || !_canConfirm) return;
    final haptics = ref.read(hapticsProvider);
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await ref
          .read(budgetProvider.notifier)
          .completeSetup(incomeMinor: _incomeMinor, budgetMinor: _budgetMinor);
    } catch (_) {
      haptics.refused();
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
      return;
    }
    // _saving stays set: setup is done, and a tap that lands before the home
    // screen has replaced this one must not save it again.
    haptics.success();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ink,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: _enteringIncome ? _incomeStep() : _budgetStep(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _incomeStep() {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text('MONTHLY INCOME', style: TideText.eyebrow),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Monthly income, ${formatRupees(rupees(_typedRupees))}',
          excludeSemantics: true,
          child: _Figure(
            formatRupees(rupees(_typedRupees)),
            textKey: SetupScreen.incomeKey,
          ),
        ),
        const SizedBox(height: 6),
        Text('What comes in each month', style: TideText.sub),
        const SizedBox(height: 14),
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
        const SizedBox(height: 12),
        _SetupButton(
          key: SetupScreen.incomeNextKey,
          label: 'Next',
          onTap: _incomeTypedOk ? _acceptIncome : null,
        ),
      ],
    );
    // The figure, the pad and Next normally fill the screen exactly. With
    // large text on a small screen they cannot, and then they scroll rather
    // than overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: SetupScreen.scrollKey,
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: content),
        ),
      ),
    );
  }

  Widget _budgetStep(BuildContext context) {
    final String message;
    if (_saveFailed) {
      message = SetupScreen.saveFailedMessage;
    } else if (_budgetMinor < minAmountMinor) {
      message = SetupScreen.noBudgetMessage;
    } else {
      message = SetupScreen.readyMessage;
    }
    // The least height the vessel is given: its figures and a tank still
    // tall enough to drag in or, while its pad is open, Cancel and Done and
    // the pad at its smallest. The line under the budget wraps onto more
    // lines as the text grows, so past a scale of 1.5 the allowance for it
    // grows faster than the text does.
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(100) / 100;
    final minVesselHeight =
        _Figure.heightFor(scaler) +
        scaler.scale(57) * 1.4 * math.max(1, scale - 0.5) +
        28 +
        (_typingBudget ? 44 + 8 + 232 : 110);

    final content = AbsorbPointer(
      absorbing: _saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IncomeLine(incomeMinor: _incomeMinor, onTap: _changeIncome),
          const SizedBox(height: 12),
          Expanded(
            child: _AtLeast(
              height: minVesselHeight,
              child: BudgetVessel(
                incomeMinor: _incomeMinor,
                budgetMinor: _budgetMinor,
                onChanged: _setBudget,
                onTypingChanged: _setTypingBudget,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Every message is laid out and one is shown, so that a change of
          // message never changes the height of the tank above it.
          Stack(
            alignment: Alignment.center,
            children: [
              for (final m in const [
                SetupScreen.noBudgetMessage,
                SetupScreen.readyMessage,
                SetupScreen.saveFailedMessage,
              ])
                Visibility(
                  visible: m == message,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      m,
                      key: m == message ? SetupScreen.messageKey : null,
                      textAlign: TextAlign.center,
                      style: TideText.body(
                        size: 13,
                        weight: m == SetupScreen.saveFailedMessage
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: m == SetupScreen.saveFailedMessage
                            ? TideColors.coral
                            : TideColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _SetupButton(
            key: SetupScreen.confirmKey,
            label: 'Confirm',
            onTap: _canConfirm && !_saving ? _confirm : null,
          ),
        ],
      ),
    );
    // The vessel takes whatever height is left. On a screen too short for
    // that the step scrolls rather than overflows; the tank claims its own
    // drags, so dragging the level never scrolls.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: SetupScreen.scrollKey,
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: content),
        ),
      ),
    );
  }
}

/// Tells a parent working out its height that [child] needs [height], and
/// is otherwise not there. The vessel cannot answer that itself, because its
/// tank is laid out by a `LayoutBuilder`.
class _AtLeast extends SingleChildRenderObjectWidget {
  const _AtLeast({required this.height, required super.child});

  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAtLeast(height);

  @override
  void updateRenderObject(BuildContext context, _RenderAtLeast renderObject) {
    renderObject.height = height;
  }
}

class _RenderAtLeast extends RenderProxyBox {
  _RenderAtLeast(this._height);

  double _height;

  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}

/// An amount in the hero style, scaled down when it is too wide.
class _Figure extends StatelessWidget {
  const _Figure(this.text, {required this.textKey});

  final String text;
  final Key textKey;

  /// The height of a hero figure, here and in the vessel, at [scaler].
  static double heightFor(TextScaler scaler) =>
      scaler.clamp(maxScaleFactor: 1.35).scale(TideText.hero.fontSize!) *
      TideText.hero.height!;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.35);
    return SizedBox(
      height: heightFor(scaler),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          key: textKey,
          maxLines: 1,
          softWrap: false,
          textScaler: scaler,
          style: TideText.hero,
        ),
      ),
    );
  }
}

/// The income above the vessel, as a button that goes back to change it.
class _IncomeLine extends StatelessWidget {
  const _IncomeLine({required this.incomeMinor, required this.onTap});

  final int incomeMinor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      onTap: onTap,
      label: 'Monthly income, ${formatRupees(incomeMinor)}. Change',
      excludeSemantics: true,
      child: Material(
        key: SetupScreen.changeIncomeKey,
        color: const Color(0x12EEF2F5),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Income', style: TideText.sub),
                          const SizedBox(width: 8),
                          Text(
                            formatRupees(incomeMinor),
                            key: SetupScreen.incomeKey,
                            maxLines: 1,
                            style: TideText.body(
                              size: 15,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Change',
                        maxLines: 1,
                        style: TideText.body(
                          size: 15,
                          weight: FontWeight.w600,
                          color: TideColors.teal,
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

/// Next or Confirm: a wide button, dimmed while [onTap] is null.
class _SetupButton extends StatelessWidget {
  const _SetupButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      onTap: onTap,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: enabled ? TideColors.text : const Color(0x1FEEF2F5),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TideText.body(
                      size: 16,
                      weight: FontWeight.w600,
                      color: enabled ? TideColors.ink : TideColors.muted,
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
