import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/vpn_policy/full_tunnel.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows global mode enables TUN capture', () {
    const state = PatchClashConfig(
      mode: Mode.rule,
      tun: Tun(enable: false),
    );

    final next = configureGlobalFullTunnel(state, isWindows: true);

    expect(next.mode, Mode.global);
    expect(next.tun.enable, isTrue);
  });

  test('VPN Policy all-vpn capture enables Windows TUN without process rules', () {
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
  });

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
}