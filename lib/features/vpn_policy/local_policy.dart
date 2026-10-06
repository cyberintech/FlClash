import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/clash_config.dart';

const _nueQuicFallbackAppSelectors = {
  'chrome.exe',
  'msedge.exe',
  'com.google.android.youtube',
};

bool _shouldDisableQuicForNueApp(String vpnTarget, String selector) {
  final normalizedTarget = vpnTarget.trim().toUpperCase();
  if (normalizedTarget != 'NUE-VLESS' &&
      normalizedTarget != 'NUE-VLESS-REALITY') {
    return false;
  }
  return _nueQuicFallbackAppSelectors.contains(selector.trim().toLowerCase());
}

Rule _quicFallbackRule(String selector) {
  return Rule.parse(
    'AND,((PROCESS-NAME,$selector),(NETWORK,UDP),(DST-PORT,443)),REJECT',
  );
}

String normalizeLocalPolicyDomain(String value) {
  var domain = value.trim().toLowerCase();
  domain = domain.replaceFirst(RegExp(r'^https?://'), '');
  domain = domain.split('/').first;
  domain = domain.replaceFirst(RegExp(r'^\*\.'), '');
  if (domain.isEmpty) {
    throw const FormatException('Empty domain');
  }
  if (domain.contains(RegExp(r'[,\s]')) || domain.contains(':')) {
    throw FormatException('Invalid domain: $value');
  }
  return domain;
}

List<String> inferLocalAppSelectorsFromRules({
  required String mode,
  required Iterable<Rule> rules,
}) {
  if (mode == 'all_vpn') {
    return const [];
  }
  final selectors = <String>{};
  for (final rule in rules) {
    if (rule.ruleAction != RuleAction.PROCESS_NAME) {
      continue;
    }
    final selector = rule.realContent?.trim();
    final target = rule.realTarget?.trim().toUpperCase();
    if (selector == null || selector.isEmpty || target == null) {
      continue;
    }
    final selected = switch (mode) {
      'exclude_selected' => target == RuleTarget.DIRECT.value,
      _ =>
        target != RuleTarget.DIRECT.value &&
        target != RuleTarget.REJECT.value &&
        target != RuleTarget.REJECT_DROP.value,
    };
    if (selected) {
      selectors.add(selector);
    }
  }
  return selectors.toList()..sort();
}

List<Rule> compileLocalVpnPolicy({
  required String mode,
  required String vpnTarget,
  Iterable<String> appSelectors = const [],
  Iterable<String> domains = const [],
}) {
  if (mode == 'all_vpn') {
    final normalizedTarget = vpnTarget.trim().toUpperCase();
    final isNue =
        normalizedTarget == 'NUE-VLESS' ||
        normalizedTarget == 'NUE-VLESS-REALITY';
    return [
      if (isNue)
        Rule.parse('AND,((NETWORK,UDP),(DST-PORT,443)),REJECT'),
      Rule.parse('MATCH,$vpnTarget'),
    ];
  }

  final selectedTarget = mode == 'exclude_selected'
      ? RuleTarget.DIRECT.value
      : vpnTarget;
  final fallbackTarget = mode == 'exclude_selected'
      ? vpnTarget
      : RuleTarget.DIRECT.value;

  final rules = <Rule>[];
  final seenApps = <String>{};
  for (final raw in appSelectors) {
    final selector = raw.trim();
    if (selector.isEmpty || !seenApps.add(selector.toLowerCase())) {
      continue;
    }
    if (selectedTarget == vpnTarget &&
        _shouldDisableQuicForNueApp(vpnTarget, selector)) {
      rules.add(_quicFallbackRule(selector));
    }
    rules.add(
      Rule.parse('${RuleAction.PROCESS_NAME.value},$selector,$selectedTarget'),
    );
  }

  final seenDomains = <String>{};
  for (final raw in domains) {
    final domain = normalizeLocalPolicyDomain(raw);
    if (!seenDomains.add(domain)) {
      continue;
    }
    rules.add(
      Rule.parse('${RuleAction.DOMAIN_SUFFIX.value},$domain,$selectedTarget'),
    );
  }

  rules.add(Rule.parse('${RuleAction.MATCH.value},$fallbackTarget'));
  return rules;
}
