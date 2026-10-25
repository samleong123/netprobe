import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/strings.dart';
import 'history_screen.dart';
import 'server_screen.dart';
import 'settings_screen.dart';
import 'test_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int destination = 0;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(onChange);
    super.dispose();
  }

  void onChange() {
    final notice = widget.controller.notice;
    if (notice == null) return;
    widget.controller.clearNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notice), duration: const Duration(seconds: 7)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 720;
      final pages = [
        TestScreen(
          controller: widget.controller,
          onChooseServer: () => setState(() => destination = 1),
        ),
        ServerScreen(
          controller: widget.controller,
          onSelected: () => setState(() => destination = 0),
        ),
        HistoryScreen(controller: widget.controller),
        SettingsScreen(controller: widget.controller),
      ];
      const labels = [S.test, S.servers, S.history, S.settings];
      const icons = [
        Icons.speed_rounded,
        Icons.dns_outlined,
        Icons.history_rounded,
        Icons.settings_outlined,
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(destination == 0 ? S.appName : labels[destination]),
          actions: [
            if (widget.controller.running && destination != 0)
              IconButton(
                tooltip: 'Show active test',
                onPressed: () => setState(() => destination = 0),
                icon: const Icon(Icons.speed_rounded),
              ),
            if (destination == 0)
              IconButton(
                tooltip: S.settings,
                onPressed: () => setState(() => destination = 3),
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        body: !widget.controller.initialized
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                bottom: false,
                child: Row(
                  children: [
                    if (wide)
                      NavigationRail(
                        selectedIndex: destination,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: (v) =>
                            setState(() => destination = v),
                        destinations: [
                          for (var i = 0; i < labels.length; i++)
                            NavigationRailDestination(
                              icon: Icon(icons[i]),
                              label: Text(labels[i]),
                            ),
                        ],
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: IndexedStack(
                            index: destination,
                            children: pages,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: destination,
                onDestinationSelected: (v) => setState(() => destination = v),
                destinations: [
                  for (var i = 0; i < labels.length; i++)
                    NavigationDestination(
                      icon: Icon(icons[i]),
                      label: labels[i],
                    ),
                ],
              ),
      );
    },
  );
}
