import 'dart:convert';

import 'package:fl_clash/common/common.dart';

String _vpnPolicySettingsKey(int profileId) => 'vpn_policy_settings_$profileId';
const _vpnPolicyConnectionKey = 'vpn_policy_connection_v1';

class VpnPolicySettings {
  final String serviceUrl;
  final String deviceKey;
  final String vpnTarget;
  final String lastRevision;
  final String lastPolicyName;
  final String localMode;
  final List<String> localAppSelectors;
  final List<String> localDomains;

  const VpnPolicySettings({
    this.serviceUrl = '',
    this.deviceKey = '',
    this.vpnTarget = '',
    this.lastRevision = '',
    this.lastPolicyName = '',
    this.localMode = 'only_selected',
    this.localAppSelectors = const [],
    this.localDomains = const [],
  });

  factory VpnPolicySettings.fromJson(Map<String, dynamic> json) {
    return VpnPolicySettings(
      serviceUrl: json['serviceUrl']?.toString() ?? '',
      deviceKey: json['deviceKey']?.toString() ?? '',
      vpnTarget: json['vpnTarget']?.toString() ?? '',
      lastRevision: json['lastRevision']?.toString() ?? '',
      lastPolicyName: json['lastPolicyName']?.toString() ?? '',
      localMode: json['localMode']?.toString() ?? 'only_selected',
      localAppSelectors: (json['localAppSelectors'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      localDomains: (json['localDomains'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }

  VpnPolicySettings copyWith({
    String? serviceUrl,
    String? deviceKey,
    String? vpnTarget,
    String? lastRevision,
    String? lastPolicyName,
    String? localMode,
    List<String>? localAppSelectors,
    List<String>? localDomains,
  }) {
    return VpnPolicySettings(
      serviceUrl: serviceUrl ?? this.serviceUrl,
      deviceKey: deviceKey ?? this.deviceKey,
      vpnTarget: vpnTarget ?? this.vpnTarget,
      lastRevision: lastRevision ?? this.lastRevision,
      lastPolicyName: lastPolicyName ?? this.lastPolicyName,
      localMode: localMode ?? this.localMode,
      localAppSelectors: localAppSelectors ?? this.localAppSelectors,
      localDomains: localDomains ?? this.localDomains,
    );
  }

  Map<String, dynamic> toJson() => {
    'serviceUrl': serviceUrl,
    'deviceKey': deviceKey,
    'vpnTarget': vpnTarget,
    'lastRevision': lastRevision,
    'lastPolicyName': lastPolicyName,
    'localMode': localMode,
    'localAppSelectors': localAppSelectors,
    'localDomains': localDomains,
  };
}

class VpnPolicySettingsStore {
  String _decodeSharedServiceUrl(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '';
    }
    try {
      final jsonValue = Map<String, dynamic>.from(json.decode(raw) as Map);
      return jsonValue['serviceUrl']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> saveConnection({
    required String serviceUrl,
    required String deviceKey,
  }) async {
    final shared = await preferences.sharedPreferencesCompleter.future;
    await shared?.setString(
      _vpnPolicyConnectionKey,
      json.encode({
        // The service URL may be shared across profiles. Device Key may not:
        // it identifies one FlClash profile/device on Policy Service.
        'serviceUrl': serviceUrl.trim(),
      }),
    );
  }

  Future<VpnPolicySettings> load(int profileId) async {
    final shared = await preferences.sharedPreferencesCompleter.future;
    VpnPolicySettings profile = const VpnPolicySettings();
    final raw = shared?.getString(_vpnPolicySettingsKey(profileId));
    if (raw != null && raw.isNotEmpty) {
      try {
        profile = VpnPolicySettings.fromJson(
          Map<String, dynamic>.from(json.decode(raw) as Map),
        );
      } catch (_) {}
    }

    var serviceUrl = _decodeSharedServiceUrl(
      shared?.getString(_vpnPolicyConnectionKey),
    );
    if (serviceUrl.isEmpty) {
      serviceUrl = profile.serviceUrl;
      if (serviceUrl.isNotEmpty) {
        await saveConnection(
          serviceUrl: serviceUrl,
          deviceKey: profile.deviceKey,
        );
      }
    }

    // Device Key always comes from this profile. A shared key could silently
    // authenticate as another device or as a profile that has been revoked.
    return profile.copyWith(serviceUrl: serviceUrl);
  }

  Future<void> save(int profileId, VpnPolicySettings settings) async {
    final shared = await preferences.sharedPreferencesCompleter.future;
    await Future.wait([
      shared?.setString(
            _vpnPolicySettingsKey(profileId),
            json.encode(settings.toJson()),
          ) ??
          Future.value(true),
      saveConnection(
        serviceUrl: settings.serviceUrl,
        deviceKey: settings.deviceKey,
      ),
    ]);
  }
}

final vpnPolicySettingsStore = VpnPolicySettingsStore();