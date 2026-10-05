import 'package:fl_clash/models/clash_config.dart';

class VpnPolicyPayload {
  final int version;
  final String revision;
  final String deviceName;
  final String platform;
  final String policyName;
  final List<Rule> rules;

  const VpnPolicyPayload({
    required this.version,
    required this.revision,
    required this.deviceName,
    required this.platform,
    required this.policyName,
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

    return VpnPolicyPayload(
      version: data['version'] as int? ?? 1,
      revision: data['revision']?.toString() ?? '',
      deviceName: device['name']?.toString() ?? '',
      platform: device['platform']?.toString() ?? '',
      policyName: policy['name']?.toString() ?? '',
      rules: rules,
    );
  }
}
