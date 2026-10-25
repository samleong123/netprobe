import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/strings.dart';
import 'widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return RefreshIndicator(
      onRefresh: c.refreshHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (c.history.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: S.noHistory,
              body: S.noHistoryHelp,
            )
          else ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: c.running
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          title: S.clearHistory,
                          body: S.clearHistoryBody,
                          action: S.delete,
                        )) {
                          c.clearHistory();
                        }
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text(S.clearHistory),
              ),
            ),
            for (final result in c.history)
              _ResultCard(result: result, unit: c.settings.unit),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.unit});
  final TransferSnapshot result;
  final SpeedUnit unit;
  @override
  Widget build(BuildContext context) {
    final timestamp = result.data['timestamp'];
    final millis = timestamp is num
        ? timestamp.round()
        : int.tryParse('$timestamp');
    final date = millis == null
        ? ''
        : MaterialLocalizations.of(
            context,
          ).formatMediumDate(DateTime.fromMillisecondsSinceEpoch(millis));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      result.data['serverName'] as String? ?? S.unavailable,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Icon(
                    result.status == 'error'
                        ? Icons.error_outline_rounded
                        : result.status == 'stopped'
                        ? Icons.stop_circle_outlined
                        : Icons.check_circle_outline_rounded,
                    color: result.status == 'error'
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _ResultValue(
                    S.download,
                    '${unit.format(result.download)} ${unit.label}',
                  ),
                  _ResultValue(
                    S.upload,
                    '${unit.format(result.upload)} ${unit.label}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${formatBytes(result.totalBytes)} · ${formatDuration(result.elapsed)} · ${result.data['threads'] ?? '—'} threads',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (result.message != null) ...[
                const SizedBox(height: 6),
                Text(
                  result.message!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultValue extends StatelessWidget {
  const _ResultValue(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}
