import 'dart:convert';

import 'package:fl_clash/common/common.dart';

String _vpnPolicySettingsKey(int profileId) => 'vpn_policy_settings_$profileId';

class VpnPolicySettings {
  final String serviceUrl;
  final String deviceKey;
  final String vpnTarget;
  final String lastRevision;
  final String lastPolicyName;

  const VpnPolicySettings({
    this.serviceUrl = '',
    this.deviceKey = '',
    this.vpnTarget = '',
    this.lastRevision = '',
    this.lastPolicyName = '',
  });

  factory VpnPolicySettings.fromJson(Map<String, dynamic> json) {
    return VpnPolicySettings(
      serviceUrl: json['serviceUrl']?.toString() ?? '',
      deviceKey: json['deviceKey']?.toString() ?? '',
      vpnTarget: json['vpnTarget']?.toString() ?? '',
      lastRevision: json['lastRevision']?.toString() ?? '',
      lastPolicyName: json['lastPolicyName']?.toString() ?? '',
    );
  }

  VpnPolicySettings copyWith({
    String? serviceUrl,
    String? deviceKey,
    String? vpnTarget,
    String? lastRevision,
    String? lastPolicyName,
  }) {
    return VpnPolicySettings(
      serviceUrl: serviceUrl ?? this.serviceUrl,
      deviceKey: deviceKey ?? this.deviceKey,
      vpnTarget: vpnTarget ?? this.vpnTarget,
      lastRevision: lastRevision ?? this.lastRevision,
      lastPolicyName: lastPolicyName ?? this.lastPolicyName,
    );
  }

  Map<String, dynamic> toJson() => {
    'serviceUrl': serviceUrl,
    'deviceKey': deviceKey,
    'vpnTarget': vpnTarget,
    'lastRevision': lastRevision,
    'lastPolicyName': lastPolicyName,
  };
}

class VpnPolicySettingsStore {
  Future<VpnPolicySettings> load(int profileId) async {
    final shared = await preferences.sharedPreferencesCompleter.future;
    final raw = shared?.getString(_vpnPolicySettingsKey(profileId));
    if (raw == null || raw.isEmpty) {
      return const VpnPolicySettings();
    }
    try {
      return VpnPolicySettings.fromJson(
        Map<String, dynamic>.from(json.decode(raw) as Map),
      );
    } catch (_) {
      return const VpnPolicySettings();
    }
  }

  Future<void> save(int profileId, VpnPolicySettings settings) async {
    final shared = await preferences.sharedPreferencesCompleter.future;
    await shared?.setString(
      _vpnPolicySettingsKey(profileId),
      json.encode(settings.toJson()),
    );
  }
}

final vpnPolicySettingsStore = VpnPolicySettingsStore();
