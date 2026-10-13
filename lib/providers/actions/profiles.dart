part of '../action.dart';

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  void build() {}

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final selectedMap = Map<String, String>.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      ref
          .read(profilesProvider.notifier)
          .put(currentProfile.copyWith(selectedMap: selectedMap));
    }
  }

  Future<void> deleteProfile(int id) async {
    await ref.read(profilesProvider.notifier).del(id);
    await clearEffect(id);
    final currentProfileId = ref.read(currentProfileIdProvider);
    if (currentProfileId == id) {
      final profiles = ref.read(profilesProvider);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        ref.read(currentProfileIdProvider.notifier).value = updateId;
      } else {
        ref.read(currentProfileIdProvider.notifier).value = null;
        unawaited(ref.read(setupActionProvider.notifier).setRunning(false));
      }
    }
  }

  Future<String> validateConfigWithData(String data) async {
    return _core.validateConfigWithData(data);
  }

  Future<Profile> _syncVpnPolicyProfile(
    Profile profile,
    VpnPolicySettings settings,
  ) async {
    final serviceUrl = settings.serviceUrl.trim().isEmpty
        ? defaultVpnPolicyServiceUrl
        : settings.serviceUrl.trim();
    final connection = settings.copyWith(serviceUrl: serviceUrl);
    final bytes = await vpnPolicyClient.fetchBootstrap(connection);
    final bootstrap = parseVpnPolicyProfileBootstrap(bytes);
    if (bootstrap == null) {
      throw StateError('Policy Service returned an invalid bootstrap profile');
    }
    final updated = await profile.saveFile(
      bootstrap.configBytes,
      validate: (path) => _core.validateConfig(path),
    );
    final nextSettings = bootstrap.settings.copyWith(
      serviceUrl: serviceUrl,
      deviceKey: connection.deviceKey,
    );
    ref.read(profilesProvider.notifier).put(updated);
    await vpnPolicySettingsStore.save(profile.id, nextSettings);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref
          .read(setupActionProvider.notifier)
          .applyProfileDebounce(silence: true);
    }
    return updated;
  }

  Future<Profile> addVpnPolicyFromDeviceKey(
    String deviceKey, {
    String serviceUrl = defaultVpnPolicyServiceUrl,
  }) async {
    final key = deviceKey.trim();
    if (key.isEmpty) {
      throw ArgumentError('Device Key is required');
    }
    final connection = VpnPolicySettings(
      serviceUrl: serviceUrl.trim().isEmpty
          ? defaultVpnPolicyServiceUrl
          : serviceUrl.trim(),
      deviceKey: key,
    );
    final bytes = await vpnPolicyClient.fetchBootstrap(connection);
    final bootstrap = parseVpnPolicyProfileBootstrap(bytes);
    if (bootstrap == null) {
      throw StateError('Policy Service returned an invalid bootstrap profile');
    }

    Profile? existing;
    for (final profile in ref.read(profilesProvider)) {
      final settings = await vpnPolicySettingsStore.load(profile.id);
      if (settings.deviceKey.trim() == key) {
        existing = profile;
        break;
      }
      if (existing == null &&
          settings.deviceKey.trim().isNotEmpty &&
          bootstrap.deviceName.isNotEmpty &&
          profile.realLabel == bootstrap.deviceName) {
        existing = profile;
      }
    }

    final base =
        existing ??
        Profile.normal(
          label: bootstrap.deviceName.isEmpty
              ? 'VPN Policy'
              : bootstrap.deviceName,
        );
    final updated = await base.saveFile(
      bootstrap.configBytes,
      validate: (path) => _core.validateConfig(path),
    );
    final nextSettings = bootstrap.settings.copyWith(
      serviceUrl: connection.serviceUrl,
      deviceKey: key,
    );
    ref.read(profilesProvider.notifier).put(updated);
    await vpnPolicySettingsStore.save(updated.id, nextSettings);
    ref.read(currentProfileIdProvider.notifier).value = updated.id;
    ref.read(setupActionProvider.notifier).applyProfileDebounce(silence: true);
    return updated;
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      final vpnSettings = await vpnPolicySettingsStore.load(profile.id);
      if (vpnSettings.deviceKey.trim().isNotEmpty) {
        try {
          await _syncVpnPolicyProfile(profile, vpnSettings);
        } catch (e) {
          commonPrint.log(
            'VPN Policy auto-sync failed for ${profile.realLabel}: '
            '${compactError(e)}',
            logLevel: LogLevel.warning,
          );
        }
        continue;
      }

      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(compactError(e), logLevel: LogLevel.warning);
      }
    }
  }

  void putProfile(Profile profile, {Iterable<int> renameIn = const []}) {
    ref.read(profilesProvider.notifier).put(profile, renameIn: renameIn);
    if (ref.read(currentProfileIdProvider) != null) return;
    ref.read(currentProfileIdProvider.notifier).value = profile.id;
  }

  Future<List<Profile>> providerUsers(Profile profile) async {
    if (!feature.customProviders) {
      return const [];
    }
    final users = await ref
        .read(clashProvidersActionProvider.notifier)
        .profilesReferencing(ProviderKind.proxy, profile.realLabel);
    return [
      for (final user in users)
        if (user.id != profile.id) user,
    ];
  }

  /// [conflicts] would move to their subscription's provider of the new name.
  Future<({List<Profile> renameIn, List<Profile> conflicts})> providerRename(
    Profile previous,
    Profile next,
  ) async {
    final label = ref.read(profilesProvider.notifier).labeled(next).realLabel;
    if (!feature.customProviders || label == previous.realLabel) {
      return (renameIn: const <Profile>[], conflicts: const <Profile>[]);
    }
    final renameIn = await providerUsers(previous);
    final conflicts = await ref
        .read(clashProvidersActionProvider.notifier)
        .profilesDefining(ProviderKind.proxy, label, renameIn);
    return (renameIn: renameIn, conflicts: conflicts);
  }

  Future<void> updateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) continue;
      await updateProfile(profile, showLoading: true);
    }
  }

  Future<void> updateProfile(
    Profile profile, {
    bool showLoading = false,
    Iterable<int> renameIn = const [],
  }) async {
    final operation = showLoading
        ? ref.read(updatingKeysProvider.notifier).start(profile.updatingKey)
        : null;
    try {
      ref.read(profilesProvider.notifier).put(profile, renameIn: renameIn);
      final newProfile = await profile.update(
        validate: (path) => _core.validateConfig(path),
      );
      ref.read(profilesProvider.notifier).put(newProfile);
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(profile.updatingKey, operation);
      }
    }
  }

  Future<void> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    final bytes = await platformFile.readBytes();
    final bootstrap = parseVpnPolicyProfileBootstrap(bytes);
    final configBytes = bootstrap?.configBytes ?? bytes;
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(
          label: platformFile.name,
        ).saveFile(configBytes, validate: (path) => _core.validateConfig(path));
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
      if (bootstrap != null) {
        await vpnPolicySettingsStore.save(profile.id, bootstrap.settings);
      }
    }
  }

  Future<void> addProfileFormURL(String url, {String? label}) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(
          label: label,
          url: url,
        ).update(validate: (path) => _core.validateConfig(path));
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
    }
  }

  void setProfileAndAutoApply(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref.read(setupActionProvider.notifier).applyProfileDebounce();
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    unawaited(addProfileFormURL(url));
  }

  void reorder(List<Profile> profiles) {
    ref.read(profilesProvider.notifier).reorder(profiles);
  }

  Future<void> clearEffect(int profileId) async {
    final profilePath = await appPath.getProfilePath(profileId.toString());
    final profileFile = File(profilePath);
    final isExists = await profileFile.exists();
    if (isExists) {
      await profileFile.safeDelete(recursive: true);
    }
    try {
      final error = await _core.clearEffect(profileId);
      if (error.isNotEmpty) {
        commonPrint.log(error, logLevel: LogLevel.warning);
      }
    } catch (error) {
      commonPrint.log(
        'clearEffect($profileId) failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }
}
