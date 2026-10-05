import 'package:fl_clash/features/vpn_policy/policy_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses policy payload and rewrites abstract VPN target', () {
    final payload = VpnPolicyPayload.fromJson({
      'version': 1,
      'revision': '2026-10-05T00:00:00Z',
      'device': {'id': 2, 'name': 'laptop-main', 'platform': 'windows'},
      'policy': {
        'id': 1,
        'name': 'Selected',
        'mode': 'only_selected',
        'apps': ['telegram'],
        'services': ['youtube'],
        'custom_domains': ['example.com'],
      },
      'compiled': {
        'target': 'mihomo',
        'rules': [
          'PROCESS-NAME,Telegram.exe,VPN',
          'RULE-SET,youtube,VPN',
          'DOMAIN-SUFFIX,example.com,VPN',
          'MATCH,DIRECT',
        ],
      },
    }, vpnTarget: 'Proxy');

    expect(payload.version, 1);
    expect(payload.deviceName, 'laptop-main');
    expect(payload.platform, 'windows');
    expect(payload.policyName, 'Selected');
    expect(payload.rules, hasLength(4));

    expect(payload.rules[0].ruleTarget, 'Proxy');
    expect(payload.rules[0].rawValue, 'PROCESS-NAME,Telegram.exe,Proxy');

    expect(payload.rules[1].ruleProvider, 'youtube');
    expect(payload.rules[1].ruleTarget, 'Proxy');
    expect(payload.rules[1].rawValue, 'RULE-SET,youtube,Proxy');

    expect(payload.rules[2].rawValue, 'DOMAIN-SUFFIX,example.com,Proxy');
    expect(payload.rules[3].rawValue, 'MATCH,DIRECT');
  });
}
