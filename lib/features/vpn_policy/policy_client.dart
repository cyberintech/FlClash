import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/vpn_policy/policy_payload.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';

class VpnPolicyClient {
  final Dio _dio;

  VpnPolicyClient({Dio? dio}) : _dio = dio ?? request.dio;

  Future<VpnPolicyPayload> fetch(
    VpnPolicySettings settings, {
    required String vpnTarget,
  }) async {
    final serviceUrl = settings.serviceUrl.trim().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    final response = await _dio.get<Map<String, dynamic>>(
      '$serviceUrl/client/v1/policy',
      options: Options(
        headers: {'Authorization': 'Bearer ${settings.deviceKey.trim()}'},
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('Policy Service returned no data');
    }
    return VpnPolicyPayload.fromJson(data, vpnTarget: vpnTarget);
  }
}

final vpnPolicyClient = VpnPolicyClient();
