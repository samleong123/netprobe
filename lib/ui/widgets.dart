import 'dart:math' as math;
import 'package:flutter/material.dart';

class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// Keep exclusive choices usable at narrow widths and with large system text.
class AdaptiveChoices<T> extends StatelessWidget {
  const AdaptiveChoices({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final List<ChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 350 ||
          MediaQuery.textScalerOf(context).scale(16) > 24) {
        return DropdownMenu<T>(
          label: Text(label),
          initialSelection: selected,
          expandedInsets: EdgeInsets.zero,
          enabled: onChanged != null,
          requestFocusOnTap: false,
          onSelected: (value) {
            if (value != null) onChanged?.call(value);
          },
          dropdownMenuEntries: [
            for (final option in options)
              DropdownMenuEntry(
                value: option.value,
                label: option.label,
                leadingIcon: option.icon == null ? null : Icon(option.icon),
              ),
          ],
        );
      }
      return SegmentedButton<T>(
        showSelectedIcon: false,
        selected: {selected},
        segments: [
          for (final option in options)
            ButtonSegment(
              value: option.value,
              label: Text(option.label),
              icon: option.icon == null ? null : Icon(option.icon),
            ),
        ],
        onSelectionChanged: onChanged == null
            ? null
            : (values) => onChanged!(values.first),
      );
    },
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class SpeedChart extends StatelessWidget {
  const SpeedChart(this.samples, {super.key});
  final List<double> samples;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 90,
      width: double.infinity,
      child: CustomPaint(
        painter: _SpeedPainter(
          samples: List.of(samples),
          color: Theme.of(context).colorScheme.primary,
          gridColor: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    ),
  );
}

class _SpeedPainter extends CustomPainter {
  _SpeedPainter({
    required this.samples,
    required this.color,
    required this.gridColor,
  });
  final List<double> samples;
  final Color color;
  final Color gridColor;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (final fraction in [0.25, 0.75]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        grid,
      );
    }
    if (samples.length < 2) return;
    final maxValue = math.max(1.0, samples.reduce(math.max) * 1.15);
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i / (samples.length - 1) * size.width;
      final y =
          size.height -
          (samples[i] / maxValue * size.height).clamp(0, size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.07));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedPainter oldDelegate) => true;
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
