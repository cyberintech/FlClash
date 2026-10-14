import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

PatchClashConfig configureGlobalFullTunnel(
  PatchClashConfig state, {
  required bool isWindows,
}) {
  return state.copyWith(
    mode: Mode.global,
    tun: isWindows
        ? state.tun.copyWith(
            enable: true,
            autoRoute: true,
            strictRoute: true,
            routeAddress: const [],
            routeExcludeAddress: const [],
          )
        : state.tun,
  );
}

PatchClashConfig configureVpnPolicyCapture(
  PatchClashConfig state, {
  required bool isWindows,
  required bool hasProcessRules,
}) {
  return state.copyWith(
    mode: Mode.rule,
    findProcessMode: hasProcessRules
        ? FindProcessMode.always
        : state.findProcessMode,
    tun: isWindows ? state.tun.copyWith(enable: true) : state.tun,
  );
}

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

String? globalVpnTarget(List<Group> groups, Map<String, String> selected) {
  final global = groups.where((group) => group.name == 'GLOBAL').firstOrNull;
  if (global == null) return null;
  final byName = {for (final group in groups) group.name: group};
  final visited = <String>{};
  bool usesVpn(Proxy proxy) {
    if (!visited.add(proxy.name)) return false;
    final type = proxy.type.toLowerCase();
    if (const {
      'direct',
      'reject',
      'rejectdrop',
      'reject-drop',
      'pass',
      'compatible',
      'dns',
      'rematch',
    }.contains(type)) {
      return false;
    }
    final group = byName[proxy.name];
    if (group == null) return true;
    final name = selected[group.name] ?? group.now ?? '';
    final current = group.all.where((item) => item.name == name).firstOrNull;
    return current != null && usesVpn(current);
  }

  final currentName = selected['GLOBAL'] ?? global.now;
  for (final proxy in [
    ...global.all.where((item) => item.name == currentName),
    ...global.all.where((item) => item.name != currentName),
  ]) {
    visited.clear();
    if (usesVpn(proxy)) return proxy.name;
  }
  return null;
}

String? globalVpnConfigTarget(
  Map<String, dynamic> config,
  Map<String, String> selected,
) {
  final proxies = config['proxies'];
  if (proxies is! List) return null;
  final candidates = <String>[];
  for (final proxy in proxies) {
    if (proxy is! Map || proxy['type'] is! String || proxy['name'] is! String) {
      continue;
    }
    if (!const {
      'direct',
      'reject',
      'dns',
      'rematch',
    }.contains((proxy['type'] as String).toLowerCase())) {
      candidates.add(proxy['name'] as String);
    }
  }
  return candidates.where((name) => name == selected['GLOBAL']).firstOrNull ??
      candidates.where(selected.values.contains).firstOrNull ??
      candidates.firstOrNull;
}
