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

  test('shares service URL but keeps Device Key per profile', () async {
    const settings = VpnPolicySettings(
      serviceUrl: 'https://policy.example.com',
      deviceKey: 'device-key-7',
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

    final otherProfile = await vpnPolicySettingsStore.load(8);
    expect(otherProfile.serviceUrl, settings.serviceUrl);
    expect(otherProfile.deviceKey, isEmpty);
    expect(otherProfile.vpnTarget, isEmpty);
  });

  test('migrates legacy profile URL without leaking Device Key', () async {
    await store.setString(
      'vpn_policy_settings_7',
      '{"serviceUrl":"https://legacy.example.com","deviceKey":"legacy-key","vpnTarget":"Proxy"}',
    );

    final migrated = await vpnPolicySettingsStore.load(7);
    final otherProfile = await vpnPolicySettingsStore.load(8);

    expect(migrated.serviceUrl, 'https://legacy.example.com');
    expect(migrated.deviceKey, 'legacy-key');
    expect(otherProfile.serviceUrl, 'https://legacy.example.com');
    expect(otherProfile.deviceKey, isEmpty);
  });

  test('profile Device Key wins over stale shared legacy key', () async {
    await store.setString(
      'vpn_policy_connection_v1',
      '{"serviceUrl":"https://policy.example.com","deviceKey":"stale-key"}',
    );
    await store.setString(
      'vpn_policy_settings_7',
      '{"serviceUrl":"https://policy.example.com","deviceKey":"right-key","vpnTarget":"Proxy"}',
    );

    final restored = await vpnPolicySettingsStore.load(7);

    expect(restored.serviceUrl, 'https://policy.example.com');
    expect(restored.deviceKey, 'right-key');
  });

  test('corrupt settings fall back to defaults', () async {
    await store.setString('vpn_policy_settings_7', 'not-json');

    final restored = await vpnPolicySettingsStore.load(7);

    expect(restored.serviceUrl, isEmpty);
    expect(restored.deviceKey, isEmpty);
  });
}