import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';
import '../helpers/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('profile_save_test');
    await useAppPaths(tempDir);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Profile.saveFile', () {
    test(
      'managed refresh keeps local exceptions and installs provider metadata',
      () async {
        await mockPreferences({});
        final profile = Profile.normal(label: 'managed');
        await vpnPolicySettingsStore.save(
          profile.id,
          const VpnPolicySettings(
            serviceUrl: 'https://old.example',
            deviceKey: 'old-key',
            localDomains: ['local.example'],
            localRules: ['DOMAIN-SUFFIX,local.example,DIRECT'],
          ),
        );
        final bytes = Uint8List.fromList(
          utf8.encode('''
x-vpn-policy:
  service-url: https://new.example
  device-key: new-key
  shared-rules: true
  vpn-target: VPN
rules: ["MATCH,DIRECT"]
'''),
        );
        await profile.saveFile(
          bytes,
          validate: (path, _) async {
            expect(
              await File(path).readAsString(),
              isNot(contains('x-vpn-policy')),
            );
            return null;
          },
        );
        final settings = await vpnPolicySettingsStore.load(profile.id);
        expect(settings.deviceKey, 'new-key');
        expect(settings.vpnTarget, 'VPN');
        expect(settings.sharedRules, isTrue);
        expect(settings.localDomains, ['local.example']);
        expect(settings.localRules, ['DOMAIN-SUFFIX,local.example,DIRECT']);
      },
    );

    // EditProfileView relies on this throwing rather than silently
    // succeeding, so a caller-level try/catch can surface the failure.
    test('rejects an invalid config without touching the saved file', () async {
      final profile = Profile.normal(label: 'p');
      final bytes = Uint8List.fromList(utf8.encode('bad: ['));

      await expectLater(
        profile.saveFile(bytes, validate: (_, _) async => 'invalid config'),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            'invalid config',
          ),
        ),
      );

      final savedFile = await profile.file;
      expect(await savedFile.length(), 0);
    });

    test('copies validated bytes and stamps the update time', () async {
      final profile = Profile.normal(label: 'p');
      final bytes = Uint8List.fromList(utf8.encode('proxies: []'));

      final saved = await profile.saveFile(
        bytes,
        validate: (_, _) async => null,
      );

      expect(saved.lastUpdateDate, isNotNull);
      final savedFile = await profile.file;
      expect(await savedFile.readAsString(), 'proxies: []');
    });

    test('validates with the profile age key', () async {
      final profile = Profile.normal(
        label: 'p',
      ).copyWith(ageSecretKey: 'AGE-SECRET-KEY-1A');
      final bytes = Uint8List.fromList(utf8.encode('proxies: []'));
      String? ageSecretKey;

      await profile.saveFile(
        bytes,
        validate: (_, key) async {
          ageSecretKey = key;
          return null;
        },
      );

      expect(ageSecretKey, 'AGE-SECRET-KEY-1A');
    });
  });
}
