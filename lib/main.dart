import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

void main() => runApp(const MyApp());

const _font = 'ShipporiMincho';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Current Color',
      theme: ThemeData(fontFamily: _font),
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
  static const _bgL = 0.32;
  static const _bgC = 0.03;

  // Text: same hue as the background, with lightness chosen so the WCAG
  // contrast ratio against the background is exactly this value.
  static const _contrast = 3.0; // WCAG minimum for large text

  // Hue difference between the top and bottom of the gradient.
  static const _spread = 60.0;

  // Type sizes and spacing on a golden-ratio scale: step(n) = base × φⁿ,
  // where base = colored area height / φ⁸, so everything scales with it.
  static const _phi = 1.618;

  // The colored area is letterboxed to the cinemascope ratio, always keeping
  // at least _minBand of the height black at the top and at the bottom.
  static const _cinema = 2.39;
  static const _minBand = 0.05;

  // Advances in Shippori Mincho, in em: widest digit ("7") and widest hex
  // character ("D").
  static const _digitWidth = 0.545;
  static const _hexWidth = 0.782;

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
    final rgb = bg.toARGB32() & 0xFFFFFF;
    final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    final size = MediaQuery.sizeOf(context);
    final area = min(size.height * (1 - 2 * _minBand), size.width / _cinema);
    final base = area / pow(_phi, 8);
    double step(int n) => base * pow(_phi, n);
    TextStyle style(int n, Color color) =>
        // Font set explicitly: the hue wheel paints text directly and does
        // not inherit the theme.
        TextStyle(
            fontFamily: _font, color: color, fontSize: step(n), height: 1);
    // Wide tracking (half an em between characters). The font has no
    // tabular figures, so each hex digit sits in a fixed [cell] (in em) to
    // keep the text from jittering as it changes.
    Widget tracked(String text, TextStyle s, [double cell = _digitWidth]) {
      final em = s.fontSize!;
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: em / 2,
        children: [
          for (final ch in text.split(''))
            if ('0123456789ABCDEF'.contains(ch))
              SizedBox(
                width: em * cell,
                child: Text(ch, style: s, textAlign: TextAlign.center),
              )
            else
              Text(ch, style: s),
        ],
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            height: area,
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
                  const Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _Scanlines()),
                    ),
                  ),
                  // Date at the top, color code at the bottom, time centered.
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: step(2)),
                      child: tracked(_date.format(_now), style(1, fg)),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: size.width * 0.9),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            tracked(_time.format(_now), style(3, fg)),
                            SizedBox(height: step(0)),
                            tracked(_ms.format(_now), style(1, fg)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: step(2)),
                      child:
                          tracked('Color(0xFF$hex)', style(1, fg), _hexWidth),
                    ),
                  ),
                  if (_wheel)
                    Positioned(
                      right: step(0),
                      bottom: step(0),
                      child: CustomPaint(
                        size: Size.square(step(5)),
                        painter: _HueWheel(lch.h, spread, bg, fg, style(0, fg)),
                      ),
                    ),
                ],
              ),
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
    // All lengths are in units of 1/160 of the wheel, so it scales as a whole.
    final u = size.width / 160;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 20 * u;
    final ring = Rect.fromCircle(center: c, radius: r);
    Offset at(double deg, double radius) =>
        c + Offset(cos(_rad(deg)), sin(_rad(deg))) * radius;
    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    // Dim full ring, then the active range at full strength.
    canvas.drawCircle(c, r, stroke(3 * u)..shader = _sweep(ring, 0.25));
    if (spread > 0) {
      canvas.drawArc(ring, _rad(hue - spread / 2), spread * pi / 180, false,
          stroke(3 * u)..shader = _sweep(ring, 1));
    }

    // Ticks every 30°, longer at 0°.
    for (var d = 0; d < 360; d += 30) {
      canvas.drawLine(
        at(d.toDouble(), r + 8 * u),
        at(d.toDouble(), r + (d == 0 ? 16 : 12) * u),
        stroke(u)..color = fg,
      );
    }

    // Needle and marker filled with the current background.
    canvas.drawLine(
        at(hue, r - 14 * u), at(hue, r + 14 * u), stroke(1.5 * u)..color = fg);
    canvas.drawCircle(at(hue, r), 6 * u, Paint()..color = bg);
    canvas.drawCircle(at(hue, r), 6 * u, stroke(1.5 * u)..color = fg);

    // Caption and degrees in the center.
    final captionSize = style.fontSize! / 1.618;
    final tracking = captionSize / 2; // same half-em tracking as the clock
    final caption = TextPainter(
      text: TextSpan(
        text: 'HUE',
        style: style.copyWith(fontSize: captionSize, letterSpacing: tracking),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    TextPainter text(String s) => TextPainter(
          text: TextSpan(text: s, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
    final label = text('${hue.round() % 360}');
    final degree = text('°');
    final top = c.dy - (caption.height + label.height) / 2;
    // Tracking trails the last letter, so shift right by half of it.
    caption.paint(canvas, Offset(c.dx - (caption.width - tracking) / 2, top));
    // Center the number alone; the degree sign hangs to its right.
    final labelLeft = c.dx - label.width / 2;
    label.paint(canvas, Offset(labelLeft, top + caption.height));
    degree.paint(canvas, Offset(labelLeft + label.width, top + caption.height));
  }

  @override
  bool shouldRepaint(_HueWheel old) =>
      old.hue != hue || old.spread != spread || old.bg != bg || old.fg != fg;
}

/// Faint horizontal scanlines for a film-like texture.
class _Scanlines extends CustomPainter {
  const _Scanlines();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var y = 0.5; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Scanlines old) => false;
}
