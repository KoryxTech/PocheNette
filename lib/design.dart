import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Palette logo PocheNette — navy + vert croissance.
const navy = Color(0xff001B3D);
const navyMid = Color(0xff0A3A6B);
const navyDeep = Color(0xff000F24);
const emerald = Color(0xff00B87A);
const mint = Color(0xff2EE2A2);
const mintWash = Color(0xffD4F8EA);
const ink = Color(0xff0B1A2E);
const muted = Color(0xff526278);
const rose = Color(0xffd81c50);
const canvas = Color(0xffF5F8FC);
const border = Color(0xffE2E8F0);
const categoryColors = [
  Color(0xfffb7185),
  Color(0xff38bdf8),
  Color(0xff818cf8),
  Color(0xfffbbf24),
  Color(0xff2dd4bf),
  Color(0xffc084fc),
];
const numberStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontFeatures: [FontFeature.tabularFigures()],
);

ThemeData pocheTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: emerald,
    primary: emerald,
    onPrimary: Colors.white,
    secondaryContainer: mintWash,
    onSecondaryContainer: navy,
    surface: Colors.white,
    onSurface: ink,
    onSurfaceVariant: muted,
    error: rose,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Plus Jakarta Sans',
    scaffoldBackgroundColor: canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: shape.copyWith(side: const BorderSide(color: border)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Colors.white, shape: shape),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: canvas,
      shape: shape,
      showDragHandle: true,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      height: 72,
      indicatorColor: mintWash,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: canvas,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      titleTextStyle: TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontWeight: FontWeight.w700,
        color: ink,
        fontSize: 15,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        color: muted,
        fontSize: 12,
        height: 1.45,
      ),
    ),
  );
}

class IconPlate extends StatelessWidget {
  const IconPlate(this.icon, {super.key, this.color = emerald});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(14),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 22, color: color),
  );
}

class SummaryPanel extends StatelessWidget {
  const SummaryPanel({
    super.key,
    required this.label,
    required this.amount,
    required this.footer,
    this.progress,
  });

  final String label;
  final String amount;
  final String footer;
  final double? progress;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [navy, navyMid],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: mint,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount,
            maxLines: 1,
            style: numberStyle.copyWith(color: Colors.white, fontSize: 30),
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 14),
          PocheProgress(value: progress!, color: mint, track: navyDeep),
        ],
        const SizedBox(height: 10),
        Text(
          footer,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .78),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

class BalanceRing extends StatelessWidget {
  const BalanceRing({
    super.key,
    required this.values,
    required this.child,
    this.diameter = 206,
  });
  final double diameter;
  final List<int> values;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: diameter,
    child: TweenAnimationBuilder<double>(
      key: ValueKey(values.join(',')),
      tween: Tween(begin: 0, end: 1),
      duration: motionDuration(context, 480),
      curve: Curves.easeOutCubic,
      builder: (context, reveal, center) =>
          CustomPaint(painter: _RingPainter(values, reveal), child: center),
      child: Padding(
        padding: const EdgeInsets.all(27),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x0f0f172a),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.values, this.reveal);
  final double reveal;
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 - 11;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 19;
    canvas.drawCircle(center, radius, paint..color = border);
    final total = values.fold(0, (sum, value) => sum + value);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep == 0) continue;
      final gap = values[i] == total ? 0.0 : math.min(.045, sweep * .2);
      canvas.drawArc(
        rect,
        start + gap,
        (sweep - gap * 2) * reveal,
        false,
        paint..color = categoryColors[i % categoryColors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.reveal != reveal;
}

Duration motionDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class PocheProgress extends StatelessWidget {
  const PocheProgress({
    super.key,
    required this.value,
    this.color = emerald,
    this.track = border,
  });
  final double value;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value),
    duration: motionDuration(context, 380),
    curve: Curves.easeOutCubic,
    builder: (context, progress, _) => LinearProgressIndicator(
      value: progress,
      semanticsValue: '${(value * 100).round()} %',
      color: color,
      backgroundColor: track,
      borderRadius: BorderRadius.circular(8),
      minHeight: 7,
    ),
  );
}
