import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_mode.dart';
import '../theme/app_theme.dart';

/// How the logo is drawn.
enum LogoStyle {
  /// Rounded-square badge with background (in-app, legacy Android icon).
  badge,

  /// Full-bleed square with background (iOS masks the corners itself).
  square,

  /// Only the symbol on transparent, inside the Android adaptive-icon safe zone.
  foreground,

  /// Only the background (Android adaptive-icon back layer).
  background,

  /// White silhouette for Android 13+ themed (monochrome) icons.
  monochrome,
}

/// Brand colours of each mode's logo (more vivid than the app background).
class LogoColors {
  const LogoColors({required this.bgTop, required this.bgBottom, required this.a, required this.b, required this.glow});

  final Color bgTop;
  final Color bgBottom;

  /// The two "people" (left / right shape).
  final Color a;
  final Color b;
  final Color glow;

  static LogoColors of(AppMode mode) => switch (mode) {
        AppMode.general => const LogoColors(
            bgTop: Color(0xFF1A2747),
            bgBottom: Color(0xFF0A0F1C),
            a: Color(0xFF4C8DFF),
            b: Color(0xFF22C7E6),
            glow: Color(0xFF4C8DFF),
          ),
        AppMode.love => const LogoColors(
            bgTop: Color(0xFF3A1650),
            bgBottom: Color(0xFF130A24),
            a: Color(0xFFFF5E8A),
            b: Color(0xFF8B5CF6),
            glow: Color(0xFFFF5E8A),
          ),
        AppMode.friends => const LogoColors(
            bgTop: Color(0xFF123B36),
            bgBottom: Color(0xFF07171A),
            a: Color(0xFFFF7A45),
            b: Color(0xFF2EC4B6),
            glow: Color(0xFF2EC4B6),
          ),
      };
}

/// The Duet logo: two people (overlapping shapes) watching together (play button).
///   general → two overlapping circles · love → a heart of two lobes · friends → two bouncy circles + spark
class DuetLogoPainter extends CustomPainter {
  const DuetLogoPainter({required this.mode, this.style = LogoStyle.badge});

  final AppMode mode;
  final LogoStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final origin = Offset((size.width - s) / 2, (size.height - s) / 2);
    final colors = LogoColors.of(mode);
    final full = origin & Size(s, s);

