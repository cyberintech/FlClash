import 'package:fl_clash/features/vpn_policy/installed_apps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses, filters and deduplicates Windows application selectors', () {
    final apps = parseWindowsInstalledApps('''
[
  {"label":"Telegram","selector":"Telegram.exe","path":"C:/Telegram.exe"},
  {"label":"Telegram Desktop","selector":"telegram.EXE","path":"C:/Telegram2.exe"},
  {"label":"Chrome","selector":"chrome.exe","path":"C:/Chrome.exe"},
  {"label":"Document","selector":"readme.txt","path":"C:/readme.txt"},
  {"label":"","selector":"tool.exe","path":"C:/tool.exe"}
]
''');

    expect(apps.map((item) => item.selector.toLowerCase()).toSet(), {
      'telegram.exe',
      'chrome.exe',
      'tool.exe',
    });
    expect(apps.first.label, 'Chrome');
    expect(
      apps
          .singleWhere((item) => item.selector.toLowerCase() == 'telegram.exe')
          .label,
      'Telegram',
    );
    expect(
      apps.singleWhere((item) => item.selector == 'tool.exe').label,
      'tool.exe',
    );
  });

  test('empty Windows discovery output produces an empty list', () {
    expect(parseWindowsInstalledApps('  '), isEmpty);
  });
}
