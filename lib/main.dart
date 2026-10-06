import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'dev/scenario.dart';
import 'dev/start_timing.dart';
import 'home/home_screen.dart';
import 'home/open_error_screen.dart';
import 'log/log_flow.dart';
import 'setup/setup_screen.dart';
import 'state/budget_state.dart';
import 'state/ledger.dart';
import 'state/start_up.dart';
import 'theme/tide_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter already draws edge to edge on Android; only the bar styling is
  // ours. (Asking for SystemUiMode.edgeToEdge as well made Android 16 draw a
  // coloured frame around the window.)
  SystemChrome.setSystemUIOverlayStyle(tideSystemUi);
  // The ledger is opened and read before the first frame, while the
  // platform's launch screen shows the ink background. A scenario build
  // never opens the saved ledger.
  Future<StartResult> start() =>
      tideScenario.isEmpty ? startUp() : startUp(open: openScenarioLedger);
  final initial = await start();
  runApp(
    TideLauncher(
      initial: initial,
      start: start,
      overrides: scenarioOverrides(),
    ),
  );
  // Profile builds only: the start-up time, for the README's measurement.
  logStartTime(switch (initial) {
    Started(:final start) => start.hasBudget ? 'home' : 'setup',
    StartFailed() => 'error',
  });
}

/// Runs the app on the ledger that start-up opened, or, when it could not be
/// opened, the error screen, whose Retry runs [start] again.
class TideLauncher extends StatefulWidget {
  const TideLauncher({
    super.key,
    required this.initial,
    required this.start,
    this.overrides = const [],
    this.app = const TideApp(),
  });

  /// How the start-up that `main()` awaited ended.
  final StartResult initial;

  /// The same start-up, for Retry.
  final Future<StartResult> Function() start;

  /// Overrides to add to the two for the ledger.
  final List<Override> overrides;

  /// What runs once the ledger is open.
  final Widget app;

  @override
  State<TideLauncher> createState() => _TideLauncherState();
}

class _TideLauncherState extends State<TideLauncher> {
  late StartResult _result = widget.initial;
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final result = await widget.start();
    if (!mounted) return;
    setState(() {
      _result = result;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_result) {
      Started(:final store, :final start) => ProviderScope(
        overrides: [...ledgerOverrides(store, start), ...widget.overrides],
        child: widget.app,
      ),
      StartFailed() => TideApp(
        home: OpenErrorScreen(onRetry: _retrying ? null : _retry),
      ),
    };
  }
}

class TideApp extends StatelessWidget {
  const TideApp({super.key, this.home = const TideRoot()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tide',
      debugShowCheckedModeBanner: false,
      theme: tideTheme(),
      home: home,
    );
  }
}

/// Chooses the screen: setup until a budget has been saved, home from then
/// on. There is no router.
class TideRoot extends ConsumerWidget {
  const TideRoot({
    super.key,
    this.setup = const SetupScreen(),
    this.home = const HomeScreen(logFlowBuilder: buildLogFlow),
  });

  final Widget setup;
  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupComplete = ref.watch(
      budgetProvider.select((state) => state.setupComplete),
    );
    return setupComplete ? home : setup;
  }
}

/// Builds the log flow for the home screen's overlay slot.
Widget buildLogFlow(BuildContext context) => const LogFlow();