    // ---- background
    if (style == LogoStyle.badge || style == LogoStyle.square || style == LogoStyle.background) {
      final bgPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.bgTop, colors.bgBottom],
        ).createShader(full);
      if (style == LogoStyle.badge) {
        canvas.drawRRect(RRect.fromRectAndRadius(full, Radius.circular(s * 0.23)), bgPaint);
      } else {
        canvas.drawRect(full, bgPaint);
      }
      // Soft light from the top-left.
      final light = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.6, -0.7),
          radius: 0.9,
          colors: [colors.glow.withValues(alpha: 0.28), colors.glow.withValues(alpha: 0)],
        ).createShader(full);
      if (style == LogoStyle.badge) {
        canvas.drawRRect(RRect.fromRectAndRadius(full, Radius.circular(s * 0.23)), light);
      } else {
        canvas.drawRect(full, light);
      }
    }
    if (style == LogoStyle.background) return;

    // ---- symbol box (the adaptive foreground must stay inside the ~61% safe zone)
    final scale = switch (style) {
      LogoStyle.foreground || LogoStyle.monochrome => 0.56,
      LogoStyle.square => 0.68,
      _ => 0.74,
    };
    final box = Rect.fromCenter(center: full.center, width: s * scale, height: s * scale);
    Offset p(double x, double y) => Offset(box.left + box.width * x, box.top + box.height * y);
    double u(double v) => box.width * v;

    final mono = style == LogoStyle.monochrome;
    canvas.saveLayer(full, Paint());

    // Two "people".
    final Path left;
    final Path right;
    Offset playCenter;
    var playSize = 0.24;
    switch (mode) {
      case AppMode.general:
        left = Path()..addOval(Rect.fromCircle(center: p(0.37, 0.5), radius: u(0.31)));
        right = Path()..addOval(Rect.fromCircle(center: p(0.63, 0.5), radius: u(0.31)));
        playCenter = p(0.515, 0.5);
      case AppMode.love:
        final heart = _heart(box);
        // Split the heart into a left and right half so each "person" has a colour.
        left = Path.combine(PathOperation.intersect, heart, Path()..addRect(Rect.fromLTRB(box.left - 1, box.top - 1, box.center.dx, box.bottom + 1)));
        right = Path.combine(PathOperation.intersect, heart, Path()..addRect(Rect.fromLTRB(box.center.dx, box.top - 1, box.right + 1, box.bottom + 1)));
        playCenter = p(0.52, 0.47);
        playSize = 0.27;
      case AppMode.friends:
        left = Path()..addOval(Rect.fromCircle(center: p(0.36, 0.56), radius: u(0.29)));
        right = Path()..addOval(Rect.fromCircle(center: p(0.64, 0.44), radius: u(0.29)));
        playCenter = p(0.51, 0.5);
    }

    // Glow under the symbol.
    if (!mono) {
      final union = Path.combine(PathOperation.union, left, right);
      canvas.drawPath(
        union.shift(Offset(0, u(0.03))),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, u(0.05)),
      );
    }

    Paint fill(Color c1, Color c2, Rect bounds) => mono
        ? (Paint()..color = Colors.white)
        : (Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c1, c2],
          ).createShader(bounds));

    canvas.drawPath(left, fill(Color.lerp(colors.a, Colors.white, 0.12)!, colors.a, left.getBounds()));
    if (mode == AppMode.love) {
      canvas.drawPath(right, fill(colors.b, Color.lerp(colors.b, Colors.black, 0.1)!, right.getBounds()));
    } else {
      // Overlap shows through (the two of you together).
      canvas.saveLayer(full, Paint()..blendMode = mono ? BlendMode.srcOver : BlendMode.screen);
      canvas.drawPath(right, fill(colors.b, Color.lerp(colors.b, Colors.black, 0.08)!, right.getBounds()));
      canvas.restore();
    }

    // Friends: little "excitement" lines bursting from the teal circle.
    if (mode == AppMode.friends) {
      final spark = Paint()
        ..color = mono ? Colors.white : const Color(0xFFFFD166)
        ..strokeWidth = u(0.045)
        ..strokeCap = StrokeCap.round;
      final center = p(0.64, 0.44);
      for (final degrees in [-75.0, -45.0, -15.0]) {
        final angle = degrees * math.pi / 180;
        final dir = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(center + dir * u(0.35), center + dir * u(0.42), spark);
      }
    }

    // Play button: white on the heart; on the bright overlap of the two circles it is
    // a dark "cut-out" for contrast; a real cut-out in the monochrome icon.
    final play = _roundedPlay(playCenter, u(playSize));
    final cutOut = mode != AppMode.love;
    final playPaint = Paint()
      ..color = mono ? Colors.black : (cutOut ? colors.bgBottom : Colors.white)
      ..blendMode = mono ? BlendMode.clear : BlendMode.srcOver
      ..style = PaintingStyle.fill;
    if (!mono && !cutOut) {
      canvas.drawPath(
        play.shift(Offset(0, u(0.012))),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, u(0.02)),
      );
    }
    canvas.drawPath(play, playPaint);
    canvas.restore();
  }

  /// A heart made of two round lobes (the two of you) meeting at the point.
  static Path _heart(Rect box) {
    final w = box.width;
    final h = box.height;
    Offset p(double x, double y) => Offset(box.left + w * x, box.top + h * y);
    return Path()
      ..moveTo(p(0.5, 0.92).dx, p(0.5, 0.92).dy)
      ..cubicTo(p(0.36, 0.80).dx, p(0.36, 0.80).dy, p(0.04, 0.62).dx, p(0.04, 0.62).dy, p(0.05, 0.38).dx, p(0.05, 0.38).dy)
      ..cubicTo(p(0.06, 0.16).dx, p(0.06, 0.16).dy, p(0.24, 0.06).dx, p(0.24, 0.06).dy, p(0.36, 0.08).dx, p(0.36, 0.08).dy)
      ..cubicTo(p(0.44, 0.09).dx, p(0.44, 0.09).dy, p(0.49, 0.15).dx, p(0.49, 0.15).dy, p(0.5, 0.21).dx, p(0.5, 0.21).dy)
      ..cubicTo(p(0.51, 0.15).dx, p(0.51, 0.15).dy, p(0.56, 0.09).dx, p(0.56, 0.09).dy, p(0.64, 0.08).dx, p(0.64, 0.08).dy)
      ..cubicTo(p(0.76, 0.06).dx, p(0.76, 0.06).dy, p(0.94, 0.16).dx, p(0.94, 0.16).dy, p(0.95, 0.38).dx, p(0.95, 0.38).dy)
      ..cubicTo(p(0.96, 0.62).dx, p(0.96, 0.62).dy, p(0.64, 0.80).dx, p(0.64, 0.80).dy, p(0.5, 0.92).dx, p(0.5, 0.92).dy)
      ..close();
  }

  /// Play triangle with softly rounded corners, optically centred.
  static Path _roundedPlay(Offset center, double size) {
    final h = size;
    final w = size * 0.92;
    final cx = center.dx + w * 0.08;
    final a = Offset(cx - w / 2, center.dy - h / 2);
    final b = Offset(cx - w / 2, center.dy + h / 2);
    final c = Offset(cx + w / 2, center.dy);
    final r = size * 0.14;
    Offset towards(Offset from, Offset to, double d) {
      final v = to - from;
      return from + v / v.distance * d;
    }

    final path = Path();
    final corners = [a, b, c];
    for (var i = 0; i < 3; i++) {
      final prev = corners[(i + 2) % 3];
      final cur = corners[i];
      final next = corners[(i + 1) % 3];
      final p1 = towards(cur, prev, r);
      final p2 = towards(cur, next, r);
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(DuetLogoPainter oldDelegate) => oldDelegate.mode != mode || oldDelegate.style != style;
}

/// The logo as a widget; follows the shared theme unless [mode] is given.
class DuetLogo extends StatelessWidget {
  const DuetLogo({super.key, this.size = 48, this.mode, this.style = LogoStyle.badge});

  final double size;
  final AppMode? mode;
  final LogoStyle style;

  @override
  Widget build(BuildContext context) {
    final current = mode ?? context.palette.mode;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: SizedBox(
        key: ValueKey(current),
        width: size,
        height: size,
        child: CustomPaint(painter: DuetLogoPainter(mode: current, style: style)),
      ),
    );
  }
}
