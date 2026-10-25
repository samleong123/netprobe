import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedtest/core/app_controller.dart';
import 'package:speedtest/core/models.dart';
import 'package:speedtest/core/platform_bridge.dart';

class FakeBridge extends AndroidBridge {
  final eventController = StreamController<Map<String, dynamic>>.broadcast();
  final pendingSearches = <String, Completer<Discovery>>{};
  Map<String, dynamic> stored = {'servers': '[]', 'history': '[]'};
  int startupRequests = 0;
  bool startupGranted = true;
  Discovery nearby = const Discovery('203.0.113.1', 'Example ISP', '', '', []);

  @override
  Stream<Map<String, dynamic>> get stream => eventController.stream;
  @override
  Future<Map<String, dynamic>> load() async => stored;
  @override
  Future<Map<String, dynamic>> network() async => {
    'connected': true,
    'transport': 'Wi-Fi',
  };
  @override
  Future<void> save(String key, Object value) async {
    stored[key] = jsonEncode(value);
  }

  @override
  Future<bool> requestStartupPermissions() async {
    startupRequests++;
    return startupGranted;
  }

  @override
  Future<Discovery> discover(String search) {
    if (search.isEmpty) {
      return Future.value(nearby);
    }
    final pending = Completer<Discovery>();
    pendingSearches[search] = pending;
    return pending.future;
  }
}

