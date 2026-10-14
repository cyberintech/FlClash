import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/vpn_policy/full_tunnel.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows global mode enables TUN capture', () {
    const state = PatchClashConfig(mode: Mode.rule, tun: Tun(enable: false));

    final next = configureGlobalFullTunnel(state, isWindows: true);

    expect(next.mode, Mode.global);
    expect(next.tun.enable, isTrue);
  });

  test(
    'VPN Policy all-vpn capture enables Windows TUN without process rules',
    () {
      const state = PatchClashConfig(
        mode: Mode.global,
        tun: Tun(enable: false),
        findProcessMode: FindProcessMode.off,
      );

      final next = configureVpnPolicyCapture(
        state,
        isWindows: true,
        hasProcessRules: false,
      );

      expect(next.mode, Mode.rule);
      expect(next.tun.enable, isTrue);
      expect(next.findProcessMode, FindProcessMode.off);
    },
  );

  test('VPN Policy process rules enable process discovery', () {
    const state = PatchClashConfig(findProcessMode: FindProcessMode.off);

    final next = configureVpnPolicyCapture(
      state,
      isWindows: false,
      hasProcessRules: true,
    );

    expect(next.mode, Mode.rule);
    expect(next.findProcessMode, FindProcessMode.always);
  });

  test('Android full capture disables outer package filtering', () {
    const state = VpnProps(
      enable: false,
      accessControlProps: AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['com.example.only'],
      ),
    );

    final next = configureAndroidFullCapture(state, isAndroid: true);

    expect(next.enable, isTrue);
    expect(next.accessControlProps.enable, isFalse);
    expect(next.accessControlProps.acceptList, ['com.example.only']);
  });
  test(
    'Global removes route restrictions and enables strict Windows capture',
    () {
      const state = PatchClashConfig(
        tun: Tun(
          routeAddress: ['1.1.1.1/32'],
          routeExcludeAddress: ['8.8.8.8/32'],
        ),
      );
      final next = configureGlobalFullTunnel(state, isWindows: true);
      expect(next.tun.autoRoute, isTrue);
      expect(next.tun.strictRoute, isTrue);
      expect(next.tun.routeAddress, isEmpty);
      expect(next.tun.routeExcludeAddress, isEmpty);
    },
  );

  test('Global replaces DIRECT with a VPN node', () {
    const groups = [
      Group(
        type: GroupType.Selector,
        name: 'GLOBAL',
        now: 'DIRECT',
        all: [
          Proxy(name: 'DIRECT', type: 'Direct'),
          Proxy(name: 'NUE-VLESS', type: 'Vless'),
        ],
      ),
    ];
    expect(globalVpnTarget(groups, {'GLOBAL': 'DIRECT'}), 'NUE-VLESS');
  });

  test('Global preserves an existing VPN selection', () {
    const groups = [
      Group(
        type: GroupType.Selector,
        name: 'GLOBAL',
        all: [
          Proxy(name: 'VPN-1', type: 'Vless'),
          Proxy(name: 'VPN-2', type: 'Vless'),
        ],
      ),
    ];
    expect(globalVpnTarget(groups, {'GLOBAL': 'VPN-2'}), 'VPN-2');
  });

  test('Global skips groups resolving to DIRECT and cyclic groups', () {
    const groups = [
      Group(
        type: GroupType.Selector,
        name: 'GLOBAL',
        all: [
          Proxy(name: 'Split', type: 'Selector'),
          Proxy(name: 'Loop', type: 'Selector'),
          Proxy(name: 'VPN', type: 'Vless'),
        ],
      ),
      Group(
        type: GroupType.Selector,
        name: 'Split',
        now: 'DIRECT',
        all: [Proxy(name: 'DIRECT', type: 'Direct')],
      ),
      Group(
        type: GroupType.Selector,
        name: 'Loop',
        now: 'Loop',
        all: [Proxy(name: 'Loop', type: 'Selector')],
      ),
    ];
    expect(globalVpnTarget(groups, {'GLOBAL': 'Split'}), 'VPN');
  });

  test('Global does not choose a renamed direct proxy', () {
    const groups = [
      Group(
        type: GroupType.Selector,
        name: 'GLOBAL',
        all: [Proxy(name: 'Looks-like-VPN', type: 'Direct')],
      ),
    ];
    expect(globalVpnTarget(groups, {}), isNull);
  });
  test(
    'a cold Global start replaces a saved DIRECT pick from its own profile',
    () {
      final config = <String, dynamic>{
        'proxies': [
          {'name': 'Local', 'type': 'direct'},
          {'name': 'VPN-1', 'type': 'vless'},
          {'name': 'VPN-2', 'type': 'vless'},
        ],
      };
      expect(globalVpnConfigTarget(config, {'GLOBAL': 'DIRECT'}), 'VPN-1');
      expect(globalVpnConfigTarget(config, {'GLOBAL': 'VPN-2'}), 'VPN-2');
      expect(
        globalVpnConfigTarget(config, {'VPN': 'VPN-2', 'GLOBAL': 'DIRECT'}),
        'VPN-2',
      );
    },
  );
}
