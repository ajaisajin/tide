import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget/budget.dart';
import '../home/log_flow_state.dart';
import '../state/budget_state.dart';
import '../state/clock.dart';
import '../state/confirmation_state.dart';
import '../state/haptics.dart';
import '../state/ledger.dart';
import '../state/log_session_state.dart';
import '../state/seed.dart';
import '../state/timing_state.dart';
import '../theme/tide_theme.dart';
import 'amount.dart';
import 'amount_ring.dart';
import 'number_pad.dart';
import 'timing.dart';

/// The log flow: set an amount with the chips, the pad or the ring, then tap
/// a category pebble (or an income source) to record it. One tap files; there
/// is no save button.
///
/// It fills the overlay slot of the home screen and closes itself through
/// [logFlowOpenProvider].
class LogFlow extends ConsumerStatefulWidget {
  const LogFlow({super.key});

  static const amountKey = ValueKey<String>('log-amount');
  static const cancelKey = ValueKey<String>('log-cancel');
  static const spendKey = ValueKey<String>('log-mode-spend');
  static const incomeKey = ValueKey<String>('log-mode-income');
  static const padSwitchKey = ValueKey<String>('log-panel-pad');
  static const ringSwitchKey = ValueKey<String>('log-panel-ring');
  static const addNoteKey = ValueKey<String>('log-add-note');
  static const noteFieldKey = ValueKey<String>('log-note');
  static const messageKey = ValueKey<String>('log-message');
  static const scrollKey = ValueKey<String>('log-scroll');

  static Key chipKey(int amountMinor) => ValueKey<String>('chip-$amountMinor');
  static Key pebbleKey(String categoryId) =>
      ValueKey<String>('log-pebble-$categoryId');
  static Key sourceKey(String source) => ValueKey<String>('log-source-$source');

  /// What is said when a pebble is tapped with no amount set.
  static const refusalMessage = 'Set an amount first';

  /// What is said when the entry could not be saved.
  static const saveFailedMessage = 'That could not be saved. Tap to try again.';

  /// The same, for the home screen, when the flow was closed before the
  /// save failed.
  static const saveFailedNotice = 'Your entry could not be saved';

  /// The height of a pebble and of an income source.
  static const double cellHeight = 68;

  @override
  ConsumerState<LogFlow> createState() => _LogFlowState();
}

class _LogFlowState extends ConsumerState<LogFlow> {
  final _note = TextEditingController();
  final _noteFocus = FocusNode();

  late final DateTime _openedAt;
  AmountEntry _amount = AmountEntry.initial;
  bool _income = false;
  bool _noteOpen = false;
  bool _refused = false;
  Timer? _refusedTimer;

