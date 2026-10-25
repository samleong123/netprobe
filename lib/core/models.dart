import 'package:flutter/material.dart';

enum TestMode { normal, download, upload }

enum SpeedUnit { mbps, megabytes }

String formatBytes(num bytes) {
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
  if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
  if (bytes >= 1e3) return '${(bytes / 1e3).toStringAsFixed(1)} kB';
  return '${bytes.toInt()} B';
}

String formatDuration(num seconds) {
  final s = seconds.toInt();
  final hours = s ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  return hours > 0
      ? '${hours}h ${minutes}m'
      : '${minutes.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

extension SpeedUnitDisplay on SpeedUnit {
  String get label => this == SpeedUnit.mbps ? 'Mbps' : 'MB/s';
  double convert(num mbps) =>
      mbps.toDouble() / (this == SpeedUnit.mbps ? 1 : 8);
  String format(num? mbps) =>
      mbps == null ? '—' : convert(mbps).toStringAsFixed(1);
}

bool validTransferUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;
}

class TestServer {
  static const uploadEndpointVersion = 2;

  const TestServer({
    required this.id,
    required this.name,
    required this.sponsor,
    required this.country,
    this.distance,
    this.downloadUrl,
    this.uploadUrl,
    this.latencyUrl,
    this.custom = false,
  });

  final String id;
  final String name;
  final String sponsor;
  final String country;
  final double? distance;
  final String? downloadUrl;
  final String? uploadUrl;
  final String? latencyUrl;
  final bool custom;

  String get subtitle => [
    name,
    country,
    if (distance != null) '${distance!.toStringAsFixed(0)} km',
  ].where((s) => s.isNotEmpty).join(' · ');

  bool supports(TestMode mode) => switch (mode) {
    TestMode.normal => downloadUrl != null && uploadUrl != null,
    TestMode.download => downloadUrl != null,
    TestMode.upload => uploadUrl != null,
  };

  factory TestServer.fromApi(Map<String, dynamic> json) {
    final host = json['host']?.toString() ?? '';
    // Download uses the advertised host. Upload uses the API's separate URL.
    final base = Uri.tryParse('http://$host');
    if (base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.path.isNotEmpty) {
      throw const FormatException('Invalid server host');
    }
    final uploadUrl = json['url']?.toString() ?? '';
    if (uploadUrl != uploadUrl.trim() || !validTransferUrl(uploadUrl)) {
      throw const FormatException('Invalid server upload URL');
    }
    final latency = Uri.parse(uploadUrl).resolve('latency.txt').toString();
    return TestServer(
      id: 'ookla:${json['id']}',
      name: json['name']?.toString() ?? '',
      sponsor: json['sponsor']?.toString() ?? 'Speedtest server',
      country: json['country']?.toString() ?? '',
      distance: double.tryParse('${json['distance']}'),
      downloadUrl: base.resolve('/download?size=25000000000').toString(),
      uploadUrl: uploadUrl,
      latencyUrl: latency,
    );
  }

  factory TestServer.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final custom = json['custom'] as bool? ?? false;
    var uploadUrl = json['uploadUrl'] as String?;
    final latencyUrl = json['latencyUrl'] as String?;
    final cachedUpload = Uri.tryParse(uploadUrl ?? '');
    final oldVersion =
        (json['uploadEndpointVersion'] as num? ?? 1) < uploadEndpointVersion;
    if (!custom &&
        id.startsWith('ookla:') &&
        oldVersion &&
        cachedUpload != null &&
        cachedUpload.path == '/upload' &&
        !cachedUpload.hasQuery) {
      // Earlier versions derived /upload from host but saved the original
      // upload.php authority in the adjacent speedtest/latency.txt URL.
      final latency = Uri.tryParse(latencyUrl ?? '');
      if (latency != null &&
          latency.path == '/speedtest/latency.txt' &&
          validTransferUrl(latencyUrl ?? '')) {
        uploadUrl = latency.resolve('upload.php').toString();
      } else {
        uploadUrl = null;
      }
      // Without that metadata, wait for an authoritative discovery refresh.
    }
    return TestServer(
      id: id,
      name: json['name'] as String? ?? '',
      sponsor: json['sponsor'] as String? ?? 'Custom server',
      country: json['country'] as String? ?? '',
      distance: (json['distance'] as num?)?.toDouble(),
      downloadUrl: json['downloadUrl'] as String?,
      uploadUrl: uploadUrl,
      latencyUrl: latencyUrl,
      custom: custom,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sponsor': sponsor,
    'country': country,
    'distance': distance,
    'downloadUrl': downloadUrl,
    'uploadUrl': uploadUrl,
    'latencyUrl': latencyUrl,
    'custom': custom,
    'uploadEndpointVersion': uploadEndpointVersion,
  };
}

