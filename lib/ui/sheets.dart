import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/strings.dart';
import 'widgets.dart';

Future<void> showLimits(BuildContext context, AppController controller) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LimitsSheet(controller: controller),
    );

class _LimitsSheet extends StatefulWidget {
  const _LimitsSheet({required this.controller});
  final AppController controller;
  @override
  State<_LimitsSheet> createState() => _LimitsSheetState();
}

class _LimitsSheetState extends State<_LimitsSheet> {
  final form = GlobalKey<FormState>();
  late final TextEditingController duration;
  late final TextEditingController budget;
  late final bool normal;
  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    normal = s.mode == TestMode.normal;
    duration = TextEditingController(
      text: '${normal ? s.normalSeconds : s.sustainedSeconds ?? ''}',
    );
    budget = TextEditingController(
      text: s.maxBytes == null ? '' : (s.maxBytes! / 1e9).toString(),
    );
  }

  @override
  void dispose() {
    duration.dispose();
    budget.dispose();
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) return;
    final seconds = int.tryParse(duration.text.trim());
    final gb = double.tryParse(budget.text.trim());
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(
        normalSeconds: normal ? seconds : null,
        sustainedSeconds: normal ? null : seconds,
        maxBytes: normal
            ? null
            : gb == null
            ? null
            : (gb * 1e9).round(),
        clearDuration: !normal && seconds == null,
        clearBudget: !normal && gb == null,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.limits, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(normal ? S.normalHelp : S.limitsHelp),
            const SizedBox(height: 24),
            TextFormField(
              controller: duration,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: normal ? S.phaseDuration : S.duration,
                suffixText: 's',
              ),
              validator: (v) {
                if (!normal && (v?.trim().isEmpty ?? true)) return null;
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 || n > 86400 ? S.secondsError : null;
              },
            ),
            if (!normal) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: budget,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: S.dataLimit,
                  suffixText: 'GB',
                  helperText: S.dataHelp,
                  helperMaxLines: 3,
                ),
                validator: (v) {
                  if (v?.trim().isEmpty ?? true) return null;
                  final n = double.tryParse(v!.trim());
                  return n == null || !n.isFinite || n * 1e9 < 1 || n > 9000000
                      ? S.budgetError
                      : null;
                },
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(S.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: save, child: const Text(S.save)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showCustomServer(
  BuildContext context,
  AppController controller,
) async {
  final server = await showModalBottomSheet<TestServer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _CustomServerSheet(),
  );
  if (server != null) controller.addCustom(server);
}

class _CustomServerSheet extends StatefulWidget {
  const _CustomServerSheet();
  @override
  State<_CustomServerSheet> createState() => _CustomServerSheetState();
}

class _CustomServerSheetState extends State<_CustomServerSheet> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final download = TextEditingController();
  final upload = TextEditingController();
  bool saved = false;
  String? error;
  bool get dirty =>
      name.text.isNotEmpty ||
      download.text.isNotEmpty ||
      upload.text.isNotEmpty;
  @override
  void dispose() {
    name.dispose();
    download.dispose();
    upload.dispose();
    super.dispose();
  }

  Future<void> cancel() async {
    if (dirty) {
      final discard = await confirm(
        context,
        title: S.discardTitle,
        body: S.discardBody,
        action: S.discard,
      );
      if (!discard || !mounted) return;
    }
    setState(() => saved = true);
    // Allow PopScope to rebuild before dismissing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void save() {
    if (!form.currentState!.validate()) return;
    if (download.text.trim().isEmpty && upload.text.trim().isEmpty) {
      setState(() => error = S.endpointRequired);
      return;
    }
    final server = TestServer(
      id: 'custom:${DateTime.now().microsecondsSinceEpoch}',
      name: '',
      sponsor: name.text.trim(),
      country: '',
      custom: true,
      downloadUrl: download.text.trim().isEmpty ? null : download.text.trim(),
      uploadUrl: upload.text.trim().isEmpty ? null : upload.text.trim(),
    );
    setState(() => saved = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, server);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: saved,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) cancel();
    },
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.addServer,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(S.customHelp),
              const SizedBox(height: 24),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                maxLength: 100,
                decoration: const InputDecoration(labelText: S.serverName),
                validator: (v) =>
                    v?.trim().isEmpty == true ? S.nameRequired : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: download,
                keyboardType: TextInputType.url,
                autocorrect: false,
                maxLines: 2,
                decoration: const InputDecoration(labelText: S.downloadUrl),
                validator: (v) =>
                    v?.trim().isNotEmpty == true && !validTransferUrl(v!)
                    ? S.urlError
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: upload,
                keyboardType: TextInputType.url,
                autocorrect: false,
                maxLines: 2,
                decoration: const InputDecoration(labelText: S.uploadUrl),
                validator: (v) =>
                    v?.trim().isNotEmpty == true && !validTransferUrl(v!)
                    ? S.urlError
                    : null,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: cancel, child: const Text(S.cancel)),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: save, child: const Text(S.save)),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showNetworkDetails(
  BuildContext context,
  AppController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final n = controller.network;
      final d = controller.discovery;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              S.networkDetails,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            DetailRow(S.device, n['device'] as String? ?? S.unavailable),
            DetailRow(
              S.publicIp,
              d?.ip.isNotEmpty == true ? d!.ip : S.unavailable,
            ),
            DetailRow(
              S.isp,
              d?.isp.isNotEmpty == true ? d!.isp : S.unavailable,
            ),
            DetailRow(
              S.location,
              d == null
                  ? S.unavailable
                  : [d.city, d.country].where((v) => v.isNotEmpty).join(', '),
            ),
            DetailRow(
              S.localIp,
              (n['localAddresses'] as List?)?.join('\n') ?? S.unavailable,
            ),
            const Divider(),
            if (n['transport'] == 'Wi-Fi')
              DetailRow(S.wifiName, n['ssid'] as String? ?? S.unavailable),
            if (n['transport'] == 'Mobile') ...[
              DetailRow(S.operator, n['operator'] as String? ?? S.unavailable),
              DetailRow(
                S.simOperator,
                n['simOperator'] as String? ?? S.unavailable,
              ),
              DetailRow(
                S.networkType,
                n['networkType'] as String? ?? S.unavailable,
              ),
              DetailRow(
                S.roaming,
                n['roaming'] == null
                    ? S.unavailable
                    : n['roaming'] == true
                    ? S.on
                    : S.off,
              ),
            ],
            const SizedBox(height: 16),
            const Text(S.networkDetailsHelp),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: controller.requestDetails,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text(S.permissions),
            ),
            TextButton(
              onPressed: controller.bridge.appSettings,
              child: const Text(S.appSettings),
            ),
            if (n['locationEnabled'] != true)
              TextButton(
                onPressed: controller.bridge.locationSettings,
                child: const Text(S.locationSettings),
              ),
          ],
        ),
      );
    },
  ),
);
