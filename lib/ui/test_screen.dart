import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/network_summary.dart';
import '../core/strings.dart';
import 'sheets.dart';
import 'widgets.dart';
import 'thread_selector.dart';

class TestScreen extends StatelessWidget {
  const TestScreen({
    super.key,
    required this.controller,
    required this.onChooseServer,
  });
  final AppController controller;
  final VoidCallback onChooseServer;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final t = c.transfer;
    final s = c.settings;
    final active = c.running;
    final phase = c.starting
        ? S.starting
        : t?.running == true
        ? switch (t!.phase) {
            'download' => S.download,
            'upload' => S.upload,
            'latency' => S.latency,
            _ => S.starting,
          }
        : t?.message ?? S.ready;
    final duration = t?.data['durationSeconds'] as num?;
    final maxBytes = t?.data['maxBytes'] as num?;
    final mode = t?.data['mode'] as String?;
    final isNormal =
        mode == 'normal' || (mode == null && s.mode == TestMode.normal);
    final progress = !active
        ? null
        : maxBytes != null
        ? ((t?.totalBytes ?? 0) / maxBytes).clamp(0.0, 1.0).toDouble()
        : duration != null && t?.phase != 'latency'
        ? isNormal
              ? switch (t?.phase) {
                  'download' =>
                    ((t?.data['phaseSeconds'] as num? ?? 0) / (duration * 2))
                        .clamp(0.0, 0.5)
                        .toDouble(),
                  'upload' =>
                    (0.5 +
                            ((t?.data['phaseSeconds'] as num? ?? 0) /
                                (duration * 2)))
                        .clamp(0.5, 1.0)
                        .toDouble(),
                  _ => 0.0,
                }
              : ((t?.data['phaseSeconds'] as num? ?? 0) / duration)
                    .clamp(0.0, 1.0)
                    .toDouble()
        : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Row(
          children: [
            Icon(
              switch (c.network['transport']) {
                'Wi-Fi' => Icons.wifi_rounded,
                'Mobile' => Icons.network_cell_rounded,
                'VPN' => Icons.vpn_lock_rounded,
                'Ethernet' => Icons.lan_rounded,
                _ => Icons.wifi_off_rounded,
              },
              size: 18,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                networkHeaderLabel(c.network),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => showNetworkDetails(context, c),
              child: const Text(S.details),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (active) ...[
                      SizedBox(
                        width: 8,
                        height: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        phase,
                        style: theme.textTheme.labelLarge,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (t?.running == true)
                      Text(
                        formatDuration(t!.elapsed),
                        style: theme.textTheme.labelLarge,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Semantics(
                  label:
                      'Current speed ${s.unit.format(active ? t?.speed ?? 0 : t?.download ?? t?.upload ?? 0)} ${s.unit.label}',
                  liveRegion: false,
                  child: ExcludeSemantics(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 10,
                      children: [
                        Text(
                          s.unit.format(
                            active
                                ? t?.speed ?? 0
                                : t?.download ?? t?.upload ?? 0,
                          ),
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            s.unit.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SpeedChart(c.samples),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth < 300
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: width,
                          child: _Metric(
                            label: S.download,
                            value: s.unit.format(t?.download),
                            suffix: s.unit.label,
                            icon: Icons.arrow_downward_rounded,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _Metric(
                            label: S.upload,
                            value: s.unit.format(t?.upload),
                            suffix: s.unit.label,
                            icon: Icons.arrow_upward_rounded,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _CompactMetric(
                      S.latency,
                      t?.latency == null
                          ? '—'
                          : '${t!.latency!.toStringAsFixed(0)} ms',
                    ),
                    _CompactMetric(
                      S.transferred,
                      formatBytes(t?.totalBytes ?? 0),
                    ),
                  ],
                ),
                if (active) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: active
              ? FilledButton.styleFrom(
                  backgroundColor: colors.errorContainer,
                  foregroundColor: colors.onErrorContainer,
                )
              : null,
          onPressed:
              c.starting || c.stopping || (!active && c.requestingPermissions)
              ? null
              : active
              ? c.stop
              : c.connected && c.selectedServer != null
              ? c.start
              : null,
          icon: c.starting || c.stopping
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded),
          label: Text(
            c.stopping
                ? S.stopPending
                : active
                ? S.stop
                : S.start,
          ),
        ),
        if (!c.connected) ...[
          const SizedBox(height: 12),
          Text(S.offlineHelp, style: TextStyle(color: colors.error)),
        ] else if (c.network['validated'] != true) ...[
          const SizedBox(height: 12),
          Text(
            S.limitedConnection,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
        SectionTitle(S.selectedServer),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: const Icon(Icons.dns_outlined),
            title: Text(c.selectedServer?.sponsor ?? S.noServer),
            subtitle: Text(
              c.selectedServer?.custom == true
                  ? S.custom
                  : c.selectedServer?.subtitle ?? S.chooseServer,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            enabled: !active,
            onTap: active ? null : onChooseServer,
          ),
        ),
        SectionTitle(S.testSetup),
        AdaptiveChoices<TestMode>(
          label: S.testSetup,
          options: const [
            ChoiceOption(TestMode.normal, S.normal),
            ChoiceOption(TestMode.download, S.download),
            ChoiceOption(TestMode.upload, S.upload),
          ],
          selected: s.mode,
          onChanged: active
              ? null
              : (m) {
                  HapticFeedback.selectionClick();
                  c.updateSettings(s.copyWith(mode: m));
                },
        ),
        const SizedBox(height: 12),
        Text(
          s.mode == TestMode.normal ? S.normalHelp : S.sustainedHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        ThreadSelector(
          value: s.threads,
          onCommitted: active
              ? null
              : (threads) =>
                    c.updateSettings(c.settings.copyWith(threads: threads)),
        ),
        const SizedBox(height: 8),
        Text(
          S.threadsHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(S.limits),
          subtitle: Text(
            s.mode == TestMode.normal
                ? '${s.normalSeconds}s download · ${s.normalSeconds}s upload'
                : s.sustainedSeconds == null && s.maxBytes == null
                ? S.untilStopped
                : [
                    if (s.sustainedSeconds != null)
                      formatDuration(s.sustainedSeconds!),
                    if (s.maxBytes != null) formatBytes(s.maxBytes!),
                  ].join(' · '),
          ),
          trailing: const Icon(Icons.tune_rounded),
          onTap: active ? null : () => showLimits(context, c),
        ),
        SectionTitle(S.currentNetwork),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Text(
              c.discovery?.isp.isNotEmpty == true
                  ? c.discovery!.isp
                  : c.network['transport'] as String? ?? S.offline,
            ),
            subtitle: Text(
              [
                if (c.network['transport'] == 'Wi-Fi')
                  c.network['ssid'] as String? ?? 'Wi-Fi name hidden',
                if (c.network['transport'] == 'Mobile')
                  c.network['networkType'] as String? ?? 'Radio type hidden',
                if (c.discovery != null) c.discovery!.ip,
                if (c.discovery != null)
                  [
                    c.discovery!.city,
                    c.discovery!.country,
                  ].where((v) => v.isNotEmpty).join(', '),
              ].where((v) => v.isNotEmpty).join('\n'),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showNetworkDetails(context, c),
          ),
        ),
        if (c.discoveryError != null) ...[
          const SizedBox(height: 12),
          Text(c.discoveryError!, style: TextStyle(color: colors.error)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: c.loadingServers ? null : c.discover,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(S.retry),
            ),
          ),
        ],
        if (c.loadingServers && c.discovery == null) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text(S.findingServers),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
  });
  final String label;
  final String value;
  final String suffix;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(suffix, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ],
  );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}
