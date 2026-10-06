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
import 'package:flutter/services.dart';
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
  late final ErrorWidgetBuilder _previousErrorWidgetBuilder;

  @override
  void initState() {
    super.initState();
    _previousErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = _buildDiagnosticError;
    _load();
  }

  Widget _buildDiagnosticError(FlutterErrorDetails details) {
    final stack = details.stack?.toString() ?? '';
    final message =
        'VPN Policy runtime error\n\n'
        '${details.exceptionAsString()}\n\n'
        '$stack';

    return ColoredBox(
      color: const Color(0xFF101826),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF26364D),
                    border: Border.all(
                      color: const Color(0xFF8AA4C8),
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'COPY ERROR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ErrorWidget.builder = _previousErrorWidgetBuilder;
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

  Future<void> _applyRulesToRuntimeIfRunning() async {
    final isCurrent = ref.read(currentProfileIdProvider) == widget.profileId;
    if (!isCurrent || !ref.read(isStartProvider)) {
      return;
    }
    final restarted = await ref.read(coreActionProvider.notifier).restartCore();
    if (!restarted) {
      throw StateError('Rules were saved, but the core restart did not complete');
    }
  }

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
      _status = 'Syncing...';
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
      if (applyRules) {
        await _applyRulesToRuntimeIfRunning();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Sync failed: ${compactError(error)}';
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
      final policyLabel = payload.policyName.isEmpty
          ? 'Policy'
          : payload.policyName;
      _status =
          'Synced: $policyLabel · ${payload.rules.length} rules'
          '${payload.revision.isEmpty ? '' : ' · ${payload.revision}'}';
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
      await _applyRulesToRuntimeIfRunning();
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
    final status = _status;
    final isError = status?.startsWith('Sync failed:') == true;
    final isSuccess = status?.startsWith('Synced:') == true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final statusBackground = isError
        ? (dark ? const Color(0xFF4A1D24) : const Color(0xFFFFECEE))
        : isSuccess
        ? (dark ? const Color(0xFF153B2A) : const Color(0xFFE9F8EF))
        : (dark ? const Color(0xFF26364D) : const Color(0xFFEAF2FC));
    final statusBorder = isError
        ? const Color(0xFFF87171)
        : isSuccess
        ? const Color(0xFF4ADE80)
        : const Color(0xFF60A5FA);
    final statusTextColor = dark
        ? const Color(0xFFFFFFFF)
        : isError
        ? const Color(0xFF7F1D1D)
        : isSuccess
        ? const Color(0xFF14532D)
        : const Color(0xFF1E3A5F);
    return [
      _Section(
        title: 'Policy Service',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_settings.lastPolicyName.isNotEmpty) ...[
              Text(
                _settings.lastPolicyName,
                style: context.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
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
              decoration: InputDecoration(
                labelText: appLocalizations.ruleTarget,
              ),
              child: targets.isEmpty
                  ? Text(appLocalizations.selectSplitStrategy)
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final target in targets)
                          ChoiceChip(
                            label: Text(target),
                            selected: selectedTarget == target,
                            onSelected: (_) {
                              setState(() {
                                _selectedTarget = target;
                              });
                            },
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _refreshFromServer(targets: targets),
              child: _busy
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Syncing...'),
                      ],
                    )
                  : Text(appLocalizations.sync),
            ),
            if (status?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  border: Border.all(color: statusBorder, width: 1.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isError
                          ? Icons.error_outline
                          : isSuccess
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 21,
                      color: statusTextColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        status!,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: statusTextColor,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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

    final body = _loading
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
              if (_payload != null && _payload!.revision.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_payload!.revision, style: context.textTheme.bodySmall),
              ],
            ],
          );

    return BaseScaffold(
      title: 'VPN Policy',
      body: Localizations.override(
        context: context,
        locale: const Locale('en'),
        delegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: body,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark
        ? const Color(0xFF1B2432)
        : const Color(0xFFF3F6FA);
    final borderColor = dark
        ? const Color(0xFF66758B)
        : const Color(0xFFA7B3C4);
    final titleColor = dark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF172033);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
