import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/vpn_policy/policy_client.dart';
import 'package:fl_clash/features/vpn_policy/policy_settings.dart';
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

  VpnPolicySettings _settings = const VpnPolicySettings();
  String? _selectedTarget;
  String? _status;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
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
  }

  String? _effectiveTarget(List<String> targets) {
    final selected = _selectedTarget;
    if (selected != null && targets.contains(selected)) {
      return selected;
    }
    return targets.isEmpty ? null : targets.first;
  }

  Future<void> _sync(List<String> targets) async {
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
      return;
    }
    if (key.isEmpty) {
      setState(() {
        _status = appLocalizations.emptyTip(appLocalizations.key);
      });
      return;
    }
    if (target == null) {
      setState(() {
        _status = appLocalizations.emptyTip(appLocalizations.ruleTarget);
      });
      return;
    }

    final settings = _settings.copyWith(
      serviceUrl: url,
      deviceKey: key,
      vpnTarget: target,
    );

    setState(() {
      _syncing = true;
      _status = null;
    });

    try {
      await vpnPolicySettingsStore.save(widget.profileId, settings);
      final payload = await vpnPolicyClient.fetch(settings, vpnTarget: target);
      await ref
          .read(profileCustomRulesProvider(widget.profileId).notifier)
          .replaceAll(payload.rules);

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
        _selectedTarget = target;
        _status = '${payload.policyName} · ${payload.rules.length} rules';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = compactError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final overwrite = ref.watch(customOverwriteDateProvider(widget.profileId));
    final targets =
        overwrite.ruleTargets
            .where((target) => !RuleTarget.baseTargetNames.contains(target))
            .toList()
          ..sort();
    final selectedTarget = _effectiveTarget(targets);

    return BaseScaffold(
      title: 'VPN Policy',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(
                16,
              ).copyWith(top: context.contentTopPadding),
              children: [
                TextFormField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: appLocalizations.url,
                    hintText: 'https://policy.example.com',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _keyController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: appLocalizations.key),
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: appLocalizations.ruleTarget,
                  ),
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
                if (targets.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    appLocalizations.emptyTip(appLocalizations.proxyGroup),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: _syncing ? null : () => _sync(targets),
                  child: _syncing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(appLocalizations.sync),
                ),
                if (_status?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  SelectableText(_status!),
                ],
                if (_settings.lastPolicyName.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _settings.lastPolicyName,
                    style: context.textTheme.titleMedium,
                  ),
                  if (_settings.lastRevision.isNotEmpty)
                    Text(
                      _settings.lastRevision,
                      style: context.textTheme.bodySmall,
                    ),
                ],
              ],
            ),
    );
  }
}
