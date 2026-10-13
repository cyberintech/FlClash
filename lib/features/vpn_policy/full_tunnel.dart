import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

/// Global mode in our VPN fork means a real full tunnel, not merely
/// "use GLOBAL for traffic that already happens to enter Mihomo".
PatchClashConfig configureGlobalFullTunnel(
  PatchClashConfig state, {
  required bool isWindows,
}) {
  return state.copyWith(
    mode: Mode.global,
    tun: isWindows ? state.tun.copyWith(enable: true) : state.tun,
  );
}

/// VPN Policy is implemented with Mihomo rules, so Windows must capture all
/// system traffic even when the policy contains only MATCH/domain rules and no
/// PROCESS-NAME rules. Otherwise "all_vpn" is only global inside Mihomo, while
/// non-proxy-aware applications never enter the core at all.
PatchClashConfig configureVpnPolicyCapture(
  PatchClashConfig state, {
  required bool isWindows,
  required bool hasProcessRules,
}) {
  return state.copyWith(
    mode: Mode.rule,
    findProcessMode:
        hasProcessRules ? FindProcessMode.always : state.findProcessMode,
    tun: isWindows ? state.tun.copyWith(enable: true) : state.tun,
  );
}

/// Android's VpnService package allow/deny filter sits outside Mihomo. VPN
/// Policy already performs split routing inside Mihomo, so a second Android
/// app filter would make "Global" or policy rules silently miss applications.
VpnProps configureAndroidFullCapture(
  VpnProps state, {
  required bool isAndroid,
}) {
  if (!isAndroid) return state;
  return state.copyWith(
    enable: true,
    accessControlProps: state.accessControlProps.copyWith(enable: false),
  );
}