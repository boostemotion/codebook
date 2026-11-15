import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import 'shell_destination.dart';
import 'shell_navigation.dart';
import 'shell_platform.dart';
import 'shell_settings.dart';

typedef ShellWindowDragAreaBuilder = WidgetBuilder;

/// A configurable responsive top-level shell.
///
/// The host supplies every page and label. The shell owns navigation geometry,
/// retained page state, motion, and responsive presentation.
class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({
    super.key,
    required this.destinations,
    required this.initialDestinationId,
    this.windowDragAreaBuilder,
    this.windowControlsWidth = 148,
    this.windowDragAreaHeight = 32,
    this.wideSidebarBreakpoint = 768,
    this.mobileWidthBreakpoint = 620,
    this.mobilePlatformPredicate = defaultMobilePlatformPredicate,
    this.navigationVisible = true,
  }) : assert(destinations.length > 0);

  final List<ShellDestinationSpec> destinations;
  final String initialDestinationId;
  final ShellWindowDragAreaBuilder? windowDragAreaBuilder;
  final double windowControlsWidth;
  final double windowDragAreaHeight;
  final double wideSidebarBreakpoint;
  final double mobileWidthBreakpoint;
  final bool Function(TargetPlatform platform) mobilePlatformPredicate;
  final bool navigationVisible;

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

