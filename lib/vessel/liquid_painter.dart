import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../theme/tide_theme.dart';
import 'liquid_motion.dart';

/// Base of the four painters that can fill the Vessel's canvas. Each draws
/// from a [LiquidMotion] and repaints whenever it changes.
abstract class VesselPainter extends CustomPainter {
  VesselPainter(this.motion) : super(repaint: motion);

  final LiquidMotion motion;

  @override
  bool shouldRepaint(covariant VesselPainter oldDelegate) =>
      oldDelegate.runtimeType != runtimeType || oldDelegate.motion != motion;

  /// The colour the liquid darkens to at the bottom of the screen.
  static Color deep(Color color) => Color.lerp(color, TideColors.ink, 0.42)!;
}

/// The liquid drawn by `shaders/liquid.frag`. The normal painter on a device.
class ShaderLiquidPainter extends VesselPainter {
  ShaderLiquidPainter(this.shader, super.motion);

  final ui.FragmentShader shader;

  @override
  void paint(Canvas canvas, Size size) {
    final color = motion.color;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, motion.time)
      ..setFloat(3, motion.height)
      ..setFloat(4, motion.lean)
      ..setFloat(5, motion.slosh)
      ..setFloat(6, color.r)
      ..setFloat(7, color.g)
      ..setFloat(8, color.b);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant VesselPainter oldDelegate) =>
      super.shouldRepaint(oldDelegate) ||
      (oldDelegate as ShaderLiquidPainter).shader != shader;
}

/// The same moving liquid drawn with paths. Used when the shader is not
/// available: while it loads, if it fails to compile on a target, and in
/// widget tests.
class PathLiquidPainter extends VesselPainter {
  PathLiquidPainter(super.motion);

  static const double _step = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final color = motion.color;
    final level = size.height - motion.height;

    final back = Path()..moveTo(0, size.height);
    final front = Path()..moveTo(0, size.height);
    for (var x = 0.0; ; x += _step) {
      final px = x > size.width ? size.width : x;
      back.lineTo(
        px,
        level -
            5 +
            motion.slope(px, size.width) +
            motion.ripple(px + 140, phase: 2.6) * 1.35,
      );
      front.lineTo(px, level + motion.surfaceOffset(px, size.width));
      if (px >= size.width) break;
    }
    back
      ..lineTo(size.width, size.height)
      ..close();
    front
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      back,
      Paint()..color = Color.lerp(TideColors.ink, color, 0.45)!,
    );
    canvas.drawPath(
      front,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, level),
          Offset(0, size.height),
          [color, VesselPainter.deep(color)],
        ),
    );
  }
}

/// Still water: a flat, unmoving level in the band colour.
class StillLiquidPainter extends VesselPainter {
  StillLiquidPainter(super.motion);

  @override
  void paint(Canvas canvas, Size size) {
    final color = motion.color;
    final level = size.height - motion.height;
    final rect = Rect.fromLTRB(0, level, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomLeft, [
          color,
          VesselPainter.deep(color),
        ]),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, level, size.width, 1.5),
      Paint()..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.3)!,
    );
  }
}

/// The overspent band: coral hatching with a dashed top edge, in place of
/// liquid when the month is below the line.
class OverspentBandPainter extends VesselPainter {
  OverspentBandPainter(super.motion);

  static const double _stripe = 10;

  @override
  void paint(Canvas canvas, Size size) {
    const coral = TideColors.coral;
    final top = size.height - motion.height;
    final rect = Rect.fromLTRB(0, top, size.width, size.height);

    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = coral.withValues(alpha: 0.2));
    // 45 degree stripes, 10 on and 10 off, measured across the stripe. They
    // are anchored to the bottom-left corner so that they do not slide as
    // the band grows.
    final stripes = Paint()
      ..color = coral.withValues(alpha: 0.44)
      ..strokeWidth = _stripe
      ..style = PaintingStyle.stroke;
    const pitch = _stripe * 2 * 1.41421356;
    final h = rect.height;
    for (var x = -h - pitch; x < size.width + pitch; x += pitch) {
      canvas.drawLine(
        Offset(x - _stripe, size.height + _stripe),
        Offset(x + h + _stripe, top - _stripe),
        stripes,
      );
    }
    canvas.restore();

    final dash = Paint()
      ..color = coral
      ..strokeWidth = 2;
    for (var x = 0.0; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, top), Offset(x + 8, top), dash);
    }
  }
}
