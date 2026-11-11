import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/features/vpn_policy/profile_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'shared profile defaults to VPN without copying shared rules into overrides',
    () {
      final parsed = parseVpnPolicyProfileBootstrap(
        Uint8List.fromList(
          utf8.encode('''
x-vpn-policy:
  format-version: 2
  shared-rules: true
  service-url: https://policy.example
  device-key: new-device
rules: ["RULE-SET,VPN-Shared-VPN,VPN", "MATCH,DIRECT"]
'''),
        ),
      );
      expect(parsed!.settings.vpnTarget, 'VPN');
      expect(parsed.settings.sharedRules, isTrue);
      expect(parsed.settings.localRules, isEmpty);
    },
  );
  test('invalid YAML is left for the normal config validator', () {
    expect(
      parseVpnPolicyProfileBootstrap(Uint8List.fromList(utf8.encode('bad: ['))),
      isNull,
    );
  });
  test('extracts VPN Policy bootstrap metadata and strips it from config', () {
    const input = '''
x-vpn-policy:
  service-url: https://cyberintellect.tech/vpn-policy
  device-key: vp1_test
  device-name: desktop-main
  policy-name: Main
  revision: rev-1
  mode: only_selected
  app-selectors:
    - chrome.exe
  domains:
    - youtube.com
mixed-port: 7890
proxies:
  - name: NUE-VLESS
    type: vless
    server: 203.0.113.10
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
rules:
  - PROCESS-NAME,chrome.exe,NUE-VLESS
  - DOMAIN-SUFFIX,youtube.com,NUE-VLESS
  - MATCH,DIRECT
''';

    final parsed = parseVpnPolicyProfileBootstrap(
      Uint8List.fromList(utf8.encode(input)),
    );

    expect(parsed, isNotNull);
    expect(parsed!.settings.deviceKey, 'vp1_test');
    expect(parsed.settings.lastPolicyName, 'Main');
    expect(parsed.settings.localMode, 'only_selected');
    expect(parsed.settings.localAppSelectors, ['chrome.exe']);
    expect(parsed.settings.localDomains, ['youtube.com']);

    final config = loadYaml(utf8.decode(parsed.configBytes)) as YamlMap;
    expect(config.containsKey('x-vpn-policy'), isFalse);
    expect(config['mixed-port'], 7890);
    expect((config['rules'] as YamlList).length, 3);
  });
}
