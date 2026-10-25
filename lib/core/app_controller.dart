import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'platform_bridge.dart';
import 'strings.dart';

class AppController extends ChangeNotifier {
  AppController({AndroidBridge? bridge}) : bridge = bridge ?? AndroidBridge();
  final AndroidBridge bridge;
  AppSettings settings = const AppSettings();
  Map<String, dynamic> network = {};
  Discovery? discovery;
  List<TestServer> foundServers = [];
  List<TestServer> savedServers = [];
  List<TransferSnapshot> history = [];
  TestServer? selectedServer;
  TransferSnapshot? transfer;
  final List<double> samples = [];
  bool initialized = false;
  bool loadingServers = false;
  bool starting = false;
  bool stopping = false;
  bool requestingPermissions = false;
  String search = '';
  String? discoveryError;
  String? notice;
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _searchTimer;
  Timer? _saveTimer;
  Timer? _stopTimeoutTimer;
  int _discoveryVersion = 0;
  String? _networkSignature;
  bool _disposed = false;
  Future<void> _storageQueue = Future.value();

  bool get running => starting || transfer?.running == true;
  bool get connected => network['connected'] == true;
  bool isSaved(TestServer server) => savedServers.any((s) => s.id == server.id);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _error(Object e) => e is PlatformException
      ? e.message ?? 'Android operation failed'
      : e.toString();
  void clearNotice() {
    notice = null;
  }

  Future<void> initialize() async {
    try {
      final stored = await bridge.load();
      final rawSettings = stored['settings'] as String?;
      if (rawSettings != null) {
        final data = jsonDecode(rawSettings) as Map<String, dynamic>;
        settings = AppSettings.fromJson(data);
        if (data['selectedServer'] is Map) {
          final selected = Map<String, dynamic>.from(
            data['selectedServer'] as Map,
          );
          selectedServer = TestServer.fromJson(selected);
          if (selected['uploadEndpointVersion'] !=
              TestServer.uploadEndpointVersion) {
            _persistSettings();
          }
        }
      }
      final saved = jsonDecode(stored['servers'] as String? ?? '[]') as List;
      savedServers = saved
          .map((s) => TestServer.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
      if (saved.any(
        (s) =>
            (s as Map)['uploadEndpointVersion'] !=
            TestServer.uploadEndpointVersion,
      )) {
        _persistServers();
      }
      _loadHistory(stored);
      network = await bridge.network();
    } catch (e) {
      notice = _error(e);
    }
    if (_disposed) return;
    initialized = true;
    _events = bridge.stream.listen(
      _event,
      onError: (Object e) {
        notice = _error(e);
        _notify();
      },
    );
    _notify();
    await requestStartupPermissions();
    if (_disposed) return;
    if (connected) await discover();
  }

  void _loadHistory(Map<String, dynamic> stored) {
    history = ((jsonDecode(stored['history'] as String? ?? '[]')) as List)
        .map((s) => TransferSnapshot(Map<String, dynamic>.from(s as Map)))
        .toList();
  }

  void _event(Map<String, dynamic> event) {
    if (_disposed) return;
    final data = Map<String, dynamic>.from(event['data'] as Map);
    if (event['type'] == 'network') {
      network = data;
      final signature =
          '${data['transport']}:${data['localAddresses']}:${data['ssid']}';
      if (_networkSignature != null && signature != _networkSignature) {
        discovery = null;
        foundServers = [];
        discoveryError = null;
        _discoveryVersion++;
        loadingServers = false;
        _searchTimer?.cancel();
        if (connected) {
          _searchTimer = Timer(
            const Duration(milliseconds: 600),
            () => unawaited(discover()),
          );
        }
      }
      _networkSignature = signature;
    } else if (event['type'] == 'transfer') {
      final next = TransferSnapshot(data);
      final previous = transfer;
      if (previous?.id != next.id) samples.clear();
      transfer = next;
      starting = false;
      if (next.running) {
        samples.add(next.speed.toDouble());
        if (samples.length > 120) samples.removeAt(0);
      } else {
        stopping = false;
        _stopTimeoutTimer?.cancel();
        if (previous?.running == true || previous?.id != next.id) {
          unawaited(refreshHistory());
          if (next.status == 'error') notice = next.message;
        }
      }
    }
    _notify();
  }

  Future<void> discover() async {
    _searchTimer?.cancel();
    final version = ++_discoveryVersion;
    loadingServers = true;
    discoveryError = null;
    _notify();
    try {
      final result = await bridge.discover(search.trim());
      if (_disposed || version != _discoveryVersion) return;
      discovery = result;
      foundServers = result.servers;
      _refreshSavedServers(result.servers);
      if (selectedServer == null &&
          result.servers.isNotEmpty &&
          search.trim().isEmpty) {
        selectedServer = result.servers.first;
        _persistSettings();
      }
    } catch (e) {
      if (_disposed || version != _discoveryVersion) return;
      discoveryError = _error(e);
    } finally {
      if (!_disposed && version == _discoveryVersion) {
        loadingServers = false;
        _notify();
      }
    }
  }

  void _refreshSavedServers(List<TestServer> servers) {
    final byId = {for (final server in servers) server.id: server};
    var changed = false;
    savedServers = savedServers.map((saved) {
      final fresh = saved.custom ? null : byId[saved.id];
      if (fresh != null && !mapEquals(saved.toJson(), fresh.toJson())) {
        changed = true;
        return fresh;
      }
      return saved;
    }).toList();
    if (changed) {
      _persistServers();
    }
    final selected = selectedServer;
    if (selected != null && !selected.custom) {
      final fresh = byId[selected.id];
      if (fresh != null && !mapEquals(selected.toJson(), fresh.toJson())) {
        selectedServer = fresh;
        _persistSettings();
      }
    }
  }

  void setSearch(String value) {
    search = value;
    _searchTimer?.cancel();
    // Invalidate an in-flight request immediately, before the next debounced call starts.
    _discoveryVersion++;
    loadingServers = true;
    foundServers = [];
    discoveryError = null;
    _notify();
    _searchTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(discover()),
    );
  }

