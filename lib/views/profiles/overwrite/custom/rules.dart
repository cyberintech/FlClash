import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/overwrite/overwrite.dart';
import 'package:fl_clash/features/vpn_policy/installed_apps.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/models/state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CustomRulesView extends ConsumerStatefulWidget {
  final int profileId;

  const CustomRulesView(this.profileId, {super.key});

  @override
  ConsumerState createState() => _CustomRulesViewState();
}

class _CustomRulesViewState extends ConsumerState<CustomRulesView> {
  int get _profileId => widget.profileId;

  String _normalizeQuickDomain(String value) {
    var domain = value.trim().toLowerCase();
    domain = domain.replaceFirst(RegExp(r'^https?://'), '');
    domain = domain.split('/').first;
    domain = domain.replaceFirst(RegExp(r'^\\*\\.'), '');
    return domain;
  }

  List<String> _quickTargets() {
    final targets = ref
        .read(customOverwriteDateProvider(_profileId))
        .ruleTargets
        .where((target) => !RuleTarget.baseTargetNames.contains(target))
        .toList()
      ..sort();
    return [RuleTarget.DIRECT.value, ...targets];
  }

  String _defaultQuickTarget(List<String> targets) {
    for (final preferred in const ['NUE-VLESS', 'NUE-VLESS-REALITY']) {
      if (targets.contains(preferred)) {
        return preferred;
      }
    }
    return targets.length > 1 ? targets[1] : RuleTarget.DIRECT.value;
  }

