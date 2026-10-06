import 'package:fl_clash/features/vpn_policy/local_policy.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only selected routes apps and domains to VPN with DIRECT fallback', () {
    final rules = compileLocalVpnPolicy(
      mode: 'only_selected',
      vpnTarget: 'NUE-VLESS',
      appSelectors: const ['org.telegram.messenger'],
      domains: const ['https://ifconfig.me/path'],
    );

    expect(rules.map((rule) => rule.rawValue).toList(), [
      'PROCESS-NAME,org.telegram.messenger,NUE-VLESS',
      'DOMAIN-SUFFIX,ifconfig.me,NUE-VLESS',
      'MATCH,DIRECT',
    ]);
  });

  test('Chrome-only policy keeps every other app on DIRECT', () {
    final rules = compileLocalVpnPolicy(
      mode: 'only_selected',
      vpnTarget: 'NUE-VLESS',
      appSelectors: const ['chrome.exe'],
    );

    expect(rules.map((rule) => rule.rawValue).toList(), [
      'AND,((PROCESS-NAME,chrome.exe),(NETWORK,UDP),(DST-PORT,443)),REJECT',
      'PROCESS-NAME,chrome.exe,NUE-VLESS',
      'MATCH,DIRECT',
    ]);
  });

  test('YouTube app over NUE forces TCP fallback from QUIC', () {
    final rules = compileLocalVpnPolicy(
      mode: 'only_selected',
      vpnTarget: 'NUE-VLESS',
      appSelectors: const ['com.google.android.youtube'],
    );

    expect(rules.map((rule) => rule.rawValue).toList(), [
      'AND,((PROCESS-NAME,com.google.android.youtube),(NETWORK,UDP),(DST-PORT,443)),REJECT',
      'PROCESS-NAME,com.google.android.youtube,NUE-VLESS',
      'MATCH,DIRECT',
    ]);
  });

  test(
    'exclude selected routes selections direct and everything else to VPN',
    () {
      final rules = compileLocalVpnPolicy(
        mode: 'exclude_selected',
        vpnTarget: 'NUE-VLESS',
        appSelectors: const ['ru.oneme.app'],
      );

      expect(rules.map((rule) => rule.rawValue).toList(), [
        'PROCESS-NAME,ru.oneme.app,DIRECT',
        'MATCH,NUE-VLESS',
      ]);
    },
  );

  test('all vpn only needs a VPN fallback rule', () {
    final rules = compileLocalVpnPolicy(
      mode: 'all_vpn',
      vpnTarget: 'NUE-VLESS',
      appSelectors: const ['org.telegram.messenger'],
      domains: const ['example.com'],
    );

    expect(rules.map((rule) => rule.rawValue).toList(), [
      'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT',
      'MATCH,NUE-VLESS',
    ]);
  });
}
