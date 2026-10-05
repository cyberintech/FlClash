import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/vpn_policy/installed_apps.dart';
import 'package:fl_clash/features/vpn_policy/policy_catalog.dart';
import 'package:fl_clash/features/vpn_policy/policy_client.dart';
import 'package:fl_clash/features/vpn_policy/policy_payload.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VpnPolicyView extends ConsumerStatefulWidget {
  final int profileId;

  const VpnPolicyView(this.profileId, {super.key});

  @override
  ConsumerState<VpnPolicyView> createState() => _VpnPolicyViewState();
}

class _VpnPolicyViewState extends ConsumerState<VpnPolicyView> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _appSearchController = TextEditingController();
  final _domainController = TextEditingController();

  VpnPolicySettings _settings = const VpnPolicySettings();
  VpnPolicyCatalog? _catalog;
  VpnPolicyPayload? _payload;

  final _selectedApps = <String>{};
  final _selectedServices = <String>{};
  final _selectedCustomApps = <String>{};
  final _customDomains = <String>[];

  List<Package> _androidPackages = const [];
  List<VpnPolicyInstalledApp> _windowsApps = const [];

  String? _selectedTarget;
  String _mode = 'only_selected';
  String? _status;
  bool _loading = true;
  bool _busy = false;
  bool _appsLoading = false;
  bool _installedAppsPermissionGranted = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _appSearchController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await vpnPolicySettingsStore.load(widget.profileId);
    if (!mounted) {
      return;
    }
    _urlController.text = settings.serviceUrl;
    _keyController.text = settings.deviceKey;
    setState(() {
      _settings = settings;
      _selectedTarget = settings.vpnTarget;
      _loading = false;
    });
    await _loadInstalledApps();
    if (settings.serviceUrl.isNotEmpty && settings.deviceKey.isNotEmpty) {
      await _refreshFromServer(applyRules: false);
    }
  }

  Future<void> _loadInstalledApps() async {
    if (_appsLoading) {
      return;
    }
    setState(() {
      _appsLoading = true;
    });
    try {
      if (Platform.isAndroid) {
        final action = ref.read(systemActionProvider.notifier);
        final packages = await action.getPackages();
        final granted =
            packages.isNotEmpty ||
            await action.isInstalledAppsPermissionGranted();
        if (!mounted) {
          return;
        }
        setState(() {
          _androidPackages =
              packages.where((item) => !item.system && item.internet).toList()
                ..sort(
                  (a, b) =>
                      a.label.toLowerCase().compareTo(b.label.toLowerCase()),
                );
          _installedAppsPermissionGranted = granted;
        });
      } else if (Platform.isWindows) {
        final apps = await loadWindowsInstalledApps();
        if (!mounted) {
          return;
        }
        setState(() {
          _windowsApps = apps;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = compactError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _appsLoading = false;
        });
      }
    }
  }

  Future<void> _grantInstalledAppsPermission() async {
    final action = ref.read(systemActionProvider.notifier);
    final granted = await action.requestInstalledAppsPermission();
    if (!mounted) {
      return;
    }
    if (granted) {
      await _loadInstalledApps();
    } else {
      setState(() {
        _installedAppsPermissionGranted = false;
      });
    }
  }

  String? _effectiveTarget(List<String> targets) {
    final selected = _selectedTarget;
    if (selected != null && targets.contains(selected)) {
      return selected;
    }
    return targets.isEmpty ? null : targets.first;
  }

  VpnPolicySettings? _connectionSettings(List<String> targets) {
    final appLocalizations = context.appLocalizations;
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    final target = _effectiveTarget(targets);

    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() {
        _status = appLocalizations.urlTip(appLocalizations.url);
      });
      return null;
    }
    if (key.isEmpty) {
      setState(() {
        _status = appLocalizations.emptyTip(appLocalizations.key);
      });
      return null;
    }
    if (target == null) {
      setState(() {
        _status = appLocalizations.emptyTip(appLocalizations.ruleTarget);
      });
      return null;
    }
    return _settings.copyWith(
      serviceUrl: url,
      deviceKey: key,
      vpnTarget: target,
    );
  }

  List<String> _ruleTargets() =>
      ref
          .read(customOverwriteDateProvider(widget.profileId))
          .ruleTargets
          .where((target) => !RuleTarget.baseTargetNames.contains(target))
          .toList()
        ..sort();

  Future<void> _refreshFromServer({
    bool applyRules = true,
    List<String>? targets,
  }) async {
    final settings = _connectionSettings(targets ?? _ruleTargets());
    if (settings == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await vpnPolicySettingsStore.save(widget.profileId, settings);
      final results = await Future.wait([
        vpnPolicyClient.fetchCatalog(settings),
        vpnPolicyClient.fetch(settings, vpnTarget: settings.vpnTarget),
      ]);
      final catalog = results[0] as VpnPolicyCatalog;
      final payload = results[1] as VpnPolicyPayload;
      if (applyRules) {
        await ref
            .read(profileCustomRulesProvider(widget.profileId).notifier)
            .replaceAll(payload.rules);
      }
      await _applyRemoteState(settings, catalog, payload);
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = compactError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _applyRemoteState(
    VpnPolicySettings settings,
    VpnPolicyCatalog catalog,
    VpnPolicyPayload payload,
  ) async {
    final next = settings.copyWith(
      lastRevision: payload.revision,
      lastPolicyName: payload.policyName,
    );
    await vpnPolicySettingsStore.save(widget.profileId, next);
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = next;
      _catalog = catalog;
      _payload = payload;
      _selectedTarget = settings.vpnTarget;
      _mode = payload.mode;
      _selectedApps
        ..clear()
        ..addAll(payload.apps);
      _selectedServices
        ..clear()
        ..addAll(payload.services);
      _selectedCustomApps
        ..clear()
        ..addAll(payload.customAppSelectors);
      _customDomains
        ..clear()
        ..addAll(payload.customDomains);
      _status = payload.policyName.isEmpty
          ? null
          : '${payload.policyName} · ${payload.rules.length} rules';
    });
  }

  Future<void> _saveAndApply(List<String> targets) async {
    final settings = _connectionSettings(targets);
    if (settings == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await vpnPolicySettingsStore.save(widget.profileId, settings);
      final payload = await vpnPolicyClient.update(
        settings,
        vpnTarget: settings.vpnTarget,
        mode: _mode,
        apps: _selectedApps.toList()..sort(),
        services: _selectedServices.toList()..sort(),
        customDomains: List<String>.from(_customDomains),
        customAppSelectors: _selectedCustomApps.toList()..sort(),
      );
      await ref
          .read(profileCustomRulesProvider(widget.profileId).notifier)
          .replaceAll(payload.rules);
      final catalog = _catalog ?? await vpnPolicyClient.fetchCatalog(settings);
      await _applyRemoteState(settings, catalog, payload);
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = compactError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _toggleInstalledApp(String selector, bool selected) {
    final semantic = _catalog?.selectorToAppKey[selector];
    setState(() {
      if (semantic != null) {
        selected ? _selectedApps.add(semantic) : _selectedApps.remove(semantic);
      } else {
        selected
            ? _selectedCustomApps.add(selector)
            : _selectedCustomApps.remove(selector);
      }
    });
  }

  bool _isInstalledAppSelected(String selector) {
    final semantic = _catalog?.selectorToAppKey[selector];
    return semantic != null
        ? _selectedApps.contains(semantic)
        : _selectedCustomApps.contains(selector);
  }

  String _normalizeDomain(String value) {
    var domain = value.trim().toLowerCase();
    domain = domain.replaceFirst(RegExp(r'^https?://'), '');
    domain = domain.split('/').first;
    domain = domain.replaceFirst(RegExp(r'^\*\.'), '');
    return domain;
  }

  void _addDomain() {
    final domain = _normalizeDomain(_domainController.text);
    if (domain.isEmpty) {
      return;
    }
    setState(() {
      if (!_customDomains.contains(domain)) {
        _customDomains.add(domain);
      }
      _domainController.clear();
    });
  }

  List<Widget> _connectionSection(BuildContext context, List<String> targets) {
    final appLocalizations = context.appLocalizations;
    final selectedTarget = _effectiveTarget(targets);
    return [
      ExpansionTile(
        title: const Text('Policy Service'),
        subtitle: Text(
          _settings.lastPolicyName.isEmpty ? '—' : _settings.lastPolicyName,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextFormField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: appLocalizations.url,
              hintText: 'https://policy.example.com',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _keyController,
            obscureText: true,
            decoration: InputDecoration(labelText: appLocalizations.key),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(labelText: appLocalizations.ruleTarget),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedTarget,
                hint: Text(appLocalizations.selectSplitStrategy),
                items: [
                  for (final target in targets)
                    DropdownMenuItem(value: target, child: Text(target)),
                ],
                onChanged: targets.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          _selectedTarget = value;
                        });
                      },
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () => _refreshFromServer(targets: targets),
            child: Text(appLocalizations.sync),
          ),
        ],
      ),
    ];
  }

  Widget _modeSection() {
    final l = context.appLocalizations;
    final modes = <(String, String)>[
      ('only_selected', l.whitelistMode),
      ('exclude_selected', l.blacklistMode),
      ('all_vpn', l.global),
    ];
    return _Section(
      title: l.mode,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in modes)
            ChoiceChip(
              label: Text(entry.$2),
              selected: _mode == entry.$1,
              onSelected: (_) {
                setState(() {
                  _mode = entry.$1;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _appsSection() {
    final query = _appSearchController.text.trim().toLowerCase();
    final android = _androidPackages
        .where(
          (item) =>
              query.isEmpty ||
              item.label.toLowerCase().contains(query) ||
              item.packageName.toLowerCase().contains(query),
        )
        .toList();
    final windows = _windowsApps
        .where(
          (item) =>
              query.isEmpty ||
              item.label.toLowerCase().contains(query) ||
              item.selector.toLowerCase().contains(query),
        )
        .toList();

    final hasNativeApps = Platform.isAndroid || Platform.isWindows;
    final listEmpty = Platform.isAndroid ? android.isEmpty : windows.isEmpty;

    return _Section(
      title: context.appLocalizations.app,
      trailing: _appsLoading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              onPressed: _loadInstalledApps,
              icon: const Icon(Icons.refresh),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _appSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.appLocalizations.search,
            ),
          ),
          if (Platform.isAndroid && !_installedAppsPermissionGranted) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _grantInstalledAppsPermission,
              child: Text(context.appLocalizations.confirm),
            ),
          ],
          if (hasNativeApps && listEmpty && !_appsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No installed apps found'),
            ),
          if (Platform.isAndroid)
            for (final item in android)
              CheckboxListTile(
                value: _isInstalledAppSelected(item.packageName),
                onChanged: (value) {
                  _toggleInstalledApp(item.packageName, value ?? false);
                },
                secondary: PackageIcon(
                  packageName: item.packageName,
                  size: 36,
                  placeholder: const Icon(Icons.apps),
                ),
                title: Text(item.label),
                subtitle: Text(item.packageName),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
          if (Platform.isWindows)
            for (final item in windows)
              CheckboxListTile(
                value: _isInstalledAppSelected(item.selector),
                onChanged: (value) {
                  _toggleInstalledApp(item.selector, value ?? false);
                },
                secondary: const Icon(Icons.desktop_windows),
                title: Text(item.label),
                subtitle: Text(item.selector),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
          if (!hasNativeApps && _catalog != null)
            for (final item in _catalog!.apps)
              CheckboxListTile(
                value: _selectedApps.contains(item.key),
                onChanged: (value) {
                  setState(() {
                    value == true
                        ? _selectedApps.add(item.key)
                        : _selectedApps.remove(item.key);
                  });
                },
                title: Text(item.title),
                subtitle: Text(item.selectors.join(', ')),
              ),
        ],
      ),
    );
  }

  Widget _servicesSection() {
    final services = _catalog?.services ?? const <VpnPolicyCatalogService>[];
    return _Section(
      title: 'Services',
      child: services.isEmpty
          ? const Text('Connect to Policy Service to load services')
          : Column(
              children: [
                for (final service in services)
                  CheckboxListTile(
                    value: _selectedServices.contains(service.key),
                    onChanged: (value) {
                      setState(() {
                        value == true
                            ? _selectedServices.add(service.key)
                            : _selectedServices.remove(service.key);
                      });
                    },
                    title: Text(service.title),
                    subtitle: service.domains.isEmpty
                        ? null
                        : Text(service.domains.join(', ')),
                  ),
              ],
            ),
    );
  }

  Widget _domainsSection() {
    return _Section(
      title: context.appLocalizations.domain,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domainController,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _addDomain(),
                  decoration: const InputDecoration(
                    hintText: 'example.com',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _addDomain,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_customDomains.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final domain in _customDomains)
                    InputChip(
                      label: Text(domain),
                      onDeleted: () {
                        setState(() {
                          _customDomains.remove(domain);
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overwrite = ref.watch(customOverwriteDateProvider(widget.profileId));
    final targets =
        overwrite.ruleTargets
            .where((target) => !RuleTarget.baseTargetNames.contains(target))
            .toList()
          ..sort();

    return BaseScaffold(
      title: 'VPN Policy',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(
                16,
              ).copyWith(top: context.contentTopPadding),
              children: [
                ..._connectionSection(context, targets),
                _modeSection(),
                _appsSection(),
                _servicesSection(),
                _domainsSection(),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || _catalog == null
                      ? null
                      : () => _saveAndApply(targets),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.appLocalizations.save),
                ),
                if (_status?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  SelectableText(_status!),
                ],
                if (_payload != null && _payload!.revision.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_payload!.revision, style: context.textTheme.bodySmall),
                ],
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: context.textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}
