import 'package:fl_clash/features/vpn_policy/policy_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late SharedPreferences store;

  setUp(() async {
    store = await SharedPreferences.getInstance();
    await store.clear();
  });

  test('defaults to empty settings', () async {
    final settings = await vpnPolicySettingsStore.load(7);

    expect(settings.serviceUrl, isEmpty);
    expect(settings.deviceKey, isEmpty);
    expect(settings.vpnTarget, isEmpty);
  });

  test('round-trips profile-scoped policy sync settings', () async {
    const settings = VpnPolicySettings(
      serviceUrl: 'https://policy.example.com',
      deviceKey: 'device-key',
      vpnTarget: 'Proxy',
      lastRevision: 'rev-1',
      lastPolicyName: 'Selected',
    );

    await vpnPolicySettingsStore.save(7, settings);
    final restored = await vpnPolicySettingsStore.load(7);

    expect(restored.serviceUrl, settings.serviceUrl);
    expect(restored.deviceKey, settings.deviceKey);
    expect(restored.vpnTarget, settings.vpnTarget);
    expect(restored.lastRevision, settings.lastRevision);
    expect(restored.lastPolicyName, settings.lastPolicyName);
    expect((await vpnPolicySettingsStore.load(8)).serviceUrl, isEmpty);
  });

  test('corrupt settings fall back to defaults', () async {
    await store.setString('vpn_policy_settings_7', 'not-json');

    final restored = await vpnPolicySettingsStore.load(7);

    expect(restored.serviceUrl, isEmpty);
    expect(restored.deviceKey, isEmpty);
  });
}
