import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';
import 'package:yaml/yaml.dart' as yaml_parser;

class VpnPolicyProfileBootstrap {
  final Uint8List configBytes;
  final VpnPolicySettings settings;

  const VpnPolicyProfileBootstrap({
    required this.configBytes,
    required this.settings,
  });
}

Object? _plainYaml(Object? value) {
  if (value is yaml_parser.YamlMap) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _plainYaml(entry.value),
    };
  }
  if (value is yaml_parser.YamlList) {
    return [for (final item in value) _plainYaml(item)];
  }
  return value;
}

VpnPolicyProfileBootstrap? parseVpnPolicyProfileBootstrap(Uint8List bytes) {
  final text = utf8.decode(bytes);
  final loaded = yaml_parser.loadYaml(text);
  if (loaded is! yaml_parser.YamlMap) {
    return null;
  }

  final plain = _plainYaml(loaded);
  if (plain is! Map<String, Object?>) {
    return null;
  }
  final metadata = plain['x-vpn-policy'];
  if (metadata is! Map) {
    return null;
  }

  final meta = {
    for (final entry in metadata.entries)
      entry.key.toString(): entry.value,
  };
  final serviceUrl = meta['service-url']?.toString().trim() ?? '';
  final deviceKey = meta['device-key']?.toString().trim() ?? '';
  if (serviceUrl.isEmpty || deviceKey.isEmpty) {
    return null;
  }

  List<String> strings(Object? value) => (value as List? ?? const [])
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);

  final config = Map<String, Object?>.from(plain)
    ..remove('x-vpn-policy');
  final cleaned = Uint8List.fromList(
    utf8.encode(yaml.encode(config)),
  );

  return VpnPolicyProfileBootstrap(
    configBytes: cleaned,
    settings: VpnPolicySettings(
      serviceUrl: serviceUrl,
      deviceKey: deviceKey,
      lastRevision: meta['revision']?.toString() ?? '',
      lastPolicyName: meta['policy-name']?.toString() ?? '',
      localMode: meta['mode']?.toString() ?? 'only_selected',
      localApps: strings(meta['apps']),
      localServices: strings(meta['services']),
      localAppSelectors: strings(meta['app-selectors']),
      localDomains: strings(meta['domains']),
    ),
  );
}