bool _hasUniqueDestinationIds(List<ShellDestinationSpec> destinations) {
  final ids = <String>{};
  return destinations.every((destination) => ids.add(destination.id));
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  late final PageController _pageController;
  late final ShellNavigation _navigation;

  @override
  void initState() {
    super.initState();
    assert(
      _hasUniqueDestinationIds(widget.destinations),
      'ResponsiveShell destination IDs must be unique.',
    );
    final currentId = ref.read(currentShellDestinationProvider);
    final initialId = _resolveId(currentId);
    _pageController = PageController(
      initialPage: widget.destinations.indexWhere(
        (destination) => destination.id == initialId,
      ),
    );
    _navigation = ShellNavigation(select: _select, push: _push);
  }

  @override
  void didUpdateWidget(covariant ResponsiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentId = ref.read(currentShellDestinationProvider);
    if (currentId.isNotEmpty && !_containsDestination(currentId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(currentShellDestinationProvider.notifier)
              .go(widget.initialDestinationId);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _containsDestination(String destinationId) {
    return widget.destinations.any(
      (destination) => destination.id == destinationId,
    );
  }

  String _resolveId(String destinationId) {
    if (_containsDestination(destinationId)) {
      return destinationId;
    }
    if (_containsDestination(widget.initialDestinationId)) {
      return widget.initialDestinationId;
    }
    return widget.destinations.first.id;
  }

  void _select(String destinationId) {
    if (!_containsDestination(destinationId)) {
      return;
    }
    ref.read(currentShellDestinationProvider.notifier).go(destinationId);
  }

  Future<void> _push(BuildContext context, String destinationId) async {
    final destination = widget.destinations
        .where((destination) => destination.id == destinationId)
        .firstOrNull;
    if (destination == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      CardPageRoute<void>(
        builder: (routeContext) => ShellNavigationScope(
          navigation: _navigation,
          child: Builder(builder: destination.builder),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storedId = ref.watch(currentShellDestinationProvider);
    final currentId = _resolveId(storedId);
    final settings = ref.watch(shellSettingsProvider);

    ref.listen<String>(currentShellDestinationProvider, (previous, next) {
      if (!_pageController.hasClients || previous == next) {
        return;
      }
      final index = widget.destinations.indexWhere(
        (destination) => destination.id == next,
      );
      if (index < 0) {
        return;
      }
      final motion = context.motionDuration(
        settings.tabAnimation == ShellTabAnimation.slide
            ? const Duration(milliseconds: 330)
            : const Duration(milliseconds: 180),
      );
      if (motion == Duration.zero) {
        _pageController.jumpToPage(index);
      } else {
        _pageController.animateToPage(
          index,
          duration: motion,
          curve: Easing.emphasizedDecelerate,
        );
      }
    });

    return ShellNavigationScope(
      navigation: _navigation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final isMobile =
              widget.mobilePlatformPredicate(defaultTargetPlatform) ||
              size.width < widget.mobileWidthBreakpoint;
          return isMobile
              ? _buildMobileShell(context, currentId, settings)
              : _buildDesktopShell(context, currentId, settings, size.width);
        },
      ),
    );
  }

  Widget _buildDesktopShell(
    BuildContext context,
    String currentId,
    ShellSettings settings,
    double width,
  ) {
    final desktopDestinations = widget.destinations
        .where((destination) => destination.desktop)
        .toList();
    final selectedIndex = desktopDestinations.indexWhere(
      (destination) => destination.id == currentId,
    );
    final canExpandInPlace = width >= widget.wideSidebarBreakpoint;
    final expanded = settings.sidebarExpanded && canExpandInPlace;
    final pageView = _buildPageView(context, currentId);
    final content = desktopDestinations.isEmpty
        ? pageView
        : Row(
            children: [
              if (widget.navigationVisible)
                Surface(
                  color: context.colorScheme.chromeSurface,
                  child: NavigationSidebar(
                    destinations: [
                      for (final destination in desktopDestinations)
                        SidebarDestination(
                          glyph: destination.glyph,
                          label: destination.label(context),
                        ),
                    ],
                    selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                    expanded: expanded,
                    onSelected: (index) {
                      _select(desktopDestinations[index].id);
                    },
                    onToggle: canExpandInPlace
                        ? () {
                            ref
                                .read(shellSettingsProvider.notifier)
                                .update(
                                  (value) => value.copyWith(
                                    sidebarExpanded: !value.sidebarExpanded,
                                  ),
                                );
                          }
                        : null,
                  ),
                ),
              Expanded(child: pageView),
            ],
          );
    final dragAreaBuilder = widget.windowDragAreaBuilder;
    return Stack(
      children: [
        content,
        if (dragAreaBuilder != null)
          Positioned(
            left: 0,
            top: 0,
            right: widget.windowControlsWidth,
            height: widget.windowDragAreaHeight,
            child: Builder(builder: dragAreaBuilder),
          ),
      ],
    );
  }

  Widget _buildMobileShell(
    BuildContext context,
    String currentId,
    ShellSettings settings,
  ) {
    final mobileDestinations = widget.destinations
        .where((destination) => destination.mobile)
        .toList();
    final page = _buildPageView(context, currentId);
    if (mobileDestinations.isEmpty) {
      return page;
    }
    final directIndex = mobileDestinations.indexWhere(
      (destination) => destination.id == currentId,
    );
    final selectedIndex = directIndex < 0
        ? mobileDestinations.length - 1
        : directIndex;
    if (!settings.floatingNavigationBar) {
      return Column(
        children: [
          Expanded(child: page),
          if (widget.navigationVisible)
            NavigationBar(
              destinations: [
                for (final destination in mobileDestinations)
                  NavigationDestination(
                    icon: GlyphIcon(destination.glyph),
                    label: destination.label(context),
                  ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                _select(mobileDestinations[index].id);
              },
            ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: ClipRect(child: page)),
        if (widget.navigationVisible)
          _NarrowNavigationDock(
            destinations: [
              for (final destination in mobileDestinations)
                NavigationDockDestination(
                  glyph: destination.glyph,
                  label: destination.label(context),
                ),
            ],
            selectedIndex: selectedIndex,
            onSelected: (index) {
              _select(mobileDestinations[index].id);
            },
          ),
      ],
    );
  }

  Widget _buildPageView(BuildContext context, String currentId) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      allowImplicitScrolling: true,
      children: [
        for (final destination in widget.destinations)
          _KeepAliveShellPage(
            key: PageStorageKey(
              destination.storageKey ?? 'shell-page-${destination.id}',
            ),
            active: destination.id == currentId,
            child: Builder(builder: destination.builder),
          ),
      ],
    );
  }
}

class _NarrowNavigationDock extends StatelessWidget {
  const _NarrowNavigationDock({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavigationDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _edgeMargin = 21.0;
  static const _shadowRoom = 8.0;

  @override
  Widget build(BuildContext context) {
    final height = NavigationDock.heightOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomMargin = safeBottom > _edgeMargin ? safeBottom : _edgeMargin;
    return SizedBox(
      width: double.infinity,
      height: _shadowRoom + height + bottomMargin,
      child: RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _edgeMargin,
            _shadowRoom,
            _edgeMargin,
            bottomMargin,
          ),
          child: LiquidGlassScope(
            key: const ValueKey('shell-narrow-navigation-selection'),
            enabled: false,
            child: FloatingNavigationBar(
              key: const ValueKey('shell-narrow-navigation-dock'),
              destinations: destinations,
              selectedIndex: selectedIndex,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepAliveShellPage extends StatefulWidget {
  const _KeepAliveShellPage({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_KeepAliveShellPage> createState() => _KeepAliveShellPageState();
}

class _KeepAliveShellPageState extends State<_KeepAliveShellPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeepScope(
      child: PageActivityScope(
        isActive: widget.active,
        child: TickerMode(
          enabled: widget.active,
          child: ExcludeFocus(excluding: !widget.active, child: widget.child),
        ),
      ),
    );
  }
}
