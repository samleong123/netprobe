import 'strings.dart';

String networkHeaderLabel(Map<String, dynamic> network) {
  String text(String key) => network[key]?.toString().trim() ?? '';
  final transport = text('transport');
  if (transport == 'Wi-Fi') {
    final device = text('device');
    return device.isEmpty ? 'WiFi' : 'WiFi - $device';
  }
  if (transport != 'Mobile') {
    return transport.isEmpty ? S.offline : transport;
  }
  final country = text('networkCountryCode').toUpperCase();
  final operator = text('operator');
  final registered = operator.isEmpty ? S.mobileNetwork : operator;
  final prefixed =
      country.isEmpty || registered.toUpperCase().startsWith('$country ')
      ? registered
      : '$country $registered';
  final radio = text('networkType');
  // A carrier name can itself contain "5G"; it must not hide the radio type.
  final connection = radio.isEmpty || radio == 'Unknown'
      ? prefixed
      : '$prefixed $radio';
  final sim = text('simOperator');
  return '$connection | ${sim.isEmpty ? S.unavailable : sim}${network['roaming'] == true ? ' - R' : ''}';
}
