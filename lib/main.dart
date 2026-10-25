import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/app_controller.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'ui/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpeedtestApp());
}

class SpeedtestApp extends StatefulWidget {
  const SpeedtestApp({super.key});
  @override
  State<SpeedtestApp> createState() => _SpeedtestAppState();
}

class _SpeedtestAppState extends State<SpeedtestApp>
    with WidgetsBindingObserver {
  late final AppController controller;
  late final ThemeData lightTheme;
  late final ThemeData darkTheme;
  ThemeMode themeMode = ThemeMode.system;
  bool wasBackgrounded = false;
  @override
  void initState() {
    super.initState();
    controller = AppController();
    lightTheme = AppTheme.build(Brightness.light);
    darkTheme = AppTheme.build(Brightness.dark);
    controller.addListener(updateTheme);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.initialize());
    });
  }

  void updateTheme() {
    if (mounted && themeMode != controller.settings.theme) {
      setState(() => themeMode = controller.settings.theme);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !controller.requestingPermissions &&
        !controller.starting) {
      wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && wasBackgrounded) {
      wasBackgrounded = false;
      if (controller.initialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(controller.requestStartupPermissions());
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(updateTheme);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: S.appName,
    debugShowCheckedModeBanner: false,
    theme: lightTheme,
    darkTheme: darkTheme,
    themeMode: themeMode,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en')],
    home: AppShell(controller: controller),
  );
}
