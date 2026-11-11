import 'package:fl_clash/common/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same custom build is current and later policy builds upgrade', () {
    expect(compareVersions('0.9.3+2026111101', '0.9.3+2026111101'), 0);
    expect(
      compareVersions('0.9.3+2026111102', '0.9.3+2026111101'),
      greaterThan(0),
    );
    expect(compareVersions('0.9.3', '0.9.3+2026111101'), lessThan(0));
  });

  test('verified update packages resolve only to the policy release channel', () {
    final name = releaseAssetName('v0.9.3+2026111101', 'android-arm64-v8a.apk');
    final uri = releaseAssetUri('v0.9.3+2026111101', name);
    expect(uri.host, 'github.com');
    expect(
      uri.path,
      '/cyberintech/FlClash/releases/download/v0.9.3+2026111101/FlClash-0.9.3+2026111101-android-arm64-v8a.apk',
    );
  });
}
