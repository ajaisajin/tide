import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget/budget.dart';
import '../home/log_flow_state.dart';
import '../log/number_pad.dart';
import '../setup/budget_vessel.dart';
import '../state/budget_state.dart';
import '../state/confirmation_state.dart';
import '../state/haptics.dart';
import '../theme/tide_theme.dart';

/// The budget screen: the month's budget on the vessel, the monthly income,
/// and each category's limit with their total. Nothing is saved until Save,
/// which saves all of it together; Cancel and the system back button leave
/// everything as it was.
///
/// It fills the overlay slot of the home screen and closes itself through
/// [budgetScreenOpenProvider].
class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  static const saveKey = ValueKey<String>('budget-save');
  static const cancelKey = ValueKey<String>('budget-cancel');
  static const scrollKey = ValueKey<String>('budget-scroll');
  static const messageKey = ValueKey<String>('budget-message');

  /// The income row; tapping it opens the number pad.
  static const incomeKey = ValueKey<String>('budget-income');

  /// The total of the limits, and the note under it when that is more than
  /// the budget.
  static const limitsTotalKey = ValueKey<String>('budget-limits-total');
  static const overBudgetKey = ValueKey<String>('budget-limits-over');

  /// The amount being typed for the income or a limit, with its message and
  /// its own Done and Cancel.
  static const typedAmountKey = ValueKey<String>('budget-typed-amount');
  static const typedMessageKey = ValueKey<String>('budget-typed-message');
  static const typedDoneKey = ValueKey<String>('budget-typed-done');
  static const typedCancelKey = ValueKey<String>('budget-typed-cancel');

  /// A category's limit row; tapping it opens the number pad.
  static Key limitKey(String categoryId) =>
      ValueKey<String>('budget-limit-$categoryId');

  /// What is said when the changes could not be saved.
  static const saveFailedMessage =
      'That could not be saved. Tap Save to try again.';

  /// The same, for the home screen, when the screen was left before the save
  /// failed.
  static const saveFailedNotice = 'Your budget could not be saved';

  /// What the home screen says once the changes are saved.
  static const savedNotice = 'Budget saved';

  /// What is said while the budget is ₹0, which cannot be saved.
  static final noBudgetMessage =
      'Set a budget of at least ${formatRupees(minAmountMinor)}';

  /// What stands in for the vessel when no income has been saved.
  static const noIncomeMessage = 'Set your income to change the budget';

  /// Said when a typed income or limit is less than ₹1.
  static String belowMinimumMessage(String what) =>
      '$what must be at least ${formatRupees(minAmountMinor)}';

  /// Said when a typed income or limit is more than ₹99,99,999.
  static String aboveMaximumMessage(String what) =>
      '$what cannot be more than ${formatRupees(maxAmountMinor)}';

  /// The note under the limits' total when it is [overByMinor] more than the
  /// budget.
  static String overBudgetMessage(int overByMinor) =>
      '${formatRupees(overByMinor)} more than the budget';

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  /// The most rupees the pad will take: the largest income or limit.
  static const int _maxTypedRupees = maxAmountMinor ~/ paisePerRupee;

  // What the screen shows: the saved values as it opened, then as edited.
  // None of it reaches the ledger before Save.
  late int? _incomeMinor;
  late int _budgetMinor;
  final Map<String, int> _limitsMinor = {};

  /// True while the vessel's own number pad is open, with an amount that is
  /// not yet the budget.
  bool _typingBudget = false;

  /// The category whose limit is being typed, or [_incomeTarget] for the
  /// income; null while the pad is closed.
  String? _typing;
  int _typedRupees = 0;
  bool _nextDigitReplaces = true;
  String? _typedMessage;

  /// True from the tap on Save until the save has failed. After a save that
  /// worked it stays true while the screen closes.
  bool _saving = false;
  bool _saveFailed = false;

  static const _incomeTarget = '';

  @override
  void initState() {
    super.initState();
    final saved = ref.read(budgetProvider);
    _incomeMinor = saved.incomeMinor;
    _budgetMinor = saved.budgetMinor;
  }

  int _limitOf(Category category) =>
      _limitsMinor[category.id] ?? category.limitMinor;

  void _close() => ref.read(budgetScreenOpenProvider.notifier).close();

  void _setBudget(int budgetMinor) {
    if (_saving) return;
    setState(() {
      _budgetMinor = budgetMinor;
      _saveFailed = false;
    });
  }

  void _startTyping(String target, int amountMinor) {
    setState(() {
      _typing = target;
      _typedRupees = amountMinor ~/ paisePerRupee;
      _nextDigitReplaces = true;
      _typedMessage = null;
      // The vessel is taken away while the pad shows and comes back with its
      // own pad closed.
      _typingBudget = false;
      _saveFailed = false;
    });
  }

  void _stopTyping() => setState(() => _typing = null);

  /// A pad digit. The first one replaces the amount, later ones append, and
  /// one that would pass ₹99,99,999 is ignored.
  void _pressDigit(int digit) {
    final next = _nextDigitReplaces ? digit : _typedRupees * 10 + digit;
    if (next > _maxTypedRupees) return;
    setState(() {
      _typedRupees = next;
      _nextDigitReplaces = false;
      _typedMessage = null;
    });
  }

  void _pressDelete() {
    setState(() {
      _typedRupees = _typedRupees ~/ 10;
      _nextDigitReplaces = false;
      _typedMessage = null;
    });
  }

  /// Done: takes the typed amount as the income or the limit, or says why
  /// not.
  void _acceptTyped(String what) {
    final target = _typing!;
    final typed = rupees(_typedRupees);
    final check = target == _incomeTarget
        ? checkIncome(typed)
        : checkCategoryLimit(typed);
    final refusal = switch (check) {
      AmountCheck.ok => null,
      AmountCheck.aboveMaximum => BudgetScreen.aboveMaximumMessage(what),
      AmountCheck.belowMinimum ||
      AmountCheck.notWholeRupees => BudgetScreen.belowMinimumMessage(what),
    };
    if (refusal != null) {
      ref.read(hapticsProvider).refused();
      // The next digit starts a new amount; delete still edits this one.
      setState(() {
        _typedMessage = refusal;
        _nextDigitReplaces = true;
      });
      return;
    }
    setState(() {
      _typing = null;
      if (target == _incomeTarget) {
        _incomeMinor = typed;
        // The budget is a share of the income and cannot be more than it.
        if (_budgetMinor > typed) _budgetMinor = typed;
      } else {
        _limitsMinor[target] = typed;
      }
    });
  }

  /// Saves what was changed, as one write, and only once that has finished
  /// closes the screen. A second tap while the save is in flight does
  /// nothing. If the save fails nothing was saved: the screen stays open
  /// with the changes as made and says so.
  Future<void> _save() async {
    if (_saving || _typingBudget || _budgetMinor < minAmountMinor) return;
    final saved = ref.read(budgetProvider);
    final incomeMinor = _incomeMinor == saved.incomeMinor ? null : _incomeMinor;
    final budgetMinor = _budgetMinor == saved.budgetMinor ? null : _budgetMinor;
    final limitsMinor = {
      for (final c in saved.categories)
        if (_limitOf(c) != c.limitMinor) c.id: _limitOf(c),
    };
    if (incomeMinor == null && budgetMinor == null && limitsMinor.isEmpty) {
      _close();
      return;
    }
    // Read now: the screen may have been left by the time the save answers.
    final open = ref.read(budgetScreenOpenProvider.notifier);
    final confirmations = ref.read(confirmationProvider.notifier);
    final haptics = ref.read(hapticsProvider);
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await ref
          .read(budgetProvider.notifier)
          .saveBudgetSettings(
            incomeMinor: incomeMinor,
            budgetMinor: budgetMinor,
            categoryLimitsMinor: limitsMinor,
          );
    } catch (_) {
      haptics.refused();
      // A screen on its way out is still mounted, and no place for a message.
      if (mounted && ref.read(budgetScreenOpenProvider)) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      } else {
        confirmations.notice(BudgetScreen.saveFailedNotice);
      }
      return;
    }
    confirmations.notice(BudgetScreen.savedNotice);
    haptics.success();
    // _saving stays set: a tap that lands before the screen has gone must
    // not save again.
    if (mounted) open.close();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(budgetProvider.select((s) => s.categories));
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final typing = _typing;

    return ColoredBox(
      color: TideColors.ink,
      child: MediaQuery(
        // Beyond 1.5x the screen's own large type gains nothing and loses
        // room.
        data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.5),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth < 380 ? 16.0 : 20.0;
            final room = constraints.maxWidth - padding.horizontal - side * 2;
            final width = room > 460 ? 460.0 : room;
            final Widget content = typing == null
                ? _settings(categories)
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight - padding.vertical - 10 - 14,
                    ),
                    child: IntrinsicHeight(
                      child: _typedAmount(typing, categories),
                    ),
                  );
            // The system bars are kept outside the scroll view, so that what
            // is scrolled away is not drawn under the status bar, where it
            // shows through the clock and cannot be tapped.
            return Padding(
              padding: EdgeInsets.only(
                top: padding.top,
                bottom: padding.bottom,
              ),
              child: SingleChildScrollView(
                key: BudgetScreen.scrollKey,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  padding.left + side,
                  10,
                  padding.right + side,
                  14,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    // Nothing on the screen answers while a save is in
                    // flight.
                    child: AbsorbPointer(absorbing: _saving, child: content),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The screen as it opens: Cancel and Save, the vessel, the income and the
  /// limits.
  Widget _settings(List<Category> categories) {
    final incomeMinor = _incomeMinor;
    final noBudget = _budgetMinor < minAmountMinor;
    final limits = compareLimitsWithBudget(
      limitsMinor: categories.map(_limitOf),
      budgetMinor: _budgetMinor,
    );
    final message = _saveFailed
        ? BudgetScreen.saveFailedMessage
        : noBudget
        ? BudgetScreen.noBudgetMessage
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _PillButton(
              key: BudgetScreen.cancelKey,
              label: 'Cancel',
              onTap: _close,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Semantics(
                  header: true,
                  child: Text('Budget', maxLines: 1, style: TideText.title),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PillButton(
              key: BudgetScreen.saveKey,
              label: 'Save',
              primary: true,
              // A typed budget is not the budget until its own Done.
              onTap: _typingBudget || noBudget ? null : _save,
            ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: BudgetScreen.messageKey,
              textAlign: TextAlign.center,
              style: TideText.body(
                size: 13,
                weight: FontWeight.w600,
                color: TideColors.coral,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (incomeMinor == null)
          _NoIncomeBudget(budgetMinor: _budgetMinor)
        else
          // The vessel fills the height it is given. Its number pad needs
          // more of it than its tank does.
          SizedBox(
            height: _typingBudget ? 480 : 320,
            child: BudgetVessel(
              incomeMinor: incomeMinor,
              budgetMinor: _budgetMinor,
              onChanged: _setBudget,
              onTypingChanged: (typing) =>
                  setState(() => _typingBudget = typing),
            ),
          ),
        const SizedBox(height: 20),
        _AmountRow(
          key: BudgetScreen.incomeKey,
          name: 'Monthly income',
          amount: incomeMinor == null ? 'Not set' : formatRupees(incomeMinor),
          onTap: () => _startTyping(_incomeTarget, incomeMinor ?? 0),
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text('CATEGORY LIMITS', style: TideText.eyebrow),
        ),
        const SizedBox(height: 4),
        for (final c in categories)
          _AmountRow(
            key: BudgetScreen.limitKey(c.id),
            name: c.name,
            semanticName: '${c.name} limit',
            dot: Color(c.colorValue),
            amount: formatRupees(_limitOf(c)),
            onTap: () => _startTyping(c.id, _limitOf(c)),
          ),
        const Divider(height: 17, thickness: 1, color: Color(0x1FEEF2F5)),
        MergeSemantics(
          child: Row(
            children: [
              Expanded(child: Text('Total of limits', style: TideText.sub)),
              const SizedBox(width: 12),
              Text(
                formatRupees(limits.totalMinor),
                key: BudgetScreen.limitsTotalKey,
                maxLines: 1,
                style: TideText.body(size: 15, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (limits.isOverBudget) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              BudgetScreen.overBudgetMessage(limits.overByMinor),
              key: BudgetScreen.overBudgetKey,
              textAlign: TextAlign.end,
              style: TideText.body(
                size: 13,
                weight: FontWeight.w600,
                color: TideColors.coral,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The number pad for the income or one category's limit, in place of the
  /// rest of the screen until Done or Cancel.
  Widget _typedAmount(String target, List<Category> categories) {
    final what = target == _incomeTarget
        ? 'Monthly income'
        : '${categories.firstWhere((c) => c.id == target).name} limit';
    final message = _typedMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: _PillButton(
                key: BudgetScreen.typedCancelKey,
                label: 'Cancel',
                onTap: _stopTyping,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: _PillButton(
                key: BudgetScreen.typedDoneKey,
                label: 'Done',
                primary: true,
                onTap: () => _acceptTyped(what),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExcludeSemantics(
          child: Text(
            what.toUpperCase(),
            textAlign: TextAlign.center,
            style: TideText.eyebrow,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: '$what typed so far, ${formatRupees(rupees(_typedRupees))}',
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatRupees(rupees(_typedRupees)),
                key: BudgetScreen.typedAmountKey,
                maxLines: 1,
                textScaler: TextScaler.noScaling,
                style: TideText.display(size: 56),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            message ??
                '${formatRupees(minAmountMinor)} to '
                    '${formatRupees(maxAmountMinor)}',
            key: BudgetScreen.typedMessageKey,
            textAlign: TextAlign.center,
            style: TideText.body(
              size: 13,
              weight: message == null ? FontWeight.w500 : FontWeight.w600,
              color: message == null ? TideColors.muted : TideColors.coral,
            ),
          ),
        ),
        const SizedBox(height: 12),
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

/// Stands where the vessel would be while no income is saved: the vessel
/// shows the budget as a share of income, and there is none to share.
class _NoIncomeBudget extends StatelessWidget {
  const _NoIncomeBudget({required this.budgetMinor});

  final int budgetMinor;

  @override
  Widget build(BuildContext context) {
    final heroScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.35);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BUDGET', style: TideText.eyebrow),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatRupees(budgetMinor),
              key: BudgetVessel.budgetKey,
              maxLines: 1,
              softWrap: false,
              textScaler: heroScaler,
              style: TideText.hero,
            ),
          ),
          const SizedBox(height: 6),
          Text(BudgetScreen.noIncomeMessage, style: TideText.sub),
        ],
      ),
    );
  }
}

/// The income or a category's limit: its name, its amount, and a tap to
/// change it.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    super.key,
    required this.name,
    required this.amount,
    required this.onTap,
    this.semanticName,
    this.dot,
  });

  final String name;
  final String amount;
  final VoidCallback onTap;

  /// What a screen reader calls the row, when [name] alone is not enough.
  final String? semanticName;

  /// The category's colour.
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final dot = this.dot;
    return Semantics(
      button: true,
      onTap: onTap,
      label: '${semanticName ?? name}, $amount, change',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                if (dot != null) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.body(size: 15),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  amount,
                  maxLines: 1,
                  style: TideText.body(size: 15, weight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: TideColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cancel, Save or Done. Without [onTap] it is dimmed and does nothing.
class _PillButton extends StatelessWidget {
  const _PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Material(
          color: primary ? TideColors.teal : const Color(0x14EEF2F5),
          shape: StadiumBorder(
            side: BorderSide(
              color: primary ? TideColors.teal : const Color(0x2EEEF2F5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  widthFactor: 1,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TideText.body(
                        size: 14,
                        weight: primary ? FontWeight.w600 : FontWeight.w400,
                        color: primary ? TideColors.ink : TideColors.text,
                      ),
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