  Future<void> _handleQuickAdd(RuleAction action) async {
    final targets = _quickTargets();
    var target = _defaultQuickTarget(targets);
    final controller = TextEditingController();
    List<VpnPolicyInstalledApp> apps = const [];
    if (action == RuleAction.PROCESS_NAME && Platform.isWindows) {
      try {
        apps = await loadWindowsInstalledApps();
      } catch (_) {
        apps = const [];
      }
    }
    if (!mounted) {
      controller.dispose();
      return;
    }

    final result = await showDialog<Rule>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final raw = controller.text.trim();
            final content = action == RuleAction.DOMAIN_SUFFIX
                ? _normalizeQuickDomain(raw)
                : raw;
            final canSave = content.isNotEmpty && target.isNotEmpty;
            return AlertDialog(
              title: Text(
                action == RuleAction.DOMAIN_SUFFIX
                    ? 'Quick site rule'
                    : 'Quick app rule',
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (action == RuleAction.PROCESS_NAME && apps.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Installed app',
                        ),
                        items: [
                          for (final app in apps)
                            DropdownMenuItem(
                              value: app.selector,
                              child: Text(
                                '${app.label} · ${app.selector}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          controller.text = value;
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: controller,
                      keyboardType: action == RuleAction.DOMAIN_SUFFIX
                          ? TextInputType.url
                          : TextInputType.text,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: action == RuleAction.DOMAIN_SUFFIX
                            ? 'Site'
                            : 'Process name',
                        hintText: action == RuleAction.DOMAIN_SUFFIX
                            ? 'example.com'
                            : 'chrome.exe',
                        prefixIcon: Icon(
                          action == RuleAction.DOMAIN_SUFFIX
                              ? Icons.language
                              : Icons.apps,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: target,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Route via'),
                      items: [
                        for (final item in targets)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            target = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      action == RuleAction.PROCESS_NAME
                          ? 'Apps that bypass the system proxy require TUN. '
                                'Rule changes take effect after core restart.'
                          : 'Rule changes take effect after core restart.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(context.appLocalizations.cancel),
                ),
                FilledButton(
                  onPressed: !canSave
                      ? null
                      : () {
                          final normalized = action == RuleAction.DOMAIN_SUFFIX
                              ? _normalizeQuickDomain(controller.text)
                              : controller.text.trim();
                          Navigator.of(dialogContext).pop(
                            Rule.parse(
                              '${action.value},$normalized,$target',
                            ),
                          );
                        },
                  child: Text(
                    ref.read(currentProfileIdProvider) == _profileId &&
                            ref.read(isStartProvider)
                        ? 'Add & apply'
                        : context.appLocalizations.add,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    if (result == null || !mounted) {
      return;
    }
    final notifier = ref.read(profileCustomRulesProvider(_profileId).notifier);
    final currentRules =
        ref.read(profileCustomRulesProvider(_profileId)).value ??
        const <Rule>[];
    await notifier.replaceAll([...currentRules, result]);
    if (!mounted) {
      return;
    }
    final isCurrent = ref.read(currentProfileIdProvider) == _profileId;
    final isRunning = ref.read(isStartProvider);
    if (isCurrent && isRunning) {
      final restarted = await ref.read(coreActionProvider.notifier).restartCore();
      if (mounted) {
        dialogs.showNotifier(
          restarted
              ? 'Rule added and applied: core restarted.'
              : 'Rule saved, but core restart did not complete.',
        );
      }
    } else {
      dialogs.showNotifier('Rule added. It will apply when this profile starts.');
    }
  }

  Future<void> _restartRulesCore() async {
    final isCurrent = ref.read(currentProfileIdProvider) == _profileId;
    if (!isCurrent || !ref.read(isStartProvider)) {
      return;
    }
    final restarted = await ref.read(coreActionProvider.notifier).restartCore();
    if (mounted && restarted) {
      dialogs.showNotifier('Rules applied: core restarted.');
    }
  }

  Widget _buildQuickHeader() {
    final isCurrent = ref.watch(currentProfileIdProvider) == _profileId;
    final isRunning = ref.watch(isStartProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Quick split tunneling',
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _handleQuickAdd(RuleAction.DOMAIN_SUFFIX),
                    icon: const Icon(Icons.language),
                    label: const Text('Site'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _handleQuickAdd(RuleAction.PROCESS_NAME),
                    icon: const Icon(Icons.apps),
                    label: const Text('App'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: isCurrent && isRunning ? _restartRulesCore : null,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Restart core'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isCurrent && isRunning
                    ? 'After adding, deleting or reordering rules, restart the '
                          'core to apply the new routing.'
                    : 'Rule changes will be applied when this profile is '
                          'started. If it is already running, restart the core.',
                style: context.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleReorder(int oldIndex, int newIndex) {
    ref
        .read(profileCustomRulesProvider(_profileId).notifier)
        .order(oldIndex, newIndex);
  }

  void _moveRule(int ruleId, int delta) {
    final rules =
        ref.read(profileCustomRulesProvider(_profileId)).value ??
        const <Rule>[];
    final index = rules.indexWhere((item) => item.id == ruleId);
    if (index < 0 || rules[index].ruleAction == RuleAction.MATCH) {
      return;
    }
    final lastMovableIndex = rules.lastIndexWhere(
      (item) => item.ruleAction != RuleAction.MATCH,
    );
    if (lastMovableIndex < 0) {
      return;
    }
    final targetIndex = index + delta;
    if (targetIndex < 0 ||
        targetIndex > lastMovableIndex ||
        targetIndex == index) {
      return;
    }
    ref
        .read(profileCustomRulesProvider(_profileId).notifier)
        .order(index, targetIndex);
  }

  void _handleDelete(Set<int> ruleIds) {
    ref.read(profileCustomRulesProvider(_profileId).notifier).delAll(ruleIds);
  }

  void _handleAddOrUpdate({Rule? rule}) {
    showOverwriteNestedSheet<Rule>(
      context: context,
      profileId: widget.profileId,
      overrides: [
        ruleProvider.overrideWithBuild((_, _) => rule ?? Rule.init()),
      ],
      currentOf: (ref) => ref.read(ruleProvider),
      save: _handleSaveRule,
      formBuilder: (_) => const _AddOrEditRuleView(),
    );
  }

  @override
  Widget build(context) {
    final appLocalizations = context.appLocalizations;
    final overwrite = ref.watch(customOverwriteDateProvider(_profileId));
    return OverwriteEditorPage<Rule, int>(
      title: appLocalizations.rule,
      header: _buildQuickHeader(),
      selectionEnabled: true,
      dragFromRow: true,
      idOf: (rule) => rule.id,
      itemsOf: (ref) {
        return ref.watch(profileCustomRulesProvider(_profileId)).value;
      },
      itemBuilder:
          (context, ref, rule, index, isEditing, isSelected, onToggleSelected) {
            final rules =
                ref.watch(profileCustomRulesProvider(_profileId)).value ??
                const <Rule>[];
            final currentIndex = rules.indexWhere((item) => item.id == rule.id);
            final lastMovableIndex = rules.lastIndexWhere(
              (item) => item.ruleAction != RuleAction.MATCH,
            );
            final movable = rule.ruleAction != RuleAction.MATCH;
            final canMoveUp = movable && currentIndex > 0;
            final canMoveDown =
                movable &&
                currentIndex >= 0 &&
                currentIndex < lastMovableIndex;
            return Row(
              children: [
                Expanded(
                  child: RuleItem(
                    invalidMessageOf: (target) {
                      final issues = customRuleIssues(target, overwrite);
                      return issues.isEmpty ? null : issues.getMessage(context);
                    },
                    isEditing: isEditing,
                    isSelected: isSelected,
                    rule: rule,
                    onSelected: onToggleSelected,
                    onEdit: (rule) {
                      _handleAddOrUpdate(rule: rule);
                    },
                  ),
                ),
                if (!isEditing) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: canMoveUp ? () => _moveRule(rule.id, -1) : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed:
                        canMoveDown ? () => _moveRule(rule.id, 1) : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ],
            );
          },
      onReorder: _handleReorder,
      onAdd: () => _handleAddOrUpdate(),
      onDelete: _handleDelete,
      searchFieldsOf: (rule) => rule.searchFields,
      emptyLabel: appLocalizations.ruleEmpty,
      itemExtent: ruleItemHeight,
    );
  }
}

class _AddOrEditRuleView extends ConsumerStatefulWidget {
  const _AddOrEditRuleView();

  @override
  ConsumerState<_AddOrEditRuleView> createState() => _AddOrEditRuleViewState();
}

class _AddOrEditRuleViewState extends ConsumerState<_AddOrEditRuleView> {
  Widget _buildItem({
    required String title,
    TextStyle? titleStyle,
    Widget? trailing,
    bool? invalid,
    final VoidCallback? onPressed,
  }) {
    return OverwriteFormRow(
      invalid: invalid ?? false,
      onPressed: onPressed,
      title: title,
      titleStyle: titleStyle,
      trailing: trailing,
    );
  }

  Future<void> _handleSelectedType() async {
    final res = await Navigator.of(context).push(
      PagedSheetRoute(
        builder: (context) => OverwriteSelectionSheet<RuleAction>(
          title: context.appLocalizations.proxyType,
          sections: [
            OverwriteSelectionSection(
              items: RuleAction.values,
              subtitleBuilder: (context, item) => item.getDesc(context),
            ),
          ],
          labelBuilder: (item) => item.name,
          selectedOf: (ref) =>
              ref.watch(ruleProvider.select((state) => state.ruleAction)),
          onSelected: (item) => Navigator.of(context).pop(item),
        ),
      ),
    );
    if (res == null) {
      return;
    }
    ref
        .read(ruleProvider.notifier)
        .update((state) => state.copyWith(ruleAction: res));
  }

  Widget _buildTypeItem(RuleAction action) {
    return _buildItem(
      title: context.appLocalizations.proxyType,
      onPressed: () {
        _handleSelectedType();
      },
      trailing: Row(
        spacing: 4,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: TooltipText(
              text: Text(
                action.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const GlyphIcon(AppGlyphs.chevronForward),
        ],
      ),
    );
  }

  Widget _buildContentItem(String? content) {
    final appLocalizations = context.appLocalizations;
    final payloadError = ref.watch(
      ruleProvider.select((state) => state.payloadError),
    );
    final field = TextFormField(
      initialValue: content,
      keyboardType: TextInputType.name,
      inputFormatters: TextInputLimits.limit(TextInputLimits.rule),
      onChanged: (value) {
        ref
            .read(ruleProvider.notifier)
            .update((state) => state.copyWith(content: value));
      },
      textAlign: TextAlign.end,
      decoration: InputDecoration.collapsed(
        border: const NoInputBorder(),
        hintText: appLocalizations.inputRuleContent,
      ),
    );
    return _buildItem(
      invalid: payloadError != null,
      title: appLocalizations.content,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (payloadError != null)
            InfoMessageButton(message: payloadError.getMessage(context)),
          Flexible(child: field),
        ],
      ),
    );
  }

  Future<void> _handleSelectedRuleProvider() async {
    final res = await Navigator.of(context).push(
      PagedSheetRoute(
        builder: (context) => Consumer(
          builder: (_, ref, _) {
            final profileId = ProfileIdProvider.of(context)!.profileId;
            final ruleProviders = ref
                .watch(
                  clashConfigProvider(profileId).select(
                    (state) => SelectValue(state.value?.ruleProviders ?? []),
                  ),
                )
                .value;
            final appRuleProviders = ref.watch(
              appProviderNamesProvider(ProviderKind.rule),
            );
            return OverwriteSelectionSheet<String>(
              title: context.appLocalizations.ruleSet,
              sections: [
                OverwriteSelectionSection(
                  items: {...ruleProviders, ...appRuleProviders}.toList(),
                ),
              ],
              labelBuilder: (item) => item,
              selectedOf: (ref) =>
                  ref.watch(ruleProvider.select((state) => state.ruleProvider)),
              onSelected: (item) => Navigator.of(context).pop(item),
              emptyLabel: context.appLocalizations.proxyProvidersEmpty,
            );
          },
        ),
      ),
    );
    if (res == null) {
      return;
    }
    ref
        .read(ruleProvider.notifier)
        .update((state) => state.copyWith(ruleProvider: res));
  }

  Widget _buildRuleProviderItem(int profileId, String? ruleProvider) {
    final appLocalizations = context.appLocalizations;
    final invalid =
        ruleProvider != null &&
        !ref.watch(
          customOverwriteRuleProviderIsValidProvider(profileId, ruleProvider),
        );
    final foregroundColor = invalid
        ? context.colorScheme.error
        : context.colorScheme.onSurfaceVariant;
    final source = ruleProvider == null
        ? null
        : ref.watch(
            providerSourcesProvider(
              profileId,
              ProviderKind.rule,
            ).select((state) => state[ruleProvider]),
          );
    return _buildItem(
      invalid: invalid,
      title: appLocalizations.ruleSet,
      onPressed: _handleSelectedRuleProvider,
      trailing: Row(
        spacing: 4,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (invalid)
            InfoMessageButton(
              message: appLocalizations.invalidRuleSet(ruleProvider),
            ),
          if (source != null)
            Text(
              source.label(appLocalizations),
              style: context.textTheme.bodySmall?.copyWith(
                color: foregroundColor,
              ),
            ),
          Flexible(
            child: TooltipText(
              text: Text(
                ruleProvider ?? appLocalizations.selectRuleSet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: foregroundColor,
                ),
              ),
            ),
          ),
          GlyphIcon(AppGlyphs.chevronForward, color: foregroundColor),
        ],
      ),
    );
  }

  Future<void> _handleSelectedTarget() async {
    final res = await Navigator.of(context).push(
      PagedSheetRoute(
        builder: (context) => Consumer(
          builder: (_, ref, _) {
            final profileId = ProfileIdProvider.of(context)!.profileId;
            final overwrite = ref.watch(customOverwriteDateProvider(profileId));
            final groupTypes = {
              for (final item in overwrite.proxyGroups)
                item.name: item.type.name,
            };
            final proxyTypes = overwrite.proxyTypes;
            return OverwriteSelectionSheet<String>(
              title: context.appLocalizations.splitStrategy,
              sections: [
                OverwriteSelectionSection(
                  label: context.appLocalizations.basicStrategy,
                  items: RuleTarget.baseTargetNames,
                ),
                OverwriteSelectionSection(
                  label: context.appLocalizations.ruleTarget,
                  items: groupTypes.keys.toList(),
                  subtitleBuilder: (context, name) => groupTypes[name] ?? '',
                ),
                OverwriteSelectionSection(
                  label: context.appLocalizations.proxies,
                  items: overwrite.proxyNames,
                  subtitleBuilder: (context, name) => proxyTypes[name] ?? '',
                ),
              ],
              labelBuilder: (item) => item,
              selectedOf: (ref) =>
                  ref.watch(ruleProvider.select((state) => state.ruleTarget)),
              onSelected: (item) => Navigator.of(context).pop(item),
            );
          },
        ),
      ),
    );
    if (res == null) {
      return;
    }
    ref
        .read(ruleProvider.notifier)
        .update((state) => state.copyWith(ruleTarget: res));
  }

  Widget _buildTargetItem(int profileId, String? target) {
    final appLocalizations = context.appLocalizations;
    return Consumer(
      builder: (_, ref, _) {
        final invalid = !ref.watch(
          customOverwriteTargetIsValidProvider(profileId, target),
        );
        final foregroundColor = invalid
            ? context.colorScheme.error
            : context.colorScheme.onSurfaceVariant;
        return _buildItem(
          invalid: invalid,
          title: appLocalizations.splitStrategy,
          onPressed: _handleSelectedTarget,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (invalid && target != null)
                InfoMessageButton(
                  message: appLocalizations.invalidPolicy(target),
                ),
              Flexible(
                flex: 1,
                child: TooltipText(
                  text: Text(
                    target ?? appLocalizations.selectSplitStrategy,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: foregroundColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GlyphIcon(AppGlyphs.chevronForward, color: foregroundColor),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSelectedSubRule() async {
    final res = await Navigator.of(context).push(
      PagedSheetRoute(
        builder: (context) => Consumer(
          builder: (_, ref, _) {
            final profileId = ProfileIdProvider.of(context)!.profileId;
            final subRules = ref
                .watch(
                  clashConfigProvider(
                    profileId,
                  ).select((state) => SelectValue(state.value?.subRules ?? [])),
                )
                .value;
            return OverwriteSelectionSheet<String>(
              title: context.appLocalizations.subRule,
              sections: [OverwriteSelectionSection(items: subRules)],
              labelBuilder: (item) => item,
              selectedOf: (ref) =>
                  ref.watch(ruleProvider.select((state) => state.subRule)),
              onSelected: (item) => Navigator.of(context).pop(item),
              emptyLabel: context.appLocalizations.subRuleEmpty,
            );
          },
        ),
      ),
    );
    if (res == null) {
      return;
    }
    ref
        .read(ruleProvider.notifier)
        .update((state) => state.copyWith(subRule: res));
  }

  Widget _buildSubRuleItem(String? subRule) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.subRule,
      onPressed: _handleSelectedSubRule,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Flexible(
            flex: 1,
            child: TooltipText(
              text: Text(
                subRule ?? appLocalizations.selectSubRule,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const GlyphIcon(AppGlyphs.chevronForward),
        ],
      ),
    );
  }

  Widget _buildNoResolveItem(bool noResolve, bool src) {
    final appLocalizations = context.appLocalizations;
    // The core turns no-resolve on with src, so the switch cannot disagree.
    return _buildItem(
      title: appLocalizations.noResolveHostname,
      trailing: Switch(
        value: noResolve || src,
        onChanged: src
            ? null
            : (value) {
                ref
                    .read(ruleProvider.notifier)
                    .update((state) => state.copyWith(noResolve: value));
              },
      ),
    );
  }

  Widget _buildSrcItem(bool src) {
    final appLocalizations = context.appLocalizations;
    return _buildItem(
      title: appLocalizations.matchSourceIp,
      trailing: Switch(
        value: src,
        onChanged: (value) {
          ref
              .read(ruleProvider.notifier)
              .update((state) => state.copyWith(src: value));
        },
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_handleSaveRule(context, ref)) {
      context.safeNestedPop();
    }
  }

  Future<void> _handleDelete(int profileId) async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showMessage(
      message: TextSpan(
        text: appLocalizations.deleteTip(appLocalizations.rule),
      ),
    );
    if (res == true && mounted) {
      final id = ref.read(ruleProvider).id;
      ref.read(profileCustomRulesProvider(profileId).notifier).delAll([id]);
      context.safeNestedPop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final profileId = ProfileIdProvider.of(context)!.profileId;
    final rule = ref.watch(ruleProvider);
    final height = ref.sheetHeight(context, 0.60);
    return CommonScaffold(
      actions: [
        AppBarActionButton(
          data: IconButtonData(
            glyph: AppGlyphs.check,
            onPressed: _handleSave,
            tooltip: context.appLocalizations.save,
          ),
        ),
      ],
      body: Container(
        constraints: BoxConstraints(maxHeight: height),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(bottom: 20, top: context.contentTopPadding),
          children: [
            generateSectionV3(
              title: appLocalizations.basicInfo,
              items: [
                _buildTypeItem(rule.ruleAction),
                if (rule.ruleAction != RuleAction.MATCH)
                  rule.ruleAction == RuleAction.RULE_SET
                      ? _buildRuleProviderItem(profileId, rule.ruleProvider)
                      : _buildContentItem(rule.content),
                rule.ruleAction != RuleAction.SUB_RULE
                    ? _buildTargetItem(profileId, rule.ruleTarget)
                    : _buildSubRuleItem(rule.subRule),
              ],
            ),
            if (rule.ruleAction.hasParams)
              generateSectionV3(
                title: appLocalizations.additionalParameters,
                items: [
                  _buildNoResolveItem(rule.noResolve, rule.src),
                  _buildSrcItem(rule.src),
                ],
              ),
            generateSectionV3(
              title: appLocalizations.action,
              items: [
                if (rule.id != -1)
                  _buildItem(
                    title: appLocalizations.delete,
                    titleStyle: TextStyle(color: context.colorScheme.error),
                    onPressed: () {
                      _handleDelete(profileId);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      title: rule.id == -1
          ? appLocalizations.addRule
          : appLocalizations.editRule,
    );
  }
}

bool _handleSaveRule(BuildContext context, WidgetRef ref) {
  final rule = ref.read(ruleProvider);
  final appLocalizations = context.appLocalizations;
  final payloadError = rule.payloadError;
  if (payloadError != null) {
    dialogs.showMessage(
      cancelable: false,
      message: TextSpan(text: payloadError.getMessage(context)),
    );
    return false;
  }
  if (rule.ruleAction != RuleAction.MATCH &&
      rule.realContent?.isNotEmpty != true) {
    dialogs.showMessage(
      cancelable: false,
      message: TextSpan(
        text: rule.ruleAction == RuleAction.RULE_SET
            ? appLocalizations.proxyProvidersNotEmpty
            : appLocalizations.contentNotEmpty,
      ),
    );
    return false;
  }
  if (rule.realTarget?.isNotEmpty != true) {
    dialogs.showMessage(
      cancelable: false,
      message: TextSpan(
        text: rule.ruleAction == RuleAction.SUB_RULE
            ? appLocalizations.subRuleNotEmpty
            : appLocalizations.splitStrategyNotEmpty,
      ),
    );
    return false;
  }
  final profileId = ProfileIdProvider.of(context)!.profileId;
  Rule addedRule = rule;
  if (rule.id == -1) {
    addedRule = rule.copyWith(id: snowflake.id);
  }
  ref.read(profileCustomRulesProvider(profileId).notifier).put(addedRule);
  return true;
}
