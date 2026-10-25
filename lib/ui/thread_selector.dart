import 'package:flutter/material.dart';
import '../core/strings.dart';

/// Drag previews stay in this subtree. Only the final value updates app settings.
class ThreadSelector extends StatefulWidget {
  const ThreadSelector({
    super.key,
    required this.value,
    required this.onCommitted,
  });
  final int value;
  final ValueChanged<int>? onCommitted;

  @override
  State<ThreadSelector> createState() => _ThreadSelectorState();
}

class _ThreadSelectorState extends State<ThreadSelector> {
  int? _preview;

  @override
  void didUpdateWidget(covariant ThreadSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || widget.onCommitted == null) {
      _preview = null;
    }
  }

  void _commit(double value) {
    final threads = value.round();
    setState(() => _preview = null);
    if (threads != widget.value) widget.onCommitted?.call(threads);
  }

  @override
  Widget build(BuildContext context) {
    final value = _preview ?? widget.value;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Text(S.parallelThreads)),
            Text('$value', style: textTheme.titleMedium),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 64,
          divisions: 63,
          label: '$value',
          semanticFormatterCallback: (v) => '${v.round()} threads',
          onChanged: widget.onCommitted == null
              ? null
              : (v) => setState(() => _preview = v.round()),
          onChangeEnd: widget.onCommitted == null ? null : _commit,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1', style: textTheme.labelSmall),
            Text('64', style: textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
