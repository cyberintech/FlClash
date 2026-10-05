import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/vpn_policy/policy_client.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final requested = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options);

    Object response;
    if (options.uri.path.endsWith('/client/v1/catalog')) {
      response = {
        'version': 1,
        'platform': 'windows',
        'apps': [
          {
            'key': 'telegram',
            'title': 'Telegram',
            'selectors': ['Telegram.exe'],
          },
        ],
        'services': [
          {
            'key': 'chatgpt',
            'title': 'ChatGPT',
            'domains': ['chatgpt.com'],
          },
        ],
      };
    } else {
      final update = options.method == 'PUT';
      response = {
        'version': 2,
        'revision': update ? 'rev-2' : 'rev-1',
        'device': {'name': 'laptop-main', 'platform': 'windows'},
        'policy': {
          'id': 4,
          'name': 'Selected',
          'mode': update ? 'exclude_selected' : 'only_selected',
          'apps': update ? [] : ['telegram'],
          'services': update ? ['chatgpt'] : [],
          'custom_domains': update ? ['example.com'] : [],
          'custom_app_selectors': update ? ['special.exe'] : [],
        },
        'compiled': {
          'rules': update
              ? [
                  'PROCESS-NAME,special.exe,DIRECT',
                  'DOMAIN-SUFFIX,chatgpt.com,DIRECT',
                  'DOMAIN-SUFFIX,example.com,DIRECT',
                  'MATCH,VPN',
                ]
              : ['PROCESS-NAME,Telegram.exe,VPN', 'MATCH,DIRECT'],
        },
      };
    }

    return ResponseBody.fromString(
      jsonEncode(response),
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
  const settings = VpnPolicySettings(
    serviceUrl: 'https://policy.example.com/base/',
    deviceKey: 'device-key',
  );

  test('fetches catalog and policy with the device key', () async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final client = VpnPolicyClient(dio: dio);

    final catalog = await client.fetchCatalog(settings);
    final payload = await client.fetch(settings, vpnTarget: 'Proxy');

    expect(catalog.platform, 'windows');
    expect(catalog.apps.single.key, 'telegram');
    expect(catalog.selectorToAppKey['Telegram.exe'], 'telegram');
    expect(catalog.services.single.key, 'chatgpt');

    expect(adapter.requested[0].uri.path, '/base/client/v1/catalog');
    expect(adapter.requested[1].uri.path, '/base/client/v1/policy');
    for (final request in adapter.requested) {
      expect(request.headers['Authorization'], 'Bearer device-key');
    }

    expect(payload.deviceName, 'laptop-main');
    expect(payload.apps, ['telegram']);
    expect(payload.rules.first.rawValue, 'PROCESS-NAME,Telegram.exe,Proxy');
    expect(payload.rules.last.rawValue, 'MATCH,DIRECT');
  });

  test('updates native policy fields and parses returned rules', () async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final client = VpnPolicyClient(dio: dio);

    final payload = await client.update(
      settings,
      vpnTarget: 'Proxy',
      mode: 'exclude_selected',
      apps: const [],
      services: const ['chatgpt'],
      customDomains: const ['example.com'],
      customAppSelectors: const ['special.exe'],
    );

    final request = adapter.requested.single;
    expect(request.method, 'PUT');
    expect(request.uri.path, '/base/client/v1/policy');
    expect(request.headers['Authorization'], 'Bearer device-key');
    expect(request.data, {
      'mode': 'exclude_selected',
      'apps': <String>[],
      'services': ['chatgpt'],
      'custom_domains': ['example.com'],
      'custom_app_selectors': ['special.exe'],
    });

    expect(payload.mode, 'exclude_selected');
    expect(payload.services, ['chatgpt']);
    expect(payload.customDomains, ['example.com']);
    expect(payload.customAppSelectors, ['special.exe']);
    expect(payload.rules.first.rawValue, 'PROCESS-NAME,special.exe,DIRECT');
    expect(payload.rules.last.rawValue, 'MATCH,Proxy');
  });
}
