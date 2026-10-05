class VpnPolicyCatalogApp {
  final String key;
  final String title;
  final List<String> selectors;

  const VpnPolicyCatalogApp({
    required this.key,
    required this.title,
    required this.selectors,
  });

  factory VpnPolicyCatalogApp.fromJson(Map<String, dynamic> json) {
    return VpnPolicyCatalogApp(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      selectors: (json['selectors'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}

class VpnPolicyCatalogService {
  final String key;
  final String title;
  final List<String> domains;

  const VpnPolicyCatalogService({
    required this.key,
    required this.title,
    required this.domains,
  });

  factory VpnPolicyCatalogService.fromJson(Map<String, dynamic> json) {
    return VpnPolicyCatalogService(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      domains: (json['domains'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}

class VpnPolicyCatalog {
  final String platform;
  final List<VpnPolicyCatalogApp> apps;
  final List<VpnPolicyCatalogService> services;

  const VpnPolicyCatalog({
    required this.platform,
    required this.apps,
    required this.services,
  });

  factory VpnPolicyCatalog.fromJson(Map<String, dynamic> json) {
    return VpnPolicyCatalog(
      platform: json['platform']?.toString() ?? '',
      apps: (json['apps'] as List? ?? const [])
          .map(
            (value) => VpnPolicyCatalogApp.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
      services: (json['services'] as List? ?? const [])
          .map(
            (value) => VpnPolicyCatalogService.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, String> get selectorToAppKey {
    final result = <String, String>{};
    for (final app in apps) {
      for (final selector in app.selectors) {
        result[selector] = app.key;
      }
    }
    return result;
  }
}
