import 'package:fl_clash/models/clash_config.dart';

class VpnPolicyPayload {
  final int version;
  final String revision;
  final String deviceName;
  final String platform;
  final int policyId;
  final String policyName;
  final String mode;
  final List<String> apps;
  final List<String> services;
  final List<String> customDomains;
  final List<String> customAppSelectors;
  final List<Rule> rules;

  const VpnPolicyPayload({
    required this.version,
    required this.revision,
    required this.deviceName,
    required this.platform,
    required this.policyId,
    required this.policyName,
    required this.mode,
    required this.apps,
    required this.services,
    required this.customDomains,
    required this.customAppSelectors,
    required this.rules,
  });

  factory VpnPolicyPayload.fromJson(
    Map<String, dynamic> data, {
    required String vpnTarget,
  }) {
    final device = Map<String, dynamic>.from(data['device'] as Map);
    final policy = Map<String, dynamic>.from(data['policy'] as Map);
    final compiled = Map<String, dynamic>.from(data['compiled'] as Map);
    final rawRules = (compiled['rules'] as List).cast<String>();

    final rules = rawRules
        .map((raw) {
          final rule = Rule.parse(raw);
          return rule.ruleTarget == 'VPN'
              ? rule.copyWith(ruleTarget: vpnTarget)
              : rule;
        })
        .toList(growable: false);

    List<String> strings(String key) => (policy[key] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);

    return VpnPolicyPayload(
      version: data['version'] as int? ?? 1,
      revision: data['revision']?.toString() ?? '',
      deviceName: device['name']?.toString() ?? '',
      platform: device['platform']?.toString() ?? '',
      policyId: policy['id'] as int? ?? 0,
      policyName: policy['name']?.toString() ?? '',
      mode: policy['mode']?.toString() ?? 'only_selected',
      apps: strings('apps'),
      services: strings('services'),
      customDomains: strings('custom_domains'),
      customAppSelectors: strings('custom_app_selectors'),
      rules: rules,
    );
  }
}