  /// True from the filing tap until the save has failed. After a save that
  /// worked it stays true while the flow closes.
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _openedAt = ref.read(clockProvider)();
  }

  @override
  void dispose() {
    _refusedTimer?.cancel();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _setAmount(AmountEntry next) {
    if (_saving) return;
    if (next == _amount && !_refused && !_saveFailed) return;
    _refusedTimer?.cancel();
    setState(() {
      _amount = next;
      _refused = false;
      _saveFailed = false;
    });
  }

  void _ringStep(int delta) {
    final next = _amount.stepByRing(delta);
    if (next == _amount) return;
    ref.read(hapticsProvider).tick();
    _setAmount(next);
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(logFlowOpenProvider.notifier).close();
  }

  /// True, after saying so, when there is no amount to file.
  bool _refuseIfUnset() {
    if (_amount.isSet) return false;
    ref.read(hapticsProvider).refused();
    _refusedTimer?.cancel();
    _refusedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _refused = false);
    });
    setState(() => _refused = true);
    return true;
  }

  /// Saves through [save] and, only once that has finished, confirms with
  /// [confirm] and closes. A second tap while the save is in flight does
  /// nothing. If the save fails nothing was recorded: the flow stays open
  /// with the amount as entered and says so.
  Future<void> _file(
    Future<Entry> Function() save,
    void Function(Entry entry) confirm,
  ) async {
    if (_saving || _refuseIfUnset()) return;
    // Read now: the flow may have been closed by the time the save answers.
    final confirmations = ref.read(confirmationProvider.notifier);
    final haptics = ref.read(hapticsProvider);
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final Entry entry;
    try {
      entry = await save();
    } catch (_) {
      haptics.refused();
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      } else {
        confirmations.notice(LogFlow.saveFailedNotice);
      }
      return;
    }
    confirm(entry);
    haptics.success();
    // _saving stays set: this opening of the flow has filed its entry, and a
    // tap that lands before the flow has gone must not file another.
    if (mounted) _close();
  }

  Future<void> _fileExpense(Category category) {
    final budget = ref.read(budgetProvider.notifier);
    final timings = ref.read(timingsProvider.notifier);
    final confirmations = ref.read(confirmationProvider.notifier);
    final now = ref.read(clockProvider)();
    final typed = _note.text.trim();
    final amountMinor = rupees(_amount.rupees);
    final method = _amount.method ?? AmountMethod.pad;
    final elapsed = now.difference(_openedAt);
    return _file(
      () => budget.addExpense(
        amountMinor: amountMinor,
        categoryId: category.id,
        note: typed.isEmpty ? category.name : typed,
        occurredAt: now,
      ),
      (entry) {
        timings.add(
          TimingRecord(entryId: entry.id, method: method, elapsed: elapsed),
        );
        confirmations.entryRecorded(
          entryId: entry.id,
          message:
              'Logged ${formatRupees(entry.amountMinor)} to ${category.name}',
          detail: formatSeconds(elapsed),
        );
      },
    );
  }

  Future<void> _fileIncome(String source) {
    final budget = ref.read(budgetProvider.notifier);
    final confirmations = ref.read(confirmationProvider.notifier);
    final now = ref.read(clockProvider)();
    final typed = _note.text.trim();
    final amountMinor = rupees(_amount.rupees);
    return _file(
      () => budget.addIncome(
        amountMinor: amountMinor,
        note: typed.isEmpty ? source : typed,
        occurredAt: now,
      ),
      (entry) => confirmations.entryRecorded(
        entryId: entry.id,
        message: 'Added ${formatRupees(entry.amountMinor)} from $source',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(budgetProvider);
    final panel = ref.watch(entryPanelProvider);
    final chips = ref.watch(frequentAmountsProvider);
    final media = MediaQuery.of(context);
    final padding = media.padding;

    return ColoredBox(
      color: TideColors.ink,
      child: MediaQuery(
        // Beyond 1.5x the flow's own large type gains nothing and loses room.
        data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.5),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth < 380 ? 16.0 : 20.0;
            final room = constraints.maxWidth - padding.horizontal - side * 2;
            final width = room > 460 ? 460.0 : room;
            return SingleChildScrollView(
              key: LogFlow.scrollKey,
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left + side,
                      padding.top + 10,
                      padding.right + side,
                      padding.bottom + 14,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        // Nothing in the flow answers while a save is in
                        // flight.
                        child: AbsorbPointer(
                          absorbing: _saving,
                          child: _content(state, panel, chips, width),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _content(
    BudgetState state,
    EntryPanel panel,
    List<int> chips,
    double width,
  ) {
    final accent = _income ? TideColors.teal : TideColors.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _Segmented<bool>(
                  label: 'Entry type',
                  value: _income,
                  onChanged: (v) => setState(() {
                    _income = v;
                    _refused = false;
                    _saveFailed = false;
                  }),
                  options: const [
                    (false, 'Spend', LogFlow.spendKey),
                    (true, 'Income', LogFlow.incomeKey),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PillButton(key: LogFlow.cancelKey, label: 'Cancel', onTap: _close),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          container: true,
          label: 'Amount ${formatRupees(rupees(_amount.rupees))}',
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatRupees(rupees(_amount.rupees)),
                key: LogFlow.amountKey,
                maxLines: 1,
                textScaler: TextScaler.noScaling,
                style: TideText.display(
                  size: 56,
                  color: _amount.isSet ? accent : TideColors.muted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, c) in chips.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _Chip(
                      key: LogFlow.chipKey(c),
                      label: formatRupees(c),
                      selected: rupees(_amount.rupees) == c,
                      onTap: () =>
                          _setAmount(_amount.setFromChip(c ~/ paisePerRupee)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _Segmented<EntryPanel>(
                  label: 'Amount control',
                  value: panel,
                  compact: true,
                  onChanged: (v) =>
                      ref.read(entryPanelProvider.notifier).choose(v),
                  options: const [
                    (EntryPanel.pad, 'Pad', LogFlow.padSwitchKey),
                    (EntryPanel.ring, 'Ring', LogFlow.ringSwitchKey),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (!_noteOpen)
              _LinkButton(
                key: LogFlow.addNoteKey,
                label: 'Add note',
                onTap: () {
                  setState(() => _noteOpen = true);
                  _noteFocus.requestFocus();
                },
              ),
          ],
        ),
        if (_noteOpen) ...[
          const SizedBox(height: 8),
          _NoteField(controller: _note, focusNode: _noteFocus),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 232,
                maxHeight: 356,
                maxWidth: 380,
              ),
              child: panel == EntryPanel.pad
                  ? NumberPad(
                      onDigit: (d) => _setAmount(_amount.pressDigit(d)),
                      onDelete: () => _setAmount(_amount.pressDelete()),
                    )
                  : AmountRing(onStep: _ringStep),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            _saveFailed
                ? LogFlow.saveFailedMessage
                : _refused
                ? LogFlow.refusalMessage
                : _income
                ? 'Where did it come from?'
                : 'Tap a pebble to file it',
            key: LogFlow.messageKey,
            textAlign: TextAlign.center,
            style: TideText.body(
              size: 13,
              weight: _refused || _saveFailed
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: _refused || _saveFailed
                  ? TideColors.coral
                  : TideColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Grid(
          width: width,
          children: _income
              ? [
                  for (final s in incomeSources)
                    _FileCell(
                      key: LogFlow.sourceKey(s),
                      label: s,
                      semanticLabel: 'Add income from $s',
                      outline: TideColors.teal,
                      fill: const Color(0x1F2BB5A6),
                      pill: true,
                      onTap: () => _fileIncome(s),
                    ),
                ]
              : [
                  for (final c in state.categories)
                    _FileCell(
                      key: LogFlow.pebbleKey(c.id),
                      label: c.name,
                      semanticLabel: 'File to ${c.name}',
                      outline: Color(c.colorValue),
                      fill: const Color(0x0FEEF2F5),
                      onTap: () => _fileExpense(c),
                    ),
                ],
        ),
      ],
    );
  }
}

/// Three columns of equal cells, in the order given: always the same places.
class _Grid extends StatelessWidget {
  const _Grid({required this.width, required this.children});

  final double width;
  final List<Widget> children;

  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    final cell = (width - gap * 2) / 3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r * 3 < children.length; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          Row(
            children: [
              for (var i = r * 3; i < r * 3 + 3 && i < children.length; i++)
                Padding(
                  padding: EdgeInsets.only(left: i % 3 == 0 ? 0 : gap),
                  child: SizedBox(
                    width: cell,
                    height: LogFlow.cellHeight,
                    child: children[i],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A category pebble or an income source: tap to file.
class _FileCell extends StatelessWidget {
  const _FileCell({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.outline,
    required this.fill,
    required this.onTap,
    this.pill = false,
  });

  final String label;
  final String semanticLabel;
  final Color outline;
  final Color fill;
  final VoidCallback onTap;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // The prototype's pebble: 48% 52% 46% 54% / 56% 46% 54% 44%.
        final radius = pill
            ? BorderRadius.circular(h / 2)
            : BorderRadius.only(
                topLeft: Radius.elliptical(w * .48, h * .56),
                topRight: Radius.elliptical(w * .52, h * .46),
                bottomRight: Radius.elliptical(w * .46, h * .54),
                bottomLeft: Radius.elliptical(w * .54, h * .44),
              );
        return Semantics(
          button: true,
          onTap: onTap,
          label: semanticLabel,
          excludeSemantics: true,
          child: Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: outline, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              splashColor: outline.withValues(alpha: 0.25),
              highlightColor: outline.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TideText.body(size: 14, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A frequent-amount chip.
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      onTap: onTap,
      selected: selected,
      label: 'Set amount to $label',
      excludeSemantics: true,
      child: Material(
        color: selected ? const Color(0x332BB5A6) : const Color(0x14EEF2F5),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? TideColors.teal : const Color(0x2EEEF2F5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TideText.body(size: 14, weight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A two-way switch in the prototype's style: a soft track with the chosen
/// side filled.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.options,
    this.compact = false,
  });

  final String label;
  final T value;
  final ValueChanged<T> onChanged;
  final List<(T, String, Key)> options;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0x0FEEF2F5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, text, key) in options)
              Semantics(
                button: true,
                onTap: () => onChanged(v),
                selected: v == value,
                label: text,
                excludeSemantics: true,
                child: Material(
                  key: key,
                  color: v == value ? TideColors.text : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onChanged(v),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 38,
                        minWidth: compact ? 58 : 64,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 14 : 16,
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            text,
                            maxLines: 1,
                            style: TideText.body(
                              size: 14,
                              weight: FontWeight.w600,
                              color: v == value
                                  ? TideColors.ink
                                  : TideColors.soft,
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

class _PillButton extends StatelessWidget {
  const _PillButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      onTap: onTap,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: const Color(0x14EEF2F5),
        shape: const StadiumBorder(side: BorderSide(color: Color(0x2EEEF2F5))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(label, maxLines: 1, style: TideText.body(size: 14)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      onTap: onTap,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 16, color: TideColors.soft),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: TideText.body(
                    size: 14,
                    weight: FontWeight.w500,
                    color: TideColors.soft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      key: LogFlow.noteFieldKey,
      controller: controller,
      focusNode: focusNode,
      maxLines: 1,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: TideColors.teal,
      style: TideText.body(size: 15),
      onSubmitted: (_) => focusNode.unfocus(),
      onTapOutside: (_) => focusNode.unfocus(),
      decoration: InputDecoration(
        hintText: 'Note (optional)',
        hintStyle: TideText.body(size: 15, color: TideColors.muted),
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: const Color(0x0FEEF2F5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        enabledBorder: border(const Color(0x33EEF2F5)),
        focusedBorder: border(TideColors.teal),
      ),
    );
  }
}
