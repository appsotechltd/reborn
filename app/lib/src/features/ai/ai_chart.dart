import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/ai_models.dart';
import '../../theme.dart';

/// Draws a chart Reborn AI made: bars, a line or a pie.
class AIChart extends StatelessWidget {
  const AIChart({super.key, required this.chart});

  final AIChartData chart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final palette = [
      c.amber,
      c.oxblood,
      theme.colorScheme.tertiary,
      c.success,
      c.muted,
      theme.colorScheme.secondary,
    ];
    final names = chart.kind == 'pie'
        ? chart.labels
        : chart.series.map((s) => s.name).toList();
    return Semantics(
      label: chart.description,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.inset,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chart.title.isNotEmpty)
              Text(chart.title, style: theme.textTheme.titleSmall),
            if (chart.unit.isNotEmpty)
              Text(
                chart.unit,
                style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: CustomPaint(
                painter: _ChartPainter(
                  chart: chart,
                  palette: palette,
                  line: c.line,
                  label: theme.textTheme.bodySmall!.copyWith(
                    color: c.muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            if (names.length > 1 || chart.kind == 'pie') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < names.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: palette[i % palette.length],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(names[i], style: theme.textTheme.bodySmall),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.chart,
    required this.palette,
    required this.line,
    required this.label,
  });

  final AIChartData chart;
  final List<Color> palette;
  final Color line;
  final TextStyle label;

  Color _color(int i) => palette[i % palette.length];

  double _value(AIChartSeries s, int i) =>
      i < s.values.length ? s.values[i] : 0;

  TextPainter _text(String s, double maxWidth) => TextPainter(
    text: TextSpan(text: s, style: label),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: math.max(1, maxWidth));

  static String _fmt(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (chart.labels.isEmpty || chart.series.isEmpty) return;
    if (chart.kind == 'pie') {
      _pie(canvas, size);
    } else {
      _axes(canvas, size);
    }
  }

  void _pie(Canvas canvas, Size size) {
    final s = chart.series.first;
    final values = [
      for (var i = 0; i < chart.labels.length; i++) math.max(0.0, _value(s, i)),
    ];
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final r = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = _color(i));
      start += sweep;
    }
  }

  void _axes(Canvas canvas, Size size) {
    final all = [for (final s in chart.series) ...s.values];
    final maxV = all.isEmpty ? 1.0 : math.max(all.reduce(math.max), 0.0);
    final minV = all.isEmpty ? 0.0 : math.min(all.reduce(math.min), 0.0);
    final span = maxV - minV == 0 ? 1.0 : maxV - minV;

    final top = _text(_fmt(maxV), 60);
    final left = top.width + 6;
    const bottom = 18.0;
    final plot = Rect.fromLTRB(left, 6, size.width, size.height - bottom);
    double y(double v) => plot.bottom - (v - minV) / span * plot.height;

    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);
    canvas.drawLine(
      Offset(plot.left, y(maxV)),
      Offset(plot.right, y(maxV)),
      grid,
    );
    top.paint(canvas, Offset(0, y(maxV) - top.height / 2));
    if (minV < 0) {
      canvas.drawLine(Offset(plot.left, y(0)), Offset(plot.right, y(0)), grid);
    }

    final n = chart.labels.length;
    final slot = plot.width / n;
    for (var i = 0; i < n; i++) {
      final t = _text(chart.labels[i], slot - 2);
      t.paint(
        canvas,
        Offset(plot.left + slot * i + (slot - t.width) / 2, plot.bottom + 3),
      );
    }

    if (chart.kind == 'line') {
      for (var si = 0; si < chart.series.length; si++) {
        final path = Path();
        final dot = Paint()..color = _color(si);
        for (var i = 0; i < n; i++) {
          final p = Offset(
            plot.left + slot * i + slot / 2,
            y(_value(chart.series[si], i)),
          );
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          canvas.drawCircle(p, 3, dot);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = _color(si)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      return;
    }

    final count = chart.series.length;
    final barW = (slot * 0.7) / count;
    for (var i = 0; i < n; i++) {
      for (var si = 0; si < count; si++) {
        final v = _value(chart.series[si], i);
        final x = plot.left + slot * i + slot * 0.15 + barW * si;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(
              x,
              math.min(y(v), y(0)),
              x + barW - 1,
              math.max(y(v), y(0)),
            ),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          Paint()..color = _color(si),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.chart != chart || old.palette != palette || old.label != label;
}