class Discovery {
  const Discovery(this.ip, this.isp, this.city, this.country, this.servers);
  final String ip;
  final String isp;
  final String city;
  final String country;
  final List<TestServer> servers;

  factory Discovery.fromJson(Map<String, dynamic> json) {
    final location = (json['location'] as Map?) ?? {};
    final servers = <TestServer>[];
    for (final entry in (json['servers'] as List?) ?? []) {
      try {
        final server = TestServer.fromApi(
          Map<String, dynamic>.from(entry as Map),
        );
        if (!servers.any((s) => s.id == server.id)) servers.add(server);
      } on FormatException {
        continue;
      }
    }
    servers.sort(
      (a, b) => (a.distance ?? double.infinity).compareTo(
        b.distance ?? double.infinity,
      ),
    );
    return Discovery(
      json['ipAddress']?.toString() ?? '',
      json['ispName']?.toString() ?? '',
      location['cityName']?.toString() ?? '',
      location['countryName']?.toString() ?? '',
      servers,
    );
  }
}

class AppSettings {
  const AppSettings({
    this.threads = 8,
    this.mode = TestMode.normal,
    this.unit = SpeedUnit.mbps,
    this.theme = ThemeMode.system,
    this.normalSeconds = 15,
    this.sustainedSeconds = 60,
    this.maxBytes = 1000000000,
  });

  final int threads;
  final TestMode mode;
  final SpeedUnit unit;
  final ThemeMode theme;
  final int normalSeconds;
  final int? sustainedSeconds;
  final int? maxBytes;

  AppSettings copyWith({
    int? threads,
    TestMode? mode,
    SpeedUnit? unit,
    ThemeMode? theme,
    int? normalSeconds,
    int? sustainedSeconds,
    int? maxBytes,
    bool clearDuration = false,
    bool clearBudget = false,
  }) => AppSettings(
    threads: threads ?? this.threads,
    mode: mode ?? this.mode,
    unit: unit ?? this.unit,
    theme: theme ?? this.theme,
    normalSeconds: normalSeconds ?? this.normalSeconds,
    sustainedSeconds: clearDuration
        ? null
        : sustainedSeconds ?? this.sustainedSeconds,
    maxBytes: clearBudget ? null : maxBytes ?? this.maxBytes,
  );

  Map<String, dynamic> toJson() => {
    'threads': threads,
    'mode': mode.name,
    'unit': unit.name,
    'theme': theme.name,
    'normalSeconds': normalSeconds,
    'sustainedSeconds': sustainedSeconds,
    'maxBytes': maxBytes,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    threads: (json['threads'] as int? ?? 8).clamp(1, 64),
    mode: TestMode.values.firstWhere(
      (v) => v.name == json['mode'],
      orElse: () => TestMode.normal,
    ),
    unit: SpeedUnit.values.firstWhere(
      (v) => v.name == json['unit'],
      orElse: () => SpeedUnit.mbps,
    ),
    theme: ThemeMode.values.firstWhere(
      (v) => v.name == json['theme'],
      orElse: () => ThemeMode.system,
    ),
    normalSeconds: (json['normalSeconds'] as int? ?? 15).clamp(1, 86400),
    sustainedSeconds: json.containsKey('sustainedSeconds')
        ? json['sustainedSeconds'] as int?
        : 60,
    maxBytes: json.containsKey('maxBytes')
        ? json['maxBytes'] as int?
        : 1000000000,
  );
}

class TransferSnapshot {
  TransferSnapshot(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String? ?? '';
  String get status => data['status'] as String? ?? 'idle';
  String get phase => data['phase'] as String? ?? 'starting';
  bool get running => status == 'running';
  num get speed => data['speedMbps'] as num? ?? 0;
  num get totalBytes => data['totalBytes'] as num? ?? 0;
  num get elapsed => data['elapsedSeconds'] as num? ?? 0;
  num? get download => data['downloadMbps'] as num?;
  num? get upload => data['uploadMbps'] as num?;
  num? get latency => data['latencyMs'] as num?;
  String? get message => data['message'] as String?;
}
