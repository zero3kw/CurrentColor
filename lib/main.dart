import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white38);
    return MaterialApp(
      title: 'Current Color',
      theme: ThemeData(
        fontFamily: 'RictyDiminished',
        textTheme: const TextTheme(
          displayLarge: style,
          displaySmall: style,
          titleLarge: style,
        ),
      ),
      home: const MouseRegion(
        cursor: SystemMouseCursors.none,
        child: ClockPage(),
      ),
    );
  }
}

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage>
    with SingleTickerProviderStateMixin {
  static final _date = DateFormat('yyyy-MM-dd');
  static final _time = DateFormat('HH:mm:ss');
  static final _ms = DateFormat('.SSS');

  // Modes, selected with keys 1/2/3 or Q/W/E:
  //   1: hue wheel in 6 min, one step per second
  //   2: hue wheel in 1 min, continuous
  //   3: random color every second (any hue, saturation and lightness),
  //      blending smoothly into the next one
  static const _periods = [360, 60]; // seconds per turn for modes 1 and 2
  // Physical keys, so they work regardless of IME state (top row or numpad).
  static const _keys = [
    [
      PhysicalKeyboardKey.digit1,
      PhysicalKeyboardKey.numpad1,
      PhysicalKeyboardKey.keyQ
    ],
    [
      PhysicalKeyboardKey.digit2,
      PhysicalKeyboardKey.numpad2,
      PhysicalKeyboardKey.keyW
    ],
    [
      PhysicalKeyboardKey.digit3,
      PhysicalKeyboardKey.numpad3,
      PhysicalKeyboardKey.keyE
    ],
  ];

  // Hue difference between the top and bottom of the gradient.
  static const _spread = 60.0;

  late final Ticker _ticker;
  DateTime _now = DateTime.now();
  int _mode = 0;
  bool _gradient = false; // toggled with the G key
  bool _wheel = false; // hue wheel view, toggled with the H key

  // The color as actually seen: 40% of the tone over black.
  static Color _shade(double hue, [double sat = 0.5, double light = 0.8]) =>
      Color.lerp(
        Colors.black,
        HSLColor.fromAHSL(1, hue % 360, sat, light).toColor(),
        0.4,
      )!;

  // Random color for a given second, seeded by it so every device agrees.
  static Color _random(int second) {
    final r = Random(second);
    return _shade(r.nextDouble() * 360, r.nextDouble(), r.nextDouble());
  }

  // Color at time [t] (seconds since epoch), shifted by [dh] degrees of hue
  // (modes 1/2) or the equivalent fraction of a second (mode 3).
  Color _colorAt(double t, double dh) {
    if (_mode == 2) {
      // Map the ±spread/2 degree gradient offset to a fraction of a second.
      final x = t + dh / 120;
      final n = x.floor();
      return Color.lerp(_random(n), _random(n + 1), x - n)!;
    }
    return _shade(_wheelHue(t) + dh);
  }

  // Hue in degrees for modes 1/2: mode 1 steps once per second,
  // mode 2 changes continuously.
  double _wheelHue(double t) {
    final p = _periods[_mode];
    final s = _mode == 0 ? t.floorToDouble() : t;
    return s % p * 360 / p;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.physicalKey;
    final i = _keys.indexWhere((k) => k.contains(key));
    if (i >= 0) {
      setState(() => _mode = i);
    } else if (key == PhysicalKeyboardKey.keyG) {
      setState(() => _gradient = !_gradient);
    } else if (key == PhysicalKeyboardKey.keyH) {
      setState(() => _wheel = !_wheel);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() => _now = DateTime.now()))
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _now.millisecondsSinceEpoch / 1000;
    final spread = _gradient ? _spread : 0.0;
    final color = _colorAt(t, 0);
    // Mode 3 has no hue of its own, so read it back from the color.
    final hue = _mode == 2 ? HSLColor.fromColor(color).hue : _wheelHue(t);
    final rgb = color.toARGB32() & 0xFFFFFF;
    final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    final text = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        // Black bands (5% of height) above and below the colored area.
        body: Padding(
          padding: EdgeInsets.symmetric(vertical: size.height * 0.05),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_colorAt(t, -spread / 2), _colorAt(t, spread / 2)],
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: size.width * 0.6,
                    padding: const EdgeInsets.all(50),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24, width: 4),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        children: [
                          Text(_date.format(_now), style: text.titleLarge),
                          Text(_time.format(_now), style: text.displayLarge),
                          Text(_ms.format(_now), style: text.titleLarge),
                          Text('Color(0xFF$hex)', style: text.displaySmall),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_wheel)
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: CustomPaint(
                      size: const Size.square(160),
                      painter: _HueWheel(hue, spread, color, text.titleLarge!),
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

/// Hue wheel (0° at the top, clockwise): a dim ring with the range shown on
/// screen lit up, ticks every 30°, and a needle at the current hue.
class _HueWheel extends CustomPainter {
  _HueWheel(this.hue, this.spread, this.color, this.style);

  final double hue;
  final double spread;
  final Color color; // current background color, used for the marker
  final TextStyle style;

  static double _rad(double deg) => (deg - 90) * pi / 180;

  static Shader _sweep(Rect rect, double alpha) => SweepGradient(
        transform: const GradientRotation(-pi / 2),
        colors: [
          for (var h = 0; h <= 360; h += 30)
            HSLColor.fromAHSL(alpha, h % 360, 1, 0.5).toColor(),
        ],
      ).createShader(rect);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 20;
    final ring = Rect.fromCircle(center: c, radius: r);
    Offset at(double deg, double radius) =>
        c + Offset(cos(_rad(deg)), sin(_rad(deg))) * radius;
    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    // Dim full ring, then the active range at full strength.
    canvas.drawCircle(c, r, stroke(3)..shader = _sweep(ring, 0.25));
    if (spread > 0) {
      canvas.drawArc(ring, _rad(hue - spread / 2), spread * pi / 180, false,
          stroke(3)..shader = _sweep(ring, 1));
    }

    // Ticks every 30°, longer at 0°.
    for (var d = 0; d < 360; d += 30) {
      canvas.drawLine(
        at(d.toDouble(), r + 8),
        at(d.toDouble(), r + (d == 0 ? 16 : 12)),
        stroke(1)..color = d == 0 ? Colors.white54 : Colors.white24,
      );
    }

    // Needle and marker filled with the current color.
    canvas.drawLine(
        at(hue, r - 14), at(hue, r + 14), stroke(1.5)..color = Colors.white70);
    canvas.drawCircle(at(hue, r), 6, Paint()..color = color);
    canvas.drawCircle(at(hue, r), 6, stroke(1.5)..color = Colors.white);

    // Caption and degrees in the center.
    final caption = TextPainter(
      text: TextSpan(
        text: 'HUE',
        style: style.copyWith(
            fontSize: 10, letterSpacing: 3, color: Colors.white38),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final label = TextPainter(
      text: TextSpan(text: '${hue.round() % 360}°', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = c.dy - (caption.height + label.height) / 2;
    caption.paint(canvas, Offset(c.dx - caption.width / 2, top));
    label.paint(canvas, Offset(c.dx - label.width / 2, top + caption.height));
  }

  @override
  bool shouldRepaint(_HueWheel old) =>
      old.hue != hue || old.spread != spread || old.color != color;
}
