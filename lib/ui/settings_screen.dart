import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/strings.dart';
import 'sheets.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        const SectionTitle(S.appearance),
        AdaptiveChoices<ThemeMode>(
          label: S.appearance,
          options: const [
            ChoiceOption(
              ThemeMode.system,
              S.system,
              icon: Icons.brightness_auto_rounded,
            ),
            ChoiceOption(
              ThemeMode.light,
              S.light,
              icon: Icons.light_mode_outlined,
            ),
            ChoiceOption(
              ThemeMode.dark,
              S.dark,
              icon: Icons.dark_mode_outlined,
            ),
          ],
          selected: s.theme,
          onChanged: (v) => c.updateSettings(s.copyWith(theme: v)),
        ),
        const SectionTitle(S.speedUnits),
        AdaptiveChoices<SpeedUnit>(
          label: S.speedUnits,
          options: const [
            ChoiceOption(SpeedUnit.mbps, 'Mbps'),
            ChoiceOption(SpeedUnit.megabytes, 'MB/s'),
          ],
          selected: s.unit,
          onChanged: c.running
              ? null
              : (v) => c.updateSettings(s.copyWith(unit: v)),
        ),
        const SizedBox(height: 12),
        const Text(S.unitsHelp),
        const SectionTitle(S.networkDetails),
        const Text(S.networkDetailsHelp),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: c.requestDetails,
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text(S.permissions),
        ),
        TextButton(
          onPressed: () => showNetworkDetails(context, c),
          child: const Text(S.networkDetails),
        ),
        TextButton(
          onPressed: c.bridge.appSettings,
          child: const Text(S.appSettings),
        ),
        const SectionTitle(S.background),
        const Text(S.backgroundHelp),
        const SectionTitle(S.measurements),
        const Text(S.measurementsHelp),
        const SizedBox(height: 16),
        const Text(S.dataHelp),
        const SizedBox(height: 36),
        const Divider(),
        const SizedBox(height: 16),
        Center(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            children: [
              Text(
                'Created by ',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              InkWell(
                onTap: () => c.bridge.openUrl('https://www.samsam123.name.my'),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Text(
                    'Sam Sam',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Text(
                ' | v1.0.0',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
