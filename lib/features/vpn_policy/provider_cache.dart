import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/exception.dart';
import 'package:yaml/yaml.dart';

bool validManagedProvider(String contents, {required bool proxies}) {
  try {
    final value = loadYaml(contents);
    if (value is! Map) return false;
    final entries = value[proxies ? 'proxies' : 'payload'];
    if (entries is! List) return false;
    if (!proxies) return entries.every((entry) => entry is String);
    return entries.isNotEmpty &&
        entries.every(
          (entry) =>
              entry is Map &&
              entry['name'] is String &&
              entry['type'] is String,
        );
  } on YamlException {
    return false;
  }
}

Future<void> ensureManagedProviderCache(
  String yaml, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final config = loadYaml(yaml);
  if (config is! Map) return;
  final rules = config['rule-providers'];
  if (rules is! Map ||
      !rules.containsKey('VPN-Shared-Direct') ||
      !rules.containsKey('VPN-Shared-VPN')) {
    return;
  }
  final client = HttpClient()..connectionTimeout = timeout;
  client.findProxy = (_) => 'DIRECT';
  try {
    final downloads = <Future<void>>[];
    for (final section in ['proxy-providers', 'rule-providers']) {
      final providers = config[section];
      if (providers is! Map) continue;
      for (final entry in providers.entries) {
        final provider = entry.value;
        if (provider is! Map || provider['type'] != 'http') continue;
        downloads.add(
          _ensureProvider(
            client,
            entry.key.toString(),
            provider,
            proxies: section == 'proxy-providers',
            timeout: timeout,
          ),
        );
      }
    }
    await Future.wait(downloads);
  } finally {
    client.close(force: true);
  }
}

Future<void> _ensureProvider(
  HttpClient client,
  String name,
  Map provider, {
  required bool proxies,
  required Duration timeout,
}) async {
  final path = provider['path'];
  if (path is! String || path.isEmpty) {
    throw MessageException('VPN Policy: missing cache path for $name');
  }
  final file = File(path);
  if (await file.exists() &&
      validManagedProvider(await file.readAsString(), proxies: proxies)) {
    return;
  }
  final uri = Uri.tryParse(provider['url']?.toString() ?? '');
  if (uri == null ||
      !(uri.scheme == 'https' ||
          (uri.scheme == 'http' &&
              ['127.0.0.1', '::1', 'localhost'].contains(uri.host)))) {
    throw MessageException('VPN Policy: invalid provider address for $name');
  }
  File? pending;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'FlClash-VPN-Policy/0.9.3',
    );
    if (provider['headers'] case final Map headers) {
      for (final entry in headers.entries) {
        final values = entry.value;
        if (values is List) {
          for (final value in values) {
            request.headers.add(entry.key.toString(), value.toString());
          }
        } else {
          request.headers.set(entry.key.toString(), values.toString());
        }
      }
    }
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final buffer = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      if (buffer.length + chunk.length > 8 * 1024 * 1024) {
        throw const FormatException('provider exceeds cache limit');
      }
      buffer.addAll(chunk);
    }
    final text = utf8.decode(buffer);
    if (!validManagedProvider(text, proxies: proxies)) {
      throw const FormatException('provider has no valid entries');
    }
    await file.parent.create(recursive: true);
    pending = File('$path.download-${DateTime.now().microsecondsSinceEpoch}');
    await pending.writeAsString(text, flush: true);
    await pending.rename(path);
  } catch (_) {
    throw MessageException(
      'VPN Policy: $name could not be downloaded; check the subscription connection',
    );
  } finally {
    if (pending != null && await pending.exists()) {
      await pending.delete();
    }
  }
}