void main() {
  testWidgets(
    'legacy endpoints are repaired and saved even before discovery returns that server',
    (tester) async {
      final old = <String, dynamic>{
        'id': 'ookla:50737',
        'uploadUrl':
            'http://speedkl.time.com.my.prod.hosts.ooklaserver.net:8080/upload',
        'latencyUrl': 'http://speedkl.time.com.my:8080/speedtest/latency.txt',
      };
      final bridge = FakeBridge()
        ..stored = {
          'settings': jsonEncode({'selectedServer': old}),
          'servers': jsonEncode([old]),
          'history': '[]',
        };
      final controller = AppController(bridge: bridge);
      addTearDown(controller.dispose);
      addTearDown(bridge.eventController.close);
      await controller.initialize();
      await tester.pump();
      const expected = 'http://speedkl.time.com.my:8080/speedtest/upload.php';
      expect(controller.selectedServer?.uploadUrl, expected);
      expect(controller.savedServers.single.uploadUrl, expected);
      expect(
        (jsonDecode(bridge.stored['servers'] as String) as List)
            .single['uploadUrl'],
        expected,
      );
      expect(
        (jsonDecode(bridge.stored['settings'] as String)
            as Map)['selectedServer']['uploadUrl'],
        expected,
      );
    },
  );
  testWidgets(
    'discovery repairs and persists saved and selected server URLs by ID',
    (tester) async {
      final fresh = TestServer.fromApi({
        'id': '50737',
        'host': 'speedkl.time.com.my.prod.hosts.ooklaserver.net:8080',
        'url':
            'https://speedkl.time.com.my:8443/speedtest/upload.php?region=MY',
        'name': 'Kuala Lumpur',
        'sponsor': 'TIME MY',
      });
      final old = <String, dynamic>{
        'id': fresh.id,
        'downloadUrl': fresh.downloadUrl,
        'uploadUrl':
            'http://speedkl.time.com.my.prod.hosts.ooklaserver.net:8080/upload',
        'latencyUrl': 'http://speedkl.time.com.my:8080/speedtest/latency.txt',
      };
      final bridge = FakeBridge()
        ..nearby = Discovery('203.0.113.1', 'Example ISP', '', '', [fresh])
        ..stored = {
          'settings': jsonEncode({'selectedServer': old}),
          'servers': jsonEncode([old]),
          'history': '[]',
        };
      final controller = AppController(bridge: bridge);
      addTearDown(controller.dispose);
      addTearDown(bridge.eventController.close);
      await controller.initialize();
      await tester.pump();
      expect(controller.selectedServer?.uploadUrl, fresh.uploadUrl);
      expect(controller.savedServers.single.uploadUrl, fresh.uploadUrl);
      expect(
        (jsonDecode(bridge.stored['servers'] as String) as List)
            .single['uploadUrl'],
        fresh.uploadUrl,
      );
      expect(
        (jsonDecode(bridge.stored['settings'] as String)
            as Map)['selectedServer']['uploadUrl'],
        fresh.uploadUrl,
      );
    },
  );
  testWidgets(
    'launch requests permissions and reentry rechecks denied permissions',
    (tester) async {
      final bridge = FakeBridge()..startupGranted = false;
      final controller = AppController(bridge: bridge);
      addTearDown(controller.dispose);
      addTearDown(bridge.eventController.close);
      await controller.initialize();
      expect(bridge.startupRequests, 1);
      expect(controller.initialized, isTrue);
      expect(controller.requestingPermissions, isFalse);
      expect(controller.notice, isNotNull);
      await controller.requestStartupPermissions();
      expect(bridge.startupRequests, 2);
      expect(controller.requestingPermissions, isFalse);
    },
  );
  testWidgets('a slow search response cannot replace a newer search', (
    tester,
  ) async {
    final bridge = FakeBridge();
    final controller = AppController(bridge: bridge);
    addTearDown(controller.dispose);
    addTearDown(bridge.eventController.close);
    await controller.initialize();
    controller.setSearch('old');
    await tester.pump(const Duration(milliseconds: 501));
    controller.setSearch('new');
    await tester.pump(const Duration(milliseconds: 501));
    const newServer = TestServer(
      id: 'new',
      name: 'New City',
      sponsor: 'New ISP',
      country: 'MY',
    );
    bridge.pendingSearches['new']!.complete(
      const Discovery('203.0.113.1', 'New ISP', 'New City', 'MY', [newServer]),
    );
    await tester.pump();
    bridge.pendingSearches['old']!.complete(
      const Discovery('203.0.113.1', 'Old ISP', 'Old City', 'MY', []),
    );
    await tester.pump();
    expect(controller.foundServers.single.id, 'new');
    expect(controller.discovery!.city, 'New City');
    expect(controller.loadingServers, isFalse);
  });

  testWidgets(
    'saved preferences and endpoint survive initialization without discovery results',
    (tester) async {
      final bridge = FakeBridge();
      const server = TestServer(
        id: 'custom:1',
        name: '',
        sponsor: 'My LAN server',
        country: '',
        downloadUrl: 'http://192.168.1.20:8080/data',
        custom: true,
      );
      bridge.stored = {
        'settings': jsonEncode({
          ...const AppSettings(
            threads: 64,
            theme: ThemeMode.dark,
            unit: SpeedUnit.megabytes,
          ).toJson(),
          'selectedServer': server.toJson(),
        }),
        'servers': jsonEncode([server.toJson()]),
        'history': '[]',
      };
      final controller = AppController(bridge: bridge);
      addTearDown(controller.dispose);
      addTearDown(bridge.eventController.close);
      await controller.initialize();
      expect(controller.settings.threads, 64);
      expect(controller.settings.theme, ThemeMode.dark);
      expect(controller.settings.unit, SpeedUnit.megabytes);
      expect(controller.selectedServer!.downloadUrl, server.downloadUrl);
      expect(controller.savedServers.single.id, server.id);
      expect(controller.foundServers, isEmpty);
    },
  );

  testWidgets(
    'calling stop when transfer is not running does not leave stopping true',
    (tester) async {
      final bridge = FakeBridge();
      final controller = AppController(bridge: bridge);
      addTearDown(controller.dispose);
      addTearDown(bridge.eventController.close);
      await controller.initialize();
      expect(controller.running, isFalse);
      expect(controller.stopping, isFalse);
      await controller.stop();
      expect(controller.stopping, isFalse);
    },
  );

  testWidgets(
    'safety timeout recovers stopping flag if no stop event arrives',
    (tester) async {
      final bridge = FakeBridge();
      final controller = AppController(bridge: bridge);
      addTearDown(controller.dispose);
      addTearDown(bridge.eventController.close);
      await controller.initialize();
      // Simulate running transfer
      bridge.eventController.add({
        'type': 'transfer',
        'data': {'id': '1', 'status': 'running', 'phase': 'upload'},
      });
      await tester.pump();
      expect(controller.running, isTrue);

      unawaited(controller.stop());
      await tester.pump();
      expect(controller.stopping, isTrue);

      // Advance past timeout
      await tester.pump(const Duration(seconds: 5));
      expect(controller.stopping, isFalse);
    },
  );
}
