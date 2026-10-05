import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/tide_theme.dart';

/// Opens the log flow when [child] is dragged downward by [threshold] and
/// released. A droplet follows the finger while it is dragged.
///
/// A drag counts only if it starts below the top safe-area inset, so it
/// never competes with the system's notification gesture.
///
/// Where the Vessel itself has to scroll (a very small screen with very large
/// text), its scroll view takes the drag; a pull then counts once the Vessel
/// is at its top and the finger keeps going.
class PullToLog extends StatefulWidget {
  const PullToLog({super.key, required this.onOpen, required this.child});

  final VoidCallback onOpen;
  final Widget child;

  /// How far the finger must travel downward, in logical pixels.
  static const double threshold = 80;

  static const dropletKey = ValueKey<String>('pull-droplet');

  @override
  State<PullToLog> createState() => _PullToLogState();
}

class _PullToLogState extends State<PullToLog> {
  /// Where the finger is and how far down it has come; null when no pull is
  /// under way.
  final _pull = ValueNotifier<({Offset at, double travel})?>(null);

  Offset? _start;
  bool _scrollPull = false;

  /// Where the finger was when the scroll view reached its top and the pull
  /// began; null when the scroll view is not being pulled.
  double? _pullFromY;

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  bool _belowInset(Offset global) =>
      global.dy >= MediaQuery.paddingOf(context).top;

  void _finish() {
    final travel = _pull.value?.travel ?? 0;
    _start = null;
    _pull.value = null;
    if (travel >= PullToLog.threshold) widget.onOpen();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) {
      final details = n.dragDetails;
      _scrollPull = details != null && _belowInset(details.globalPosition);
      _pullFromY = null;
    } else if (n is OverscrollNotification || n is ScrollUpdateNotification) {
      // Layout can leave the Vessel a hair taller than the screen (a scroll
      // extent of 1e-13), so "at its top" allows for rounding. Without that
      // allowance the least upward wobble of the finger counted as the
      // Vessel scrolling away and threw the pull away.
      final atTop =
          n.metrics.pixels <=
          n.metrics.minScrollExtent + precisionErrorTolerance;
      if (!atTop) {
        // The Vessel has really scrolled: this is no longer a pull.
        _pullFromY = null;
        _pull.value = null;
        return false;
      }
      final details = switch (n) {
        OverscrollNotification(:final dragDetails) => dragDetails,
        ScrollUpdateNotification(:final dragDetails) => dragDetails,
        _ => null,
      };
      if (!_scrollPull || details == null) return false;
      final y = details.globalPosition.dy;
      // The pull starts where the finger was when the Vessel first refused
      // to scroll any further down. Travel is measured from there, so
      // coming back up shrinks it again.
      if (n is OverscrollNotification && n.overscroll < 0) {
        _pullFromY ??= y + n.overscroll;
      }
      final from = _pullFromY;
      if (from == null) return false;
      final travel = y - from;
      _pull.value = travel > 0
          ? (at: details.globalPosition, travel: travel)
          : null;
    } else if (n is ScrollEndNotification) {
      _scrollPull = false;
      _pullFromY = null;
      _finish();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Measure from where the finger went down, not from where the
            // drag was recognised.
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (d) {
              _start = _belowInset(d.globalPosition) ? d.globalPosition : null;
            },
            onVerticalDragUpdate: (d) {
              final start = _start;
              if (start == null) return;
              final travel = d.globalPosition.dy - start.dy;
              _pull.value = travel > 0
                  ? (at: d.globalPosition, travel: travel)
                  : null;
            },
            onVerticalDragEnd: (_) => _finish(),
            onVerticalDragCancel: () {
              _start = null;
              _pull.value = null;
            },
            child: widget.child,
          ),
        ),
        IgnorePointer(
          child: ExcludeSemantics(
            child: ValueListenableBuilder(
              valueListenable: _pull,
              builder: (context, pull, _) {
                if (pull == null) return const SizedBox.shrink();
                return _Droplet(at: pull.at, travel: pull.travel);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The droplet that follows the finger: it swells as the pull nears the
/// threshold and fills once letting go will open the log flow.
class _Droplet extends StatelessWidget {
  const _Droplet({required this.at, required this.travel});

  final Offset at;
  final double travel;

  @override
  Widget build(BuildContext context) {
    final progress = (travel / PullToLog.threshold).clamp(0.0, 1.0);
    final armed = travel >= PullToLog.threshold;
    final box = context.findAncestorRenderObjectOfType<RenderBox>();
    final local = box != null && box.hasSize ? box.globalToLocal(at) : at;
    final width = 30 + 18 * progress;
    final height = width * 1.3;
    return Stack(
      children: [
        Positioned(
          key: PullToLog.dropletKey,
          left: local.dx - 70,
          // Above the finger, where it can be seen.
          top: local.dy - height - 44,
          width: 140,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: Size(width, height),
                painter: _DropletPainter(armed: armed, progress: progress),
              ),
              const SizedBox(height: 6),
              Text(
                armed ? 'Release to log' : 'Keep pulling',
                textScaler: TextScaler.noScaling,
                style: TideText.body(
                  size: 12,
                  weight: FontWeight.w600,
                  color: armed ? TideColors.text : TideColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropletPainter extends CustomPainter {
  _DropletPainter({required this.armed, required this.progress});

  final bool armed;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // A teardrop: pointed at the top, round at the bottom.
    final r = w / 2;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * 0.62, h * 0.24, w, h * 0.42, w, h - r)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..cubicTo(0, h * 0.42, w * 0.38, h * 0.24, w / 2, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = armed
            ? TideColors.text
            : TideColors.text.withValues(alpha: 0.12 + 0.3 * progress),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = TideColors.text.withValues(alpha: armed ? 1 : 0.8),
    );
  }

  @override
  bool shouldRepaint(_DropletPainter old) =>
      old.armed != armed || old.progress != progress;
}

/// The visible handle at the top of the home screen: a short bar and the
/// caption "Pull down to log". Tapping it opens the log flow.
class LogHandle extends StatelessWidget {
  const LogHandle({super.key, required this.onTap});

  final VoidCallback onTap;

  static const handleKey = ValueKey<String>('log-handle');
  static const caption = 'Pull down to log';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      onTap: onTap,
      label: 'Pull down to log an expense',
      excludeSemantics: true,
      child: InkWell(
        key: handleKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 140),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: TideColors.text.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  caption,
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
