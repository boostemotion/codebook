import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart'
    show BannerHost, BannerLevel, ButtonTheme, ThemeMode;
import 'package:prism_shell/prism_shell.dart';

import '../../state/vault_controller.dart';
import '../bridge/vault_controller_provider.dart';
import '../shell/cipherbook_navigation.dart';
import '../shell/cipherbook_shell_chrome.dart';
import '../theme/cipherbook_visual_tokens.dart';
import '../unlock/vault_unlock_page.dart';
import '../vault/vault_query.dart';
import 'cipherbook_destinations.dart';
import 'cipherbook_ui_localizations.dart';

class CipherbookPrismApp extends StatefulWidget {
  const CipherbookPrismApp({super.key, required this.controller});

  final VaultController controller;

  @override
  State<CipherbookPrismApp> createState() => _CipherbookPrismAppState();
}

class _CipherbookPrismAppState extends State<CipherbookPrismApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final pickerTemporarilyOwnsFocus =
        state == AppLifecycleState.inactive &&
        widget.controller.externalUiActive;
    if (pickerTemporarilyOwnsFocus) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(widget.controller.handleAppLifecycle(state));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.controller.registerActivity(),
      onPointerSignal: (_) => widget.controller.registerActivity(),
      child: ProviderScope(
        overrides: [
          vaultControllerProvider.overrideWithValue(widget.controller),
          initialShellSettingsProvider.overrideWithValue(
            const ShellSettings(
              themeMode: ThemeMode.dark,
              seedColor: CipherbookVisualTokens.accent,
              liquidGlass: false,
              sidebarExpanded: true,
              floatingNavigationBar: true,
              compactDensity: false,
              locale: 'zh_CN',
            ),
          ),
        ],
        child: const _CipherbookPrismRoot(),
      ),
    );
  }
}

class _CipherbookPrismRoot extends StatelessWidget {
  const _CipherbookPrismRoot();

  @override
  Widget build(BuildContext context) {
    return FrontendShellApp(
      title: 'Cipherbook',
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        CipherbookUiLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      desktopTopInset: 0,
      themeBuilder: cipherbookPrismTheme,
      home: ButtonTheme(
        data: CipherbookVisualTokens.buttonTheme,
        child: const _VaultEntryGate(),
      ),
    );
  }
}

class _VaultEntryGate extends ConsumerStatefulWidget {
  const _VaultEntryGate();

  @override
  ConsumerState<_VaultEntryGate> createState() => _VaultEntryGateState();
}

class _VaultEntryGateState extends ConsumerState<_VaultEntryGate> {
  late bool _wasUnlocked;
  late final VaultController _controller;
  late int _lastLanSyncCompletionRevision;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(vaultControllerProvider);
    _wasUnlocked = _controller.isUnlocked;
    _lastLanSyncCompletionRevision = _controller.lanSyncCompletionRevision;
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    final unlocked = _controller.isUnlocked;
    if (_wasUnlocked && !unlocked) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
      ref
          .read(currentShellDestinationProvider.notifier)
          .go(CipherbookDestinationId.dashboard);
      ref.read(vaultQueryProvider.notifier).showAll();
      ref.read(passwordDetailShellHiddenProvider.notifier).setHidden(false);
    }
    final syncRevision = _controller.lanSyncCompletionRevision;
    if (syncRevision != _lastLanSyncCompletionRevision) {
      _lastLanSyncCompletionRevision = syncRevision;
      final message = _controller.lanSyncCompletionMessage;
      if (message != null && message.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          BannerHost.maybeOf(context)?.show(
            message,
            level: BannerLevel.success,
            onTap: () {
              if (mounted) {
                ref
                    .read(currentShellDestinationProvider.notifier)
                    .go(CipherbookDestinationId.sync);
              }
            },
          );
        });
      }
    }
    _wasUnlocked = unlocked;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isUnlocked) {
      return VaultUnlockPage(key: ValueKey(_controller.storageState));
    }
    final detailShellHidden = ref.watch(passwordDetailShellHiddenProvider);
    return ResponsiveShell(
      initialDestinationId: CipherbookDestinationId.dashboard,
      destinations: cipherbookDestinationsOf(context),
      navigationVisible: !detailShellHidden,
    );
  }
}
