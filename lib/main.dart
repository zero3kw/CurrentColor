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
    return MaterialApp(
      title: 'Current Color',
      theme: ThemeData(fontFamily: 'RictyDiminished'),
      home: const MouseRegion(
        cursor: SystemMouseCursors.none,
        child: ClockPage(),
      ),
    );
  }
}

/// OKLCH color: perceptual lightness [l] (0–1), chroma [c], hue [h] in degrees.
typedef Lch = ({double l, double c, double h});

/// Converts OKLCH to sRGB (https://bottosson.github.io/posts/oklab/).
/// Channels outside the sRGB gamut are clamped.
Color oklch(Lch p) {
  final a = p.c * cos(p.h * pi / 180);
  final b = p.c * sin(p.h * pi / 180);
  double cube(double x) => x * x * x;
  final l = cube(p.l + 0.3963377774 * a + 0.2158037573 * b);
  final m = cube(p.l - 0.1055613458 * a - 0.0638541728 * b);
  final s = cube(p.l - 0.0894841775 * a - 1.2914855480 * b);
  double encode(double x) {
    x = x.clamp(0.0, 1.0);
    return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055;
  }

  return Color.from(
    alpha: 1,
    red: encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    green: encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    blue: encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
  );
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
  //   3: random color every second (any hue, lightness and chroma),
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

  // Background (modes 1/2): fixed perceptual lightness and chroma in OKLCH,
  // so every hue looks equally bright and equally muted.
  static const _bgL = 0.44;
  static const _bgC = 0.03;

  // Text and frame: same hue as the background, with lightness chosen so the
  // WCAG contrast ratio against the background is exactly this value.
  static const _contrast = 3.0; // WCAG minimum for large text
  // The frame sits halfway between background and text (contrast is
  // multiplicative, so halfway is the square root).
  static final _frameContrast = sqrt(_contrast);

  // Hue difference between the top and bottom of the gradient.
  static const _spread = 60.0;

  // Type sizes and spacing on a golden-ratio scale: step(n) = base × φⁿ,
  // where base = screen height / φ⁸, so everything scales with the
  // screen; the frame is sized by its content.
  static const _phi = 1.618;
  static const _frameMaxWidth = 0.6; // fraction of the screen width

  late final Ticker _ticker;
  DateTime _now = DateTime.now();
  int _mode = 0;
  bool _gradient = false; // toggled with the G key
  bool _wheel = false; // hue wheel view, toggled with the H key

  // Random color for a given second, seeded by it so every device agrees.
  static Lch _random(int second) {
    final r = Random(second);
    return (
      h: r.nextDouble() * 360,
      l: 0.25 + 0.35 * r.nextDouble(),
      c: 0.12 * r.nextDouble(),
    );
  }

  // Background at time [t] (seconds since epoch), shifted by [dh] degrees of
  // hue (modes 1/2) or the equivalent fraction of a second (mode 3).
  Lch _lchAt(double t, double dh) {
    if (_mode == 2) {
      // Map the ±spread/2 degree gradient offset to a fraction of a second.
      final x = t + dh / 120;
      final n = x.floor();
      final f = x - n;
      final a = _random(n), b = _random(n + 1);
      final turn = (b.h - a.h + 540) % 360 - 180; // shortest way round
      return (
        l: a.l + (b.l - a.l) * f,
        c: a.c + (b.c - a.c) * f,
        h: (a.h + turn * f) % 360,
      );
    }
    return (l: _bgL, c: _bgC, h: (_wheelHue(t) + dh) % 360);
  }

  // Hue in degrees for modes 1/2: mode 1 steps once per second,
  // mode 2 changes continuously.
  double _wheelHue(double t) {
    final p = _periods[_mode];
    final s = _mode == 0 ? t.floorToDouble() : t;
    return s % p * 360 / p;
  }

  // Foreground of the same hue whose contrast against [bg] is [ratio].
  // Uses Y ≈ L³, which holds closely at this low chroma.
  static Color _foreground(Color bg, double hue, double ratio) {
    final y = ratio * (bg.computeLuminance() + 0.05) - 0.05;
    return oklch((l: pow(y, 1 / 3).toDouble(), c: _bgC, h: hue));
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
    final lch = _lchAt(t, 0);
    final bg = oklch(lch);
    final fg = _foreground(bg, lch.h, _contrast);
    final frame = _foreground(bg, lch.h, _frameContrast);
    final rgb = bg.toARGB32() & 0xFFFFFF;
    final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    final size = MediaQuery.sizeOf(context);
    final base = size.height / pow(_phi, 8);
    double step(int n) => base * pow(_phi, n);
    TextStyle style(int n) =>
        TextStyle(color: fg, fontSize: step(n), height: 1);

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
                colors: [
                  oklch(_lchAt(t, -spread / 2)),
                  oklch(_lchAt(t, spread / 2)),
                ],
              ),
            ),
            child: Stack(
              children: [
                Center(
                  // The frame hugs its content; on narrow screens the whole
                  // frame scales down to fit the maximum width.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: size.width * _frameMaxWidth),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                    // Wider than tall: side padding is the vertical padding × φ³.
                        padding: EdgeInsets.symmetric(
                            horizontal: step(5), vertical: step(2)),
                    decoration: BoxDecoration(
                      border: Border.all(color: frame, width: step(-4)),
                    ),
                      child: Column(
                        children: [
                          Text(_date.format(_now), style: style(0)),
                          Text(_time.format(_now), style: style(2)),
                          Text(_ms.format(_now), style: style(0)),
                          SizedBox(height: step(-1)), // separates time from color
                          Text('Color(0xFF$hex)', style: style(1)),
                        ],
                      ),
                    ),
                  ),
                  ),
                ),
                if (_wheel)
                  Positioned(
                    right: step(0),
                    bottom: step(0),
                    child: CustomPaint(
                      size: Size.square(step(4)),
                      painter: _HueWheel(lch.h, spread, bg, fg, style(0)),
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

/// Hue wheel (0° at the top, clockwise, OKLCH hue): a dim ring with the range
/// shown on screen lit up, ticks every 30°, and a needle at the current hue.
class _HueWheel extends CustomPainter {
  _HueWheel(this.hue, this.spread, this.bg, this.fg, this.style);

  final double hue;
  final double spread;
  final Color bg; // current background, used to fill the marker
  final Color fg; // text color, used for ticks, needle and labels
  final TextStyle style;

  static double _rad(double deg) => (deg - 90) * pi / 180;

  static Shader _sweep(Rect rect, double alpha) => SweepGradient(
        transform: const GradientRotation(-pi / 2),
        colors: [
          for (var h = 0; h <= 360; h += 30)
            oklch((l: 0.7, c: 0.12, h: h.toDouble())).withValues(alpha: alpha),
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
        stroke(1)..color = fg,
      );
    }

    // Needle and marker filled with the current background.
    canvas.drawLine(at(hue, r - 14), at(hue, r + 14), stroke(1.5)..color = fg);
    canvas.drawCircle(at(hue, r), 6, Paint()..color = bg);
    canvas.drawCircle(at(hue, r), 6, stroke(1.5)..color = fg);

    // Caption and degrees in the center.
    final caption = TextPainter(
      text: TextSpan(
        text: 'HUE',
        style: style.copyWith(
            fontSize: style.fontSize! / 1.618 / 1.618, letterSpacing: 3),
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
      old.hue != hue || old.spread != spread || old.bg != bg || old.fg != fg;
}
