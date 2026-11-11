import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/features/vpn_policy/provider_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late Map<String, String> bodies;
  late int requests;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vpn-provider-cache-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = 0;
    bodies = {
      '/paths': jsonEncode({
        'proxies': [
          for (var index = 0; index < 72; index++)
            {'name': 'route-$index', 'type': 'socks5', 'server': '127.0.0.1', 'port': 9},
        ],
      }),
      '/direct': 'payload: []',
      '/vpn': 'payload: [DOMAIN-SUFFIX,example.invalid]',
    };
    server.listen((request) async {
      requests++;
      final body = bodies[request.uri.path];
      request.response.statusCode = body == null ? 404 : 200;
      if (body != null) request.response.write(body);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  String config() {
    Map<String, dynamic> provider(String path, String cache) => {
      'type': 'http',
      'url': 'http://127.0.0.1:${server.port}$path',
      'path': '${directory.path}/$cache.yaml',
    };
    return jsonEncode({
      'proxy-providers': {'VPN-Paths': provider('/paths', 'paths')},
      'rule-providers': {
        'VPN-Shared-Direct': provider('/direct', 'direct'),
        'VPN-Shared-VPN': provider('/vpn', 'vpn'),
      },
    });
  }

  test('first import seeds72 actual routes and both shared lists', () async {
    await ensureManagedProviderCache(config());
    final routes = jsonDecode(await File('${directory.path}/paths.yaml').readAsString());
    expect(routes['proxies'], hasLength(72));
    expect(File('${directory.path}/direct.yaml').existsSync(), isTrue);
    expect(File('${directory.path}/vpn.yaml').existsSync(), isTrue);
    expect(requests, 3);
    expect(directory.listSync().where((file) => file.path.contains('.download-')), isEmpty);
  });

  test('healthy cache starts offline without redownloading', () async {
    await ensureManagedProviderCache(config());
    requests = 0;
    bodies.clear();
    await ensureManagedProviderCache(config());
    expect(requests, 0);
  });

  test('invalid route cache is repaired before applying core config', () async {
    await File('${directory.path}/paths.yaml').writeAsString('proxies: []');
    await ensureManagedProviderCache(config());
    expect(validManagedProvider(
      await File('${directory.path}/paths.yaml').readAsString(),
      proxies: true,
    ), isTrue);
  });

  test('empty subscription fails instead of accepting Compatible placeholder', () async {
    bodies['/paths'] = 'proxies: []';
    await expectLater(ensureManagedProviderCache(config()), throwsA(isA<MessageException>()));
    expect(File('${directory.path}/paths.yaml').existsSync(), isFalse);
  });

  test('HTTP failure is surfaced and no broken cache replaces routes', () async {
    bodies.remove('/paths');
    await expectLater(ensureManagedProviderCache(config()), throwsA(isA<MessageException>()));
    expect(File('${directory.path}/paths.yaml').existsSync(), isFalse);
    expect(directory.listSync().where((file) => file.path.contains('.download-')), isEmpty);
  });

  test('ordinary profiles are not forced into managed provider behavior', () async {
    await ensureManagedProviderCache(jsonEncode({
      'proxy-providers': {'ordinary': {'type': 'http', 'url': 'https://example.invalid'}},
    }));
    expect(requests, 0);
    expect(directory.listSync(), isEmpty);
  });
}
