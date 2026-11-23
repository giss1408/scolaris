import 'package:flutter/material.dart';

/// The Scolaris mark: a graduation cap on an open book. Same geometry as brand/scolaris-logo.svg (512 grid).
class ScolarisMarkPainter extends CustomPainter {
  const ScolarisMarkPainter({this.badge = true, this.cornerRadius = 112});

  /// 112 on a 512 grid (rounded badge); 0 for a full-bleed square (iOS app icon: the system rounds it).
  final double cornerRadius;

  /// Draw the teal rounded badge behind the mark (false: the cap and book only, e.g. on a teal surface).
  final bool badge;

  static const teal = Color(0xFF0F766E);
  static const tealDark = Color(0xFF0A5A54);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFBBF24);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    final fill = Paint()..style = PaintingStyle.fill;
    Path poly(List<Offset> p) => Path()..addPolygon(p, true);

    if (badge) canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 512, 512), Radius.circular(cornerRadius)), fill..color = teal);

    // open book
    final left = Path()
      ..moveTo(92, 304)
      ..quadraticBezierTo(174, 280, 256, 316)
      ..lineTo(256, 414)
      ..quadraticBezierTo(174, 378, 92, 402)
      ..close();
    final right = Path()
      ..moveTo(420, 304)
      ..quadraticBezierTo(338, 280, 256, 316)
      ..lineTo(256, 414)
      ..quadraticBezierTo(338, 378, 420, 402)
      ..close();
    canvas.drawPath(left, fill..color = Colors.white);
    canvas.drawPath(right, fill..color = const Color(0xFFE6F4F1));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..color = teal;
    canvas.drawLine(const Offset(256, 316), const Offset(256, 414), line);
    line
      ..strokeWidth = 7
      ..color = teal.withOpacity(0.28);
    for (final dy in [0.0, 28.0]) {
      canvas.drawPath(Path()..moveTo(122, 330 + dy)..quadraticBezierTo(166, 320 + dy, 222, 342 + dy), line);
      canvas.drawPath(Path()..moveTo(390, 330 + dy)..quadraticBezierTo(346, 320 + dy, 290, 342 + dy), line);
    }

    // cap base, board, tassel
    final base = Path()
      ..moveTo(176, 196)
      ..lineTo(176, 244)
      ..quadraticBezierTo(256, 284, 336, 244)
      ..lineTo(336, 196)
      ..lineTo(256, 226)
      ..close();
    canvas.drawPath(base, fill..color = tealDark);
    canvas.drawPath(poly(const [Offset(256, 92), Offset(408, 152), Offset(256, 212), Offset(104, 152)]), fill..color = amber);
    canvas.drawPath(poly(const [Offset(256, 92), Offset(408, 152), Offset(256, 212)]), fill..color = amberLight);
    canvas.drawLine(const Offset(388, 160), const Offset(388, 238), Paint()..color = amber..strokeWidth = 9..strokeCap = StrokeCap.round);
    canvas.drawCircle(const Offset(388, 248), 14, fill..color = amber);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ScolarisMarkPainter old) => old.badge != badge || old.cornerRadius != cornerRadius;
}

class ScolarisLogo extends StatelessWidget {
  const ScolarisLogo({super.key, this.size = 64, this.badge = true});
  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Scolaris',
        image: true,
        child: ExcludeSemantics(child: SizedBox(width: size, height: size, child: CustomPaint(painter: ScolarisMarkPainter(badge: badge)))),
      );
}

/// Mark + name, side by side (sign-in, about).
class ScolarisWordmark extends StatelessWidget {
  const ScolarisWordmark({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        ScolarisLogo(size: size),
        SizedBox(width: size * 0.3),
        Text('Scolaris', style: TextStyle(fontSize: size * 0.58, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: const Color(0xFF0F172A))),
      ]);
}
