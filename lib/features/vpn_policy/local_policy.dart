import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/clash_config.dart';

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

List<Rule> compileLocalVpnPolicy({
  required String mode,
  required String vpnTarget,
  Iterable<String> appSelectors = const [],
  Iterable<String> domains = const [],
}) {
  if (mode == 'all_vpn') {
    return [Rule.parse('MATCH,$vpnTarget')];
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
