import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/custom/custom.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _customOpenPause = Duration(milliseconds: 150);

void showAddProfilePage(BuildContext origin) {
  final context = globalState.navigatorKey.currentState!.context;
  showExtend(
    context,
    builder: (context) => CommonScaffold(
      title: context.appLocalizations.addProfile,
      body: AddProfileView(context: context, origin: origin),
    ),
  );
}

class AddProfileView extends ConsumerWidget {
  final BuildContext context;

  /// Where a page the add page leads to opens: the desktop sheet is on the root.
  final BuildContext origin;

  const AddProfileView({
    super.key,
    required this.context,
    required this.origin,
  });

  Future<void> _handleAddProfileFormFile(WidgetRef ref) async {
    unawaited(ref.read(profilesActionProvider.notifier).addProfileFormFile());
  }

  Future<void> _addVpnPolicyByKey(WidgetRef ref) async {
    final key = await dialogs.showCommonDialog<String>(
      child: InputDialog(
        title: 'Подключить VPN Policy',
        value: '',
        labelText: 'Device Key',
        hintText: 'vp1_...',
        obscureText: true,
        validator: (value) {
          final key = value?.trim() ?? '';
          if (key.isEmpty) {
            return 'Введите Device Key';
          }
          if (!key.startsWith('vp1_')) {
            return 'Device Key должен начинаться с vp1_';
          }
          return null;
        },
      ),
    );
    if (key == null) {
      return;
    }

    final profile = await globalState.loadingRun(
      () => ref
          .read(profilesActionProvider.notifier)
          .addVpnPolicyFromDeviceKey(key),
      tag: LoadingTag.profiles,
      title: 'VPN Policy',
    );
    if (profile == null) {
      return;
    }

    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    dialogs.showNotifier(
      'VPN Policy подключён: ${profile.label.isEmpty ? 'VPN Policy' : profile.label}. '
      'VLESS и split tunneling применены автоматически.',
      level: MessageLevel.success,
    );
  }

  Future<void> _toScan(WidgetRef ref) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    if (system.isDesktop) {
      unawaited(profilesAction.addProfileFormQrCode());
      return;
    }
    final url = await BaseNavigator.push(context, const ScanPage());
    if (url != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(profilesAction.addProfileFromLink(url));
      });
    }
  }

  Future<void> _toAdd(WidgetRef ref) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showNamedUrlsInput(
      title: appLocalizations.importFromLink,
      urlLabel: appLocalizations.link,
      batchTip: appLocalizations.batchLinkInputTip,
      urlValidator: (value) {
        if (value == null || value.isEmpty) {
          return appLocalizations.emptyTip(appLocalizations.link);
        }
        if (!value.isUrl && !value.isShareLink) {
          return appLocalizations.invalidLinkTip;
        }
        return null;
      },
      existingUrls: {
        for (final profile in ref.read(profilesProvider))
          if (profile.url.isNotEmpty) profile.url,
      },
      withAgeSecretKey: true,
    );
    switch (res) {
      case null:
        return;
      case [final single]:
        unawaited(
          profilesAction.addProfileFromLink(
            single.url,
            label: single.label,
            ageSecretKey: single.ageSecretKey,
          ),
        );
      default:
        unawaited(
          profilesAction.addProfilesFromLinks([
            for (final item in res) item.url,
          ]),
        );
    }
  }

  Future<void> _toAddCustom(BuildContext context, WidgetRef ref) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    final label = context.appLocalizations.unnamed;
    Widget editor() => CustomProfileView(
      profileId: profilesAction.addCustomProfile(label),
      isNew: true,
    );
    final navigator = Navigator.of(context);
    if (!origin.mounted || Navigator.of(origin) == navigator) {
      unawaited(BaseNavigator.pushReplacement(context, editor()));
      return;
    }
    // The sheet sits above origin's navigator: a page opened there before the
    // sheet has gone fades in beneath it.
    navigator.pop();
    await whenRouteSettled(context);
    await Future<void>.delayed(_customOpenPause);
    if (origin.mounted) {
      unawaited(BaseNavigator.push(origin, editor()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    return ListView(
      padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 16),
      children: [
        ListItem(
          leading: const GlyphIcon(AppGlyphs.key),
          title: const Text('VPN Policy по Device Key'),
          subtitle: const Text(
            'Один ключ: приложение само получит VLESS, policy и применит split tunneling.',
          ),
          onTap: () => _addVpnPolicyByKey(ref),
        ),
        ListItem(
          leading: const GlyphIcon(AppGlyphs.qrCode),
          title: Text(appLocalizations.qrcode),
          subtitle: Text(appLocalizations.qrcodeDesc),
          onTap: () => _toScan(ref),
        ),
        ListItem(
          leading: const GlyphIcon(AppGlyphs.importFile),
          title: Text(appLocalizations.file),
          subtitle: Text(appLocalizations.fileDesc),
          onTap: () => _handleAddProfileFormFile(ref),
        ),
        ListItem(
          leading: const GlyphIcon(AppGlyphs.cloudDownload),
          title: Text(appLocalizations.link),
          subtitle: Text(appLocalizations.linkDesc),
          onTap: () => _toAdd(ref),
        ),
        ListItem(
          leading: const GlyphIcon(AppGlyphs.customize),
          title: Text(appLocalizations.customProfile),
          subtitle: Text(appLocalizations.customProfileDesc),
          onTap: () => _toAddCustom(context, ref),
        ),
      ],
    );
  }
}
