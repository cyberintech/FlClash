import 'package:fl_clash/common/search.dart';
import 'package:fl_clash/common/vpn_route_name.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all direct routes have distinct five-character card names', () {
    final labels = <String>{};
    for (final (node, city) in [('LON', 'LN'), ('LA', 'LA'), ('DE', 'DE')]) {
      for (final (protocol, code) in [('Vision', 'V'), ('Salamander', 'S')]) {
        for (final family in [4, 6]) {
          final name = '$node-$protocol-IPv$family';
          final label = vpnRouteDisplayName(name);
          expect(label, '$city-$code$family');
          expect(label.length, 5);
          expect(labels.add(label), isTrue);
        }
      }
    }
    expect(labels, hasLength(12));
  });

  test('groups, custom names and legacy relay paths retain their identity', () {
    for (final name in [
      'VPN',
      'VPN-AUTO',
      'DIRECT',
      'LA-V4',
      'LA-Vision-IPv4 custom',
      'EXP-LA-Vision-IPv4',
      '',
    ]) {
      expect(vpnRouteDisplayName(name), name);
    }
  });

  test(
    'short and original names search the same proxy without renaming it',
    () {
      const proxy = Proxy(name: 'LA-Vision-IPv4', type: 'Vless');
      expect(proxy.displayName, 'LA-V4');
      expect(SearchQuery('la-v4').matches(proxy.searchFields), isTrue);
      expect(SearchQuery('LA-Vision-IPv4').matches(proxy.searchFields), isTrue);
      expect(SearchQuery('Vless').matches(proxy.searchFields), isTrue);
      expect(SearchQuery('LA-V6').matches(proxy.searchFields), isFalse);
      expect(proxy.name, 'LA-Vision-IPv4');
      expect(proxy.toJson()['name'], 'LA-Vision-IPv4');
    },
  );
}
