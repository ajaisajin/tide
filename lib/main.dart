import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dev/scenario.dart';
import 'home/home_screen.dart';
import 'log/log_flow.dart';
import 'theme/tide_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter already draws edge to edge on Android; only the bar styling is
  // ours. (Asking for SystemUiMode.edgeToEdge as well made Android 16 draw a
  // coloured frame around the window.)
  SystemChrome.setSystemUIOverlayStyle(tideSystemUi);
  runApp(ProviderScope(overrides: scenarioOverrides(), child: const TideApp()));
}

class TideApp extends StatelessWidget {
  const TideApp({
    super.key,
    this.home = const HomeScreen(logFlowBuilder: buildLogFlow),
  });

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

/// Builds the log flow for the home screen's overlay slot.
Widget buildLogFlow(BuildContext context) => const LogFlow();