  void updateSettings(AppSettings value) {
    settings = value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), _persistSettings);
    _notify();
  }

  void _persistSettings() => _save('settings', {
    ...settings.toJson(),
    'selectedServer': selectedServer?.toJson(),
  });

  void _persistServers() =>
      _save('servers', savedServers.map((s) => s.toJson()).toList());

  void _save(String key, Object value) {
    // Serialize mutations so a slow earlier write cannot overwrite a newer selection.
    _storageQueue = _storageQueue
        .then((_) => bridge.save(key, value))
        .catchError((Object e) {
          notice = _error(e);
          _notify();
        });
  }

  void select(TestServer server) {
    if (running) return;
    selectedServer = server;
    _persistSettings();
    _notify();
  }

  void toggleFavorite(TestServer server) {
    if (isSaved(server)) {
      savedServers.removeWhere((s) => s.id == server.id);
    } else {
      savedServers.add(server);
    }
    _persistServers();
    _notify();
  }

  void addCustom(TestServer server) {
    savedServers.add(server);
    selectedServer = server;
    _persistServers();
    _persistSettings();
    _notify();
  }

  void removeCustom(TestServer server) {
    if (running && selectedServer?.id == server.id) return;
    savedServers.removeWhere((s) => s.id == server.id);
    if (selectedServer?.id == server.id) selectedServer = null;
    _persistServers();
    _persistSettings();
    _notify();
  }

  Future<void> start() async {
    final server = selectedServer;
    if (running || requestingPermissions || server == null || !connected) {
      return;
    }
    if (!server.supports(settings.mode)) {
      notice = S.incompatible;
      _notify();
      return;
    }
    starting = true;
    stopping = false;
    samples.clear();
    transfer = null;
    _persistSettings();
    _notify();
    try {
      final notifications = await bridge.requestNotifications();
      if (!notifications) {
        notice = S.notificationDenied;
        _notify();
      }
      await bridge.start({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'mode': settings.mode.name,
        'threads': settings.threads,
        'serverName': server.name.isEmpty
            ? server.sponsor
            : '${server.sponsor} · ${server.name}',
        'downloadUrl': server.downloadUrl,
        'uploadUrl': server.uploadUrl,
        'latencyUrl': server.latencyUrl,
        'durationSeconds': settings.mode == TestMode.normal
            ? settings.normalSeconds
            : settings.sustainedSeconds,
        'maxBytes': settings.mode == TestMode.normal ? null : settings.maxBytes,
        'unit': settings.unit.label,
      });
    } catch (e) {
      starting = false;
      notice = _error(e);
      _notify();
    }
  }

  Future<void> stop() async {
    if (!running) {
      if (stopping) {
        stopping = false;
        _notify();
      }
      return;
    }
    stopping = true;
    _stopTimeoutTimer?.cancel();
    _stopTimeoutTimer = Timer(const Duration(seconds: 4), () {
      if (stopping && !_disposed) {
        stopping = false;
        _notify();
      }
    });
    _notify();
    try {
      await bridge.stop();
      if (!running && stopping) {
        stopping = false;
        _stopTimeoutTimer?.cancel();
        _notify();
      }
    } catch (e) {
      stopping = false;
      _stopTimeoutTimer?.cancel();
      notice = _error(e);
      _notify();
    }
  }

  Future<void> requestStartupPermissions() async {
    if (_disposed || requestingPermissions) return;
    requestingPermissions = true;
    _notify();
    try {
      final granted = await bridge.requestStartupPermissions();
      if (_disposed) return;
      network = await bridge.network();
      if (!granted) notice = S.startupPermissionDenied;
    } catch (e) {
      notice = _error(e);
    } finally {
      requestingPermissions = false;
      _notify();
    }
  }

  Future<void> requestDetails() async {
    if (_disposed || requestingPermissions) return;
    requestingPermissions = true;
    _notify();
    try {
      final granted = await bridge.requestDetails();
      network = await bridge.network();
      if (!granted) {
        notice =
            'Some network details remain hidden. You can enable permissions in app settings.';
      }
    } catch (e) {
      notice = _error(e);
    } finally {
      requestingPermissions = false;
      _notify();
    }
  }

  Future<void> refreshHistory() async {
    try {
      await _storageQueue;
      _loadHistory(await bridge.load());
    } catch (e) {
      notice = _error(e);
    }
    _notify();
  }

  void clearHistory() {
    history = [];
    _save('history', []);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _saveTimer?.cancel();
    _stopTimeoutTimer?.cancel();
    _persistSettings();
    _events?.cancel();
    super.dispose();
  }
}
