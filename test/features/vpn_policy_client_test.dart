import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/vpn_policy/policy_client.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? requested;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested = options;
    return ResponseBody.fromString(
      jsonEncode({
        'version': 1,
        'revision': 'rev-1',
        'device': {'name': 'laptop-main', 'platform': 'windows'},
        'policy': {'name': 'Selected'},
        'compiled': {
          'rules': ['PROCESS-NAME,Telegram.exe,VPN', 'MATCH,DIRECT'],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('fetches device policy and forwards the device key', () async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final client = VpnPolicyClient(dio: dio);

    final payload = await client.fetch(
      const VpnPolicySettings(
        serviceUrl: 'https://policy.example.com/',
        deviceKey: 'device-key',
      ),
      vpnTarget: 'Proxy',
    );

    expect(adapter.requested?.uri.path, '/client/v1/policy');
    expect(adapter.requested?.headers['Authorization'], 'Bearer device-key');
    expect(payload.deviceName, 'laptop-main');
    expect(payload.policyName, 'Selected');
    expect(payload.rules.first.rawValue, 'PROCESS-NAME,Telegram.exe,Proxy');
    expect(payload.rules.last.rawValue, 'MATCH,DIRECT');
  });
}
