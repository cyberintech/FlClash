class VpnPolicyRuleSet {
  final int id;
  final String name;
  final String description;
  final String revision;
  final List<String> appSelectors;
  final List<String> domains;

  const VpnPolicyRuleSet({
    required this.id,
    required this.name,
    required this.description,
    required this.revision,
    required this.appSelectors,
    required this.domains,
  });

  factory VpnPolicyRuleSet.fromJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(
      json['resolved'] as Map? ?? const <String, dynamic>{},
    );
    List<String> strings(Object? value) => (value as List? ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);

    return VpnPolicyRuleSet(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      revision: json['revision']?.toString() ?? '',
      appSelectors: strings(resolved['app_selectors']),
      domains: strings(resolved['domains']),
    );
  }
}
