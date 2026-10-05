import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/vpn_policy/policy_catalog.dart';
import 'package:fl_clash/features/vpn_policy/policy_payload.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';

class VpnPolicyClient {
  final Dio _dio;

  VpnPolicyClient({Dio? dio}) : _dio = dio ?? request.dio;

  String _base(VpnPolicySettings settings) =>
      settings.serviceUrl.trim().replaceFirst(RegExp(r'/$'), '');

  Options _options(VpnPolicySettings settings) => Options(
    headers: {'Authorization': 'Bearer ${settings.deviceKey.trim()}'},
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 15),
  );

  Future<VpnPolicyCatalog> fetchCatalog(VpnPolicySettings settings) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${_base(settings)}/client/v1/catalog',
      options: _options(settings),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('Policy Service returned no catalog');
    }
    return VpnPolicyCatalog.fromJson(data);
  }

  Future<VpnPolicyPayload> fetch(
    VpnPolicySettings settings, {
    required String vpnTarget,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${_base(settings)}/client/v1/policy',
      options: _options(settings),
    );
    return _payload(response, vpnTarget: vpnTarget);
  }

  Future<VpnPolicyPayload> update(
    VpnPolicySettings settings, {
    required String vpnTarget,
    required String mode,
    required List<String> apps,
    required List<String> services,
    required List<String> customDomains,
    required List<String> customAppSelectors,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '${_base(settings)}/client/v1/policy',
      data: {
        'mode': mode,
        'apps': apps,
        'services': services,
        'custom_domains': customDomains,
        'custom_app_selectors': customAppSelectors,
      },
      options: _options(settings),
    );
    return _payload(response, vpnTarget: vpnTarget);
  }

  VpnPolicyPayload _payload(
    Response<Map<String, dynamic>> response, {
    required String vpnTarget,
  }) {
    final data = response.data;
    if (data == null) {
      throw StateError('Policy Service returned no policy');
    }
    return VpnPolicyPayload.fromJson(data, vpnTarget: vpnTarget);
  }
}

final vpnPolicyClient = VpnPolicyClient();
