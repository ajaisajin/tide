import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget_screen/budget_screen.dart';
import '../state/confirmation_state.dart';
import '../theme/tide_theme.dart';
import '../vessel/vessel_layer.dart';
import 'confirmation_toast.dart';
import 'log_flow_state.dart';
import 'pull_to_log.dart';
import 'timings_sheet.dart';

/// Tide's one screen: the Vessel, always in the tree, with a slot above it
/// that holds the log flow while [logFlowOpenProvider] is true and the budget
/// screen while [budgetScreenOpenProvider] is.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.logFlowBuilder, this.budgetScreenBuilder});

  /// Builds what fills the overlay slot while the log flow is open. It is
  /// given the whole screen, including the areas behind the system bars.
  /// Defaults to [LogFlowPlaceholder].
  final WidgetBuilder? logFlowBuilder;

  /// Builds what fills the overlay slot while the budget screen is open.
  /// Defaults to [BudgetScreen].
  final WidgetBuilder? budgetScreenBuilder;

  /// The overlay slot. In the tree only while the log flow or the budget
  /// screen is open.
  static const overlaySlotKey = ValueKey<String>('log-flow-slot');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetOpen = ref.watch(budgetScreenOpenProvider);
    final open = budgetOpen || ref.watch(logFlowOpenProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tideSystemUi,
      child: Scaffold(
        backgroundColor: TideColors.ink,
        resizeToAvoidBottomInset: false,
        // The system back button closes the log flow, or leaves the budget
        // screen without saving, rather than closing the app.
        body: PopScope(
          canPop: !open,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            ref.read(logFlowOpenProvider.notifier).close();
            ref.read(budgetScreenOpenProvider.notifier).close();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A screen reader should not wander into the Vessel while the
              // log flow or the budget screen covers it.
              ExcludeSemantics(
                excluding: open,
                child: PullToLog(
                  onOpen: () => ref.read(logFlowOpenProvider.notifier).open(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VesselLayer(
                        onBudgetTap: () =>
                            ref.read(budgetScreenOpenProvider.notifier).open(),
                      ),
                      const _HomeChrome(),
                    ],
                  ),
                ),
              ),
              _Overlay(
                open: open,
                builder: budgetOpen
                    ? budgetScreenBuilder ?? _budgetScreen
                    : logFlowBuilder ?? _placeholder,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _placeholder(BuildContext context) =>
      const LogFlowPlaceholder();

  static Widget _budgetScreen(BuildContext context) => const BudgetScreen();
}

/// Stands in for the log flow until it is built: an empty ink scrim.
class LogFlowPlaceholder extends StatelessWidget {
  const LogFlowPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xE60E1420), child: SizedBox.expand());
  }
}

/// What sits over the Vessel on the home screen: the handle that opens the
/// log flow, the Timings control and the confirmation toast.
class _HomeChrome extends ConsumerWidget {
  const _HomeChrome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = MediaQuery.paddingOf(context);
    final toastShowing = ref.watch(confirmationProvider) != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The toast takes the handle row while it shows.
        Positioned(
          top: padding.top + 6,
          left: 0,
          right: 0,
          child: _HiddenWhile(
            hidden: toastShowing,
            child: Center(
              child: LogHandle(
                onTap: () => ref.read(logFlowOpenProvider.notifier).open(),
              ),
            ),
          ),
        ),
        Positioned(
          top: padding.top + 6,
          right: padding.right + 8,
          child: _HiddenWhile(
            hidden: toastShowing,
            child: const TimingsButton(),
          ),
        ),
        Positioned(
          left: padding.left + 16,
          right: padding.right + 16,
          // Over the handle row, as in the prototype, where it hides neither
          // the figures nor the pebbles. Pulling down still opens the log
          // flow while it shows, and a tap on it puts it away.
          top: padding.top + 4,
          child: const Center(child: ConfirmationToast()),
        ),
      ],
    );
  }
}

/// Fades its child out, and takes it away from touch and screen readers,
/// while [hidden].
class _HiddenWhile extends StatelessWidget {
  const _HiddenWhile({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          child: child,
        ),
      ),
    );
  }
}

/// Holds the log flow or the budget screen in the overlay slot and animates
/// it in and out: a short fade and slide from the top, or nothing when
/// reduce-motion is on.
class _Overlay extends StatefulWidget {
  const _Overlay({required this.open, required this.builder});

  final bool open;

  /// Builds what is open. Once [open] is false it is not used: what was open
  /// leaves as it was built.
  final WidgetBuilder builder;

  @override
  State<_Overlay> createState() => _OverlayState();
}

class _OverlayState extends State<_Overlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, -0.04),
    end: Offset.zero,
  ).animate(_curve);

  /// Keeps the content's state while it leaves; renewed each time it opens,
  /// so every opening starts fresh.
  GlobalKey _contentKey = GlobalKey();

  /// The builder of what is open, or of what was open and is leaving.
  late WidgetBuilder _builder = widget.builder;

  @override
  void didUpdateWidget(_Overlay old) {
    super.didUpdateWidget(old);
    if (widget.open) _builder = widget.builder;
    if (widget.open == old.open) return;
    if (widget.open) _contentKey = GlobalKey();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (!widget.open && _controller.isDismissed) {
          return const SizedBox.shrink();
        }
        final Widget content = KeyedSubtree(
          key: _contentKey,
          child: Builder(builder: _builder),
        );
        return IgnorePointer(
          ignoring: !widget.open,
          child: FadeTransition(
            opacity: _curve,
            child: SlideTransition(
              position: _slide,
              // The slot key is there only while the flow is open; on its way
              // out the same content plays its exit without it.
              child: widget.open
                  ? KeyedSubtree(key: HomeScreen.overlaySlotKey, child: content)
                  : content,
            ),
          ),
        );
      },
    );
  }
}
