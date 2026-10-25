import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedtest/core/app_controller.dart';
import 'package:speedtest/core/models.dart';
import 'package:speedtest/core/platform_bridge.dart';
import 'package:speedtest/core/theme.dart';
import 'package:speedtest/ui/app_shell.dart';
import 'package:speedtest/ui/widgets.dart';
import 'package:speedtest/ui/thread_selector.dart';
import 'package:speedtest/ui/sheets.dart';

class MemoryBridge extends AndroidBridge {
  @override
  Future<void> save(String key, Object value) async {}
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('test screen and navigation work in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppController()..initialized = true;
      controller.network = {
        'connected': true,
        'validated': true,
        'transport': 'Wi-Fi',
        'device': 'Google Pixel 9 Pro',
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness),
          home: AppShell(controller: controller),
        ),
      );
      expect(find.text('WiFi - Google Pixel 9 Pro'), findsOneWidget);
      expect(find.text('Start test'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Servers').last);
      await tester.pumpAndSettle();
      expect(find.text('Add custom server'), findsOneWidget);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SectionTitle, 'Appearance'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sam Sam'), 200);
      expect(find.text('Sam Sam'), findsOneWidget);
      expect(find.text(' | v1.0.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('64 threads and running transfer disable configuration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()..initialized = true;
    controller.settings = const AppSettings(threads: 64);
    controller.network = {
      'connected': true,
      'validated': true,
      'transport': 'Wi-Fi',
    };
    controller.transfer = TransferSnapshot({
      'id': '1',
      'status': 'running',
      'phase': 'download',
      'speedMbps': 800,
      'totalBytes': 1000000,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: AppShell(controller: controller),
      ),
    );
    expect(find.text('Stop transfer'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(Slider),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 64);
    expect(slider.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow phone uses accessible choices at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()..initialized = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: AppShell(controller: controller),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SectionTitle, 'Appearance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread drag previews locally and commits only once on release', (
    tester,
  ) async {
    final value = ValueNotifier<int>(8);
    addTearDown(value.dispose);
    final commits = <int>[];
    var parentBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: value,
            builder: (context, threads, child) {
              parentBuilds++;
              return ThreadSelector(
                value: threads,
                onCommitted: (next) {
                  commits.add(next);
                  value.value = next;
                },
              );
            },
          ),
        ),
      ),
    );
    final buildsBeforeDrag = parentBuilds;
    final rect = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(24, 0),
    );
    await gesture.moveTo(rect.center);
    await tester.pump();
    await gesture.moveTo(rect.centerRight - const Offset(24, 0));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(8));
    expect(value.value, 8);
    expect(commits, isEmpty);
    expect(parentBuilds, buildsBeforeDrag);
    await gesture.up();
    await tester.pump();
    expect(commits, hasLength(1));
    expect(value.value, inInclusiveRange(9, 64));
    expect(parentBuilds, buildsBeforeDrag + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both transfer limit fields can be cleared and saved', (
    tester,
  ) async {
    final controller = AppController(bridge: MemoryBridge());
    controller.settings = const AppSettings(mode: TestMode.download);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLimits(context, controller),
              child: const Text('Open limits'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open limits'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '');
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.settings.sustainedSeconds, isNull);
    expect(controller.settings.maxBytes, isNull);
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
