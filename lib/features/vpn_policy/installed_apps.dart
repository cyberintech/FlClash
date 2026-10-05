import 'dart:convert';
import 'dart:io';

class VpnPolicyInstalledApp {
  final String label;
  final String selector;
  final String? path;

  const VpnPolicyInstalledApp({
    required this.label,
    required this.selector,
    this.path,
  });
}

List<VpnPolicyInstalledApp> parseWindowsInstalledApps(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const [];
  }
  final decoded = json.decode(text);
  final values = decoded is List ? decoded : [decoded];
  final bySelector = <String, VpnPolicyInstalledApp>{};

  for (final value in values) {
    if (value is! Map) {
      continue;
    }
    final item = Map<String, dynamic>.from(value);
    final selector = item['selector']?.toString().trim() ?? '';
    if (selector.isEmpty || !selector.toLowerCase().endsWith('.exe')) {
      continue;
    }
    final label = item['label']?.toString().trim();
    final app = VpnPolicyInstalledApp(
      label: label == null || label.isEmpty ? selector : label,
      selector: selector,
      path: item['path']?.toString(),
    );
    final key = selector.toLowerCase();
    final current = bySelector[key];
    if (current == null || app.label.length < current.label.length) {
      bySelector[key] = app;
    }
  }

  final apps = bySelector.values.toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return apps;
}

Future<List<VpnPolicyInstalledApp>> loadWindowsInstalledApps() async {
  if (!Platform.isWindows) {
    return const [];
  }

  const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$items = New-Object System.Collections.Generic.List[object]
$ws = New-Object -ComObject WScript.Shell

$roots = @(
  [Environment]::GetFolderPath('StartMenu'),
  [Environment]::GetFolderPath('CommonStartMenu')
) | Where-Object { $_ -and (Test-Path $_) }

foreach ($root in $roots) {
  Get-ChildItem -LiteralPath $root -Filter *.lnk -Recurse -File | ForEach-Object {
    try {
      $shortcut = $ws.CreateShortcut($_.FullName)
      $target = $shortcut.TargetPath
      if ($target -and [IO.Path]::GetExtension($target) -ieq '.exe') {
        $items.Add([PSCustomObject]@{
          label = $_.BaseName
          selector = [IO.Path]::GetFileName($target)
          path = $target
        })
      }
    } catch {}
  }
}

Get-Process | ForEach-Object {
  try {
    $target = $_.Path
    if ($target -and [IO.Path]::GetExtension($target) -ieq '.exe') {
      $items.Add([PSCustomObject]@{
        label = $_.ProcessName
        selector = [IO.Path]::GetFileName($target)
        path = $target
      })
    }
  } catch {}
}

$items | ConvertTo-Json -Compress
''';

  final result = await Process.run(
    'powershell.exe',
    const ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const ['-NoProfile', '-NonInteractive'],
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return parseWindowsInstalledApps(result.stdout.toString());
}
