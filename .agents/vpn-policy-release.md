# VPN Policy release 2026-10-14

Working release branch: `vpn-policy-global-09-20261014` in `cyberintech/FlClash`.
Base: `vpn-policy-c8f8-fix` at `15a338c`, merged with upstream `chen08209/FlClash` tag `v0.9.0` (`03f9553`). The upstream tag is a real merge parent, not a version-only edit.

## Global semantics

Global means all public Internet traffic through the VPN. Windows capture uses TUN with automatic routes, strict routing and unrestricted route-address. Private LAN bypass follows the app's network setting. System Proxy is an independent compatibility toggle; it cannot substitute for TUN.

Entering Global selects a VPN member of GLOBAL instead of retaining DIRECT, reject, or a group whose effective selection is direct. Applying Global also repairs a saved direct pick using concrete VPN nodes from the profile being applied. Profile previews do not mutate selections. Starting from a persisted Global mode enforces TUN capture again. Enabling TUN follows the existing authorization/Core restart owner; cancellation reports the upstream authorization failure.

Rule mode continues to use Mihomo rules for include-only split tunneling. It captures traffic through TUN and sends unmatched traffic DIRECT. No second Android package filter is applied to VPN Policy modes.

## 0.9 migration

VPN Policy now lives at `lib/views/profiles/custom/vpn_policy.dart`. Its entry is in the profile context menu. Custom profile conversion and key-based synchronization use upstream's native custom-import path. Profile rules use `profileRulesProvider` and `RulesDao.setProfileRulesWithBatch`. Existing keys/preferences are retained, and the upstream database migration is included. REALITY/XUDP compatibility and update-exit/Core transport fixes are retained.

## Build and delivery

Windows and Android preview workflows trigger on this branch. Pins match upstream 0.9: Flutter 3.47.6, Go 1.27.1, Rust 1.99.0. Windows artifact contains `VPN-POLICY-BUILD.txt` with source SHA and build timestamp. Publish the ZIP contents as a single archive to `/srv/vpn-policy-downloads/VPN-Policy-Windows-LATEST.zip`; keep `fl_clash.exe` at the archive root. Android target is `/srv/vpn-policy-downloads/VPN-Policy-Android-arm64.apk`.

## Validation at preparation

Flutter pub get and code generation completed. Flutter analyze: no issues. 206 focused tests passed: Global/capture/selection, key bootstrap/client/policy, setup and profile orchestration, database migration/rules, exit, desktop lifecycle/helper/transport.

EXP has no Windows desktop session and lacks local Go/Rust build toolchains. Dart tests disable native build hooks temporarily; committed hooks remain enabled. The release workflows must prove native compilation. Windows Service Control Manager, UAC and actual public IP/UDP capture still require the user's desktop test.

Acceptance: update with the stamped ZIP, stop other VPNs, accept helper authorization, select Global, verify public IP in both browser and `curl.exe --noproxy "*" https://api.ipify.org`, restart app and repeat; return to Rule and verify include-only policy. System Proxy may remain off for the curl check.

## Release blocker observed 2026-10-14 10:40 UTC

Source commit `4f39b9b`, PR #8. Both explicit workflow dispatches were refused with HTTP 422: `Actions has been disabled for this repository`. Repository permissions returned `enabled=true`, `allowed_actions=all`; the Windows workflow returned `state=active`. Re-enabling the workflow and repository Actions through the documented API did not restore dispatch. No run was created for this branch. This is not a native build failure: native compilation has not started. No LATEST file has been replaced. Do not claim delivery until dispatch is restored, the stamped source builds successfully, and the artifact is published.

After access is restored, root on EXP can run `gh workflow run vpn-policy-windows-preview.yml --repo cyberintech/FlClash --ref vpn-policy-global-09-20261014` (and the Android workflow analogously). Root's GitHub CLI is authenticated; remote-agent's CLI is not. Use RDC online device `exp` with UID 0; `vpn` is a separate online device for publishing. Do not install another RDC agent.
