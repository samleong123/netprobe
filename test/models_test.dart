import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedtest/core/models.dart';
import 'package:speedtest/core/network_summary.dart';

void main() {
  test(
    'network header matches WiFi and registered roaming/non-roaming carriers',
    () {
      expect(
        networkHeaderLabel({
          'transport': 'Wi-Fi',
          'device': 'Google Pixel 9 Pro',
        }),
        'WiFi - Google Pixel 9 Pro',
      );
      final mobile = <String, dynamic>{
        'transport': 'Mobile',
        'networkCountryCode': 'my',
        'operator': 'CelcomDigi',
        'networkType': '5G NSA (LTE anchor)',
        'simOperator': 'Singtel',
        'roaming': true,
      };
      expect(
        networkHeaderLabel(mobile),
        'MY CelcomDigi 5G NSA (LTE anchor) | Singtel - R',
      );
      expect(
        networkHeaderLabel({...mobile, 'operator': 'MY CelcomDigi 5G'}),
        'MY CelcomDigi 5G 5G NSA (LTE anchor) | Singtel - R',
      );
      expect(
        networkHeaderLabel({
          ...mobile,
          'simOperator': 'Digi',
          'roaming': false,
        }),
        'MY CelcomDigi 5G NSA (LTE anchor) | Digi',
      );
      expect(
        networkHeaderLabel({...mobile, 'networkType': 'LTE', 'roaming': null}),
        'MY CelcomDigi LTE | Singtel',
      );
      expect(
        networkHeaderLabel({
          ...mobile,
          'operator': 'MY CelcomDigi',
          'networkType': 'NR (5G)',
        }),
        'MY CelcomDigi NR (5G) | Singtel - R',
      );
    },
  );

  test(
    'both empty sustained limits remain unlimited after saving settings',
    () {
      final settings = const AppSettings().copyWith(
        mode: TestMode.download,
        clearDuration: true,
        clearBudget: true,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.sustainedSeconds, isNull);
      expect(restored.maxBytes, isNull);
      expect(restored.normalSeconds, 15);
    },
  );
  test('server host and port build the specified download URL', () {
    final server = TestServer.fromApi({
      'id': '12108',
      'host': 'speed.time.com.my:8080',
      'url': 'http://speed.time.com.my:8080/speedtest/upload.php',
      'name': 'Shah Alam',
      'sponsor': 'TIME MY',
      'country': 'Malaysia',
      'distance': 3,
    });
    expect(
      server.downloadUrl,
      'http://speed.time.com.my:8080/download?size=25000000000',
    );
    expect(
      server.uploadUrl,
      'http://speed.time.com.my:8080/speedtest/upload.php',
    );
    expect(
      server.latencyUrl,
      'http://speed.time.com.my:8080/speedtest/latency.txt',
    );
    expect(
      TestServer.fromJson(server.toJson()).downloadUrl,
      server.downloadUrl,
    );
    expect(TestServer.fromJson(server.toJson()).uploadUrl, server.uploadUrl);
  });

  test('API upload URL keeps its own hostname, path, scheme and encoded query', () {
    const uploadUrl =
        'https://speedkl.time.com.my:8443/speedtest/upload.php?nonce=one%2Ftwo&region=MY';
    final server = TestServer.fromApi({
      'id': '50737',
      'host': 'speedkl.time.com.my.prod.hosts.ooklaserver.net:8080',
      'url': uploadUrl,
    });
    expect(server.uploadUrl, uploadUrl);
    expect(
      server.downloadUrl,
      'http://speedkl.time.com.my.prod.hosts.ooklaserver.net:8080/download?size=25000000000',
    );
    expect(TestServer.fromJson(server.toJson()).uploadUrl, uploadUrl);
  });

  test(
    'legacy saved upload is repaired from the original latency URL authority',
    () {
      final server = TestServer.fromJson({
        'id': 'ookla:50737',
        'uploadUrl':
            'http://speedkl.time.com.my.prod.hosts.ooklaserver.net:8080/upload',
        'downloadUrl':
            'http://speedkl.time.com.my.prod.hosts.ooklaserver.net:8080/download?size=25000000000',
        'latencyUrl': 'http://speedkl.time.com.my:8080/speedtest/latency.txt',
      });
      expect(
        server.uploadUrl,
        'http://speedkl.time.com.my:8080/speedtest/upload.php',
      );
      expect(TestServer.fromJson(server.toJson()).uploadUrl, server.uploadUrl);
    },
  );

  test(
    'custom and freshly advertised /upload endpoints stay exactly as supplied',
    () {
      final custom = TestServer.fromJson({
        'id': 'custom:1',
        'custom': true,
        'uploadUrl': 'http://lan.example:8080/upload',
        'latencyUrl': 'http://lan.example:8080/speedtest/latency.txt',
      });
      expect(custom.uploadUrl, 'http://lan.example:8080/upload');
      final advertised = TestServer.fromApi({
        'id': '1',
        'host': 'download.example:8080',
        'url': 'https://upload.example:8443/upload',
      });
      expect(
        TestServer.fromJson(advertised.toJson()).uploadUrl,
        'https://upload.example:8443/upload',
      );
    },
  );

  test(
    'missing or invalid API upload URLs cannot create an invented endpoint',
    () {
      expect(
        () => TestServer.fromApi({'id': '1', 'host': 'example.com:8080'}),
        throwsFormatException,
      );
      expect(
        () => TestServer.fromApi({
          'id': '1',
          'host': 'example.com:8080',
          'url': 'file:///tmp/upload',
        }),
        throwsFormatException,
      );
      final incomplete = TestServer.fromJson({
        'id': 'ookla:1',
        'uploadUrl': 'http://example.com:8080/upload',
      });
      expect(incomplete.uploadUrl, isNull);
    },
  );

  test('discovery sorts nearby servers and handles an invalid host', () {
    final discovery = Discovery.fromJson({
      'ipAddress': '203.0.113.1',
      'ispName': 'Example ISP',
      'location': {'cityName': 'Petaling Jaya', 'countryName': 'Malaysia'},
      'servers': [
        {
          'id': '2',
          'host': 'second.example:8080',
          'url': 'http://second.example:8080/speedtest/upload.php',
          'distance': 11,
        },
        {'id': 'bad', 'host': ''},
        {
          'id': '1',
          'host': 'first.example:8080',
          'url': 'http://first.example:8080/speedtest/upload.php',
          'distance': 3,
        },
      ],
    });
    expect(discovery.servers.map((s) => s.id), ['ookla:1', 'ookla:2']);
    expect(discovery.city, 'Petaling Jaya');
  });

  test('custom server can have a single endpoint', () {
    const server = TestServer(
      id: 'custom:1',
      name: '',
      sponsor: 'My server',
      country: '',
      downloadUrl: 'https://example.com/data',
      custom: true,
    );
    expect(server.supports(TestMode.download), isTrue);
    expect(server.supports(TestMode.normal), isFalse);
    expect(server.supports(TestMode.upload), isFalse);
  });

  test('units use decimal payload throughput', () {
    expect(SpeedUnit.megabytes.convert(800), 100);
    expect(SpeedUnit.mbps.format(800), '800.0');
    expect(formatBytes(1000000000), '1.00 GB');
  });

  test(
    'endpoint validation rejects credentials, fragments and non-HTTP schemes',
    () {
      expect(validTransferUrl('https://host.example/download?size=10'), isTrue);
      expect(validTransferUrl('http://192.168.1.20:8080/upload'), isTrue);
      expect(validTransferUrl('https://user:pass@host.example/'), isFalse);
      expect(validTransferUrl('file:///tmp/file'), isFalse);
      expect(validTransferUrl('http:///download'), isFalse);
      expect(validTransferUrl('https://host.example/data#frag'), isFalse);
    },
  );

  test('preferences retain theme, thread count and independent limits', () {
    final s = const AppSettings().copyWith(
      threads: 64,
      theme: ThemeMode.dark,
      mode: TestMode.download,
      clearDuration: true,
      maxBytes: 500000000,
    );
    final loaded = AppSettings.fromJson(s.toJson());
    expect(loaded.threads, 64);
    expect(loaded.theme, ThemeMode.dark);
    expect(loaded.sustainedSeconds, isNull);
    expect(loaded.maxBytes, 500000000);
  });
}
