import 'package:fl_clash/features/vpn_policy/local_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only selected routes apps and domains to VPN with DIRECT fallback', () {
    final rules = compileLocalVpnPolicy(
      mode: 'only_selected',
      vpnTarget: 'NUE-VLESS',
      appSelectors: const ['org.telegram.messenger'],
      domains: const ['https://ifconfig.me/path'],
    );

    expect(
      rules.map((rule) => rule.rawValue).toList(),
      [
        'PROCESS-NAME,org.telegram.messenger,NUE-VLESS',
        'DOMAIN-SUFFIX,ifconfig.me,NUE-VLESS',
        'MATCH,DIRECT',
      ],
    );
  });

  test('exclude selected routes selections direct and everything else to VPN', () {
    final rules = compileLocalVpnPolicy(
      mode: 'exclude_selected',
      vpnTarget: 'NUE-VLESS',
      appSelectors: const ['ru.oneme.app'],
    );

    expect(
      rules.map((rule) => rule.rawValue).toList(),
      [
        'PROCESS-NAME,ru.oneme.app,DIRECT',
        'MATCH,NUE-VLESS',
      ],
    );
  });

  test('all vpn only needs a VPN fallback rule', () {
    final rules = compileLocalVpnPolicy(
      mode: 'all_vpn',
      vpnTarget: 'NUE-VLESS',
      appSelectors: const ['org.telegram.messenger'],
      domains: const ['example.com'],
    );

    expect(
      rules.map((rule) => rule.rawValue).toList(),
      ['MATCH,NUE-VLESS'],
    );
  });
}
