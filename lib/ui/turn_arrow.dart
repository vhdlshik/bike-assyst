import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../route/route.dart';

/// A bold turn arrow: a stem coming up from the bottom that bends toward the
/// turn, drawn in a single bright color so it reads on see-through glasses.
class TurnArrow extends StatelessWidget {
  const TurnArrow({super.key, required this.direction, this.size = 160, this.color = Colors.white});

  final TurnDirection direction;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _TurnArrowPainter(direction, color),
      );
}

class _TurnArrowPainter extends CustomPainter {
  _TurnArrowPainter(this.direction, this.color);

  final TurnDirection direction;
  final Color color;

  double get _bendDegrees => switch (direction) {
        TurnDirection.slightLeft => -45,
        TurnDirection.left => -90,
        TurnDirection.sharpLeft => -135,
        TurnDirection.uTurn => -180,
        TurnDirection.slightRight => 45,
        TurnDirection.right => 90,
        TurnDirection.sharpRight => 135,
        TurnDirection.arrive => 0,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    if (direction == TurnDirection.arrive) {
      final c = Offset(size.width / 2, size.height / 2);
      canvas.drawCircle(c, s * 0.3, stroke);
      canvas.drawCircle(c, s * 0.1, fill);
      return;
    }

    final bend = Offset(size.width / 2, size.height * 0.55);
    final start = Offset(size.width / 2, size.height * 0.95);
    final rad = _bendDegrees * math.pi / 180;
    // Heading 0 = up the screen; positive turns clockwise (right).
    final dir = Offset(math.sin(rad), -math.cos(rad));
    final legLen = direction == TurnDirection.uTurn ? s * 0.28 : s * 0.32;

    final path = Path()..moveTo(start.dx, start.dy)..lineTo(bend.dx, bend.dy);
    Offset tip;
    if (direction == TurnDirection.uTurn) {
      final r = s * 0.16;
      final center = bend + Offset(-r, 0);
      path.arcTo(Rect.fromCircle(center: center, radius: r), 0, -math.pi, false);
      final down = Offset(center.dx - r, center.dy);
      tip = down + Offset(0, legLen);
      path.lineTo(tip.dx, tip.dy - s * 0.08);
    } else {
      tip = bend + dir * legLen;
      final shaftEnd = tip - dir * (s * 0.12);
      path.lineTo(shaftEnd.dx, shaftEnd.dy);
    }
    canvas.drawPath(path, stroke);

    final headDir = direction == TurnDirection.uTurn ? const Offset(0, 1) : dir;
    final normal = Offset(-headDir.dy, headDir.dx);
    final headLen = s * 0.22;
    final base = tip - headDir * headLen;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + normal * headLen * 0.6).dx, (base + normal * headLen * 0.6).dy)
      ..lineTo((base - normal * headLen * 0.6).dx, (base - normal * headLen * 0.6).dy)
      ..close();
    canvas.drawPath(head, fill);
  }

  @override
  bool shouldRepaint(_TurnArrowPainter old) => old.direction != direction || old.color != color;
}
