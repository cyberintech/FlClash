import 'package:fl_clash/features/vpn_policy/policy_payload.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses semantic policy and rewrites abstract VPN target', () {
    final payload = VpnPolicyPayload.fromJson({
      'version': 2,
      'revision': '2026-10-05T00:00:00Z',
      'device': {'id': 2, 'name': 'laptop-main', 'platform': 'windows'},
      'policy': {
        'id': 9,
        'name': 'Selected',
        'mode': 'only_selected',
        'apps': ['telegram'],
        'services': ['youtube'],
        'custom_domains': ['example.com'],
        'custom_app_selectors': ['special.exe'],
      },
      'compiled': {
        'target': 'mihomo',
        'rules': [
          'PROCESS-NAME,Telegram.exe,VPN',
          'PROCESS-NAME,special.exe,VPN',
          'RULE-SET,youtube,VPN',
          'DOMAIN-SUFFIX,example.com,VPN',
          'MATCH,DIRECT',
        ],
      },
    }, vpnTarget: 'Proxy');

    expect(payload.version, 2);
    expect(payload.deviceName, 'laptop-main');
    expect(payload.platform, 'windows');
    expect(payload.policyId, 9);
    expect(payload.policyName, 'Selected');
    expect(payload.mode, 'only_selected');
    expect(payload.apps, ['telegram']);
    expect(payload.services, ['youtube']);
    expect(payload.customDomains, ['example.com']);
    expect(payload.customAppSelectors, ['special.exe']);
    expect(payload.rules, hasLength(5));

    expect(payload.rules[0].ruleTarget, 'Proxy');
    expect(payload.rules[0].rawValue, 'PROCESS-NAME,Telegram.exe,Proxy');
    expect(payload.rules[1].rawValue, 'PROCESS-NAME,special.exe,Proxy');
    expect(payload.rules[2].ruleProvider, 'youtube');
    expect(payload.rules[2].ruleTarget, 'Proxy');
    expect(payload.rules[4].rawValue, 'MATCH,DIRECT');
  });
}
