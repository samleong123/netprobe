import 'dart:convert';
import 'package:flutter/services.dart';
import 'models.dart';

class AndroidBridge {
  static const control = MethodChannel('dev.sam.speedtest/control');
  static const events = EventChannel('dev.sam.speedtest/events');

  Stream<Map<String, dynamic>> get stream => events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  Future<Map<String, dynamic>> network() async => Map<String, dynamic>.from(
    await control.invokeMapMethod<String, dynamic>('network') ?? {},
  );

  Future<Map<String, dynamic>> load() async => Map<String, dynamic>.from(
    await control.invokeMapMethod<String, dynamic>('load') ?? {},
  );

  Future<Discovery> discover(String search) async {
    final raw = await control.invokeMethod<String>('fetchConfig', {
      'search': search,
    });
    return Discovery.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
  }

  Future<void> save(String key, Object value) =>
      control.invokeMethod('save', {'key': key, 'value': jsonEncode(value)});

  Future<void> start(Map<String, dynamic> config) =>
      control.invokeMethod('start', config);
  Future<void> stop() => control.invokeMethod('stop');
  Future<bool> requestNotifications() async =>
      await control.invokeMethod<bool>('requestNotifications') ?? false;
  Future<bool> requestDetails() async =>
      await control.invokeMethod<bool>('requestDetails') ?? false;
  Future<bool> requestStartupPermissions() async =>
      await control.invokeMethod<bool>('requestStartupPermissions') ?? false;
  Future<void> locationSettings() => control.invokeMethod('locationSettings');
  Future<void> appSettings() => control.invokeMethod('appSettings');
  Future<void> openUrl(String url) =>
      control.invokeMethod('openUrl', {'url': url});
}
