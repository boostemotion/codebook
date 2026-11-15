import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/vault_models.dart';
import '../../state/vault_controller.dart';
import '../dashboard/dashboard_metrics.dart';
import '../theme/cipherbook_glyphs.dart';
import '../theme/cipherbook_visual_tokens.dart';

const _inlineCopyFeedbackDuration = Duration(milliseconds: 1800);
const _copySuccessLabel = '已复制';
const _headerCopyLabelWidth = 60.0;
const _shortcutCopyLabelWidth = 44.0;

enum _CopyFeedbackTarget {
  headerPassword,
  username,
  password,
  url,
  totp,
  toolbarUsername,
  toolbarPassword,
}

class PasswordInspector extends StatefulWidget {
  const PasswordInspector({
    super.key,
    required this.controller,
    required this.item,
    required this.cardKey,
    required this.keyPrefix,
    required this.onEdit,
    required this.onSelectItem,
    this.onMoved,
  });

  final VaultController controller;
  final VaultItem item;
  final Key cardKey;
  final String keyPrefix;
  final VoidCallback? onEdit;
  final ValueChanged<VaultItem> onSelectItem;
  final VoidCallback? onMoved;

  @override
  State<PasswordInspector> createState() => _PasswordInspectorState();
}

class _PasswordInspectorState extends State<PasswordInspector> {
  final ScrollController _scrollController = ScrollController();
  bool _passwordVisible = false;
  bool _totpVisible = false;
  bool _favoriteBusy = false;
  bool _moveBusy = false;
  String? _feedback;
  bool _feedbackIsError = false;
  Timer? _feedbackTimer;
  _CopyFeedbackTarget? _activeCopyFeedback;
  Timer? _inlineCopyTimer;

  String get _prefix => widget.keyPrefix;

  @override
  void didUpdateWidget(PasswordInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _passwordVisible = false;
      _totpVisible = false;
      _favoriteBusy = false;
      _moveBusy = false;
      _feedbackTimer?.cancel();
      _inlineCopyTimer?.cancel();
      _feedback = null;
      _feedbackIsError = false;
      _activeCopyFeedback = null;
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _inlineCopyTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _copy(String value, _CopyFeedbackTarget target) async {
    final result = await widget.controller.copySecret(value);
    if (!mounted) {
      return;
    }
    if (!result.succeeded) {
      _showFeedback(result.error?.toString() ?? '复制失败。', isError: true);
      return;
    }
    _showInlineCopyFeedback(target);
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) {
      return;
    }
    final favorite = !widget.item.favorite;
    setState(() {
      _favoriteBusy = true;
    });
    try {
      final result = await widget.controller.setItemFavorite(
        itemId: widget.item.id,
        favorite: favorite,
      );
      if (!mounted) {
        return;
      }
      if (!result.succeeded) {
        _showFeedback(result.error?.toString() ?? '更新收藏状态失败。', isError: true);
        return;
      }
      _showFeedback(favorite ? '已收藏。' : '已取消收藏。');
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy = false;
        });
      }
    }
  }

  Future<void> _openWebsite() async {
    final uri = _normalizedWebsiteUri(widget.item.url);
    if (uri == null) {
      _showFeedback('网址格式无效。', isError: true);
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) {
        return;
      }
      if (!opened) {
        _showFeedback('无法打开网址。', isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showFeedback('无法打开网址。', isError: true);
      }
    }
  }

  Future<void> _showMovePicker() async {
    final categories = widget.controller.vaultData.categories.toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    final categoryId = await showFloatingDialog<String>(
      context: context,
      child: Builder(
        builder: (dialogContext) {
          return AlertDialog(
            key: ValueKey('$_prefix-move-picker'),
            title: '移动分类',
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
            ],
            child: SizedBox(
              width: 320,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _MoveChoiceRow(
                      key: ValueKey('$_prefix-move-uncategorized'),
                      label: '未分类',
                      selected: widget.item.folder.isEmpty,
                      onPressed: () => Navigator.of(dialogContext).pop(''),
                    ),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: CipherbookVisualTokens.space4,
                        ),
                        child: _MoveChoiceRow(
                          key: ValueKey('$_prefix-move-${category.id}'),
                          label: category.name,
                          selected: widget.item.folder == category.id,
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(category.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (categoryId == null || !mounted) {
      return;
    }
    await _moveTo(categoryId);
  }

  Future<void> _moveTo(String categoryId) async {
    if (_moveBusy) {
      return;
    }
    setState(() {
      _moveBusy = true;
      _feedback = null;
    });
    final result = await widget.controller.assignItemToCategory(
      itemId: widget.item.id,
      categoryId: categoryId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _moveBusy = false;
    });
    if (!result.succeeded) {
      _showFeedback(result.error?.toString() ?? '移动失败。', isError: true);
      return;
    }
    _showFeedback('分类已更新');
    widget.onMoved?.call();
  }

  void _showFeedback(String message, {bool isError = false}) {
    _feedbackTimer?.cancel();
    _inlineCopyTimer?.cancel();
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
      _activeCopyFeedback = null;
    });
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _feedback = null;
        });
      }
    });
  }

  void _showInlineCopyFeedback(_CopyFeedbackTarget target) {
    _feedbackTimer?.cancel();
    _inlineCopyTimer?.cancel();
    setState(() {
      _feedback = null;
      _feedbackIsError = false;
      _activeCopyFeedback = target;
    });
    _inlineCopyTimer = Timer(_inlineCopyFeedbackDuration, () {
      if (mounted) {
        setState(() {
          if (_activeCopyFeedback == target) {
            _activeCopyFeedback = null;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final data = widget.controller.vaultData;
    final metrics = DashboardMetrics.fromVaultData(data);
    final categoryName = data.categoryById(item.folder)?.name ?? '未分类';
    final isWeak = metrics.weakItems.any(
      (candidate) => candidate.id == item.id,
    );
    final repeatedGroup = metrics.repeatedGroups
        .where(
          (group) => group.items.any((candidate) => candidate.id == item.id),
        )
        .firstOrNull;
    final hasTotp = (item.totpSecret ?? '').trim().isNotEmpty;
    final colorScheme = context.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideColumns =
            constraints.maxWidth >= 620 &&
            MediaQuery.sizeOf(context).width >= 1200;
        final body = _buildBody(
          context,
          categoryName: categoryName,
          hasTotp: hasTotp,
          isWeak: isWeak,
          repeatedCount: repeatedGroup?.items.length,
          wideColumns: wideColumns,
        );
        final surface = Column(
          key: widget.cardKey,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, categoryName: categoryName),
            SizedBox(
              height: 1,
              child: ColoredBox(color: colorScheme.outlineVariant),
            ),
            Expanded(child: body),
          ],
        );
        if (!constraints.hasBoundedHeight) {
          return surface;
        }
        return SizedBox(height: constraints.maxHeight, child: surface);
      },
    );
  }

  Widget _buildHeader(BuildContext context, {required String categoryName}) {
    final item = widget.item;
    final colorScheme = context.colorScheme;
    final title = item.title.trim().isEmpty ? '未命名' : item.title.trim();
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InspectorAvatar(title: title),
        const SizedBox(width: CipherbookVisualTokens.space16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: ValueKey('$_prefix-title'),
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.title2.of(context, emphasized: true),
              ),
              const SizedBox(height: CipherbookVisualTokens.space4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: CipherbookVisualTokens.space8,
                runSpacing: CipherbookVisualTokens.space4,
                children: [
                  _buildCategoryEntry(context, categoryName),
                  const _MetaDot(),
                  _MetaText(_kindLabel(item.kind)),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final favoriteAction = _favoriteBusy ? null : _toggleFavorite;
    final headerCopyActive =
        _activeCopyFeedback == _CopyFeedbackTarget.headerPassword;
    final copyPasswordAction = item.password.isEmpty
        ? null
        : () => _copy(item.password, _CopyFeedbackTarget.headerPassword);
    final editAction = _favoriteBusy || _moveBusy ? null : widget.onEdit;
    final actions = <Widget>[
      OutlinedButton.icon(
        key: ValueKey('$_prefix-favorite'),
        onPressed: favoriteAction,
        icon: GlyphIcon(
          VaultGlyphs.favorite,
          size: 16,
          color: item.favorite ? colorScheme.primary : null,
        ),
        label: Text(item.favorite ? '取消收藏' : '收藏'),
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colorScheme.onSurface),
          side: const WidgetStatePropertyAll(CipherbookVisualTokens.borderSide),
          minimumSize: const Size(0, CipherbookVisualTokens.controlHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: CipherbookVisualTokens.space12,
          ),
          tapTargetSize: TapTargetSize.shrinkWrap,
        ),
      ),
      _InlineCopyFeedback(
        key: ValueKey('$_prefix-copy-password'),
        feedbackKey: ValueKey('$_prefix-inline-copy-header-password'),
        active: headerCopyActive,
        semanticsMessage: '已复制密码',
        child: FilledButton.icon(
          onPressed: copyPasswordAction,
          icon: GlyphIcon(
            headerCopyActive ? Glyphs.check : Glyphs.copy,
            size: 16,
            color: headerCopyActive ? colorScheme.onPrimary : null,
          ),
          label: _FixedCopyLabel(
            key: ValueKey('$_prefix-copy-password-label'),
            active: headerCopyActive,
            activeColor: colorScheme.onPrimary,
            normalLabel: '复制密码',
            width: _headerCopyLabelWidth,
          ),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colorScheme.surfaceContainerHighest;
              }
              return headerCopyActive
                  ? CipherbookVisualTokens.success
                  : CipherbookVisualTokens.accent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colorScheme.onSurfaceVariant;
              }
              return colorScheme.onPrimary;
            }),
            minimumSize: const Size(0, CipherbookVisualTokens.controlHeight),
            tapTargetSize: TapTargetSize.shrinkWrap,
          ),
        ),
      ),
      OutlinedButton.icon(
        key: ValueKey('$_prefix-edit'),
        onPressed: editAction,
        icon: const GlyphIcon(VaultGlyphs.edit, size: 16),
        label: const Text('编辑'),
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colorScheme.onSurface),
          side: const WidgetStatePropertyAll(CipherbookVisualTokens.borderSide),
          minimumSize: const Size(0, CipherbookVisualTokens.controlHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: CipherbookVisualTokens.space12,
          ),
          tapTargetSize: TapTargetSize.shrinkWrap,
        ),
      ),
    ];

    return Padding(
      key: ValueKey('$_prefix-header'),
      padding: const EdgeInsets.fromLTRB(
        CipherbookVisualTokens.space20,
        CipherbookVisualTokens.space20,
        CipherbookVisualTokens.space20,
        CipherbookVisualTokens.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: CipherbookVisualTokens.space12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        key: ValueKey('$_prefix-header-actions'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HeaderIconAction(
                            key: ValueKey('$_prefix-favorite'),
                            tooltip: item.favorite ? '取消收藏' : '收藏',
                            foreground: item.favorite
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            icon: GlyphIcon(VaultGlyphs.favorite, size: 18),
                            onPressed: favoriteAction,
                          ),
                          const SizedBox(width: CipherbookVisualTokens.space8),
                          _InlineCopyFeedback(
                            key: ValueKey('$_prefix-copy-password'),
                            feedbackKey: ValueKey(
                              '$_prefix-inline-copy-header-password',
                            ),
                            active: headerCopyActive,
                            semanticsMessage: '已复制密码',
                            child: _HeaderIconAction(
                              tooltip: '复制密码',
                              primary: true,
                              background: headerCopyActive
                                  ? CipherbookVisualTokens.success
                                  : CipherbookVisualTokens.accent,
                              icon: headerCopyActive
                                  ? GlyphIcon(
                                      Glyphs.check,
                                      key: ValueKey(
                                        '$_prefix-copy-password-compact-check',
                                      ),
                                      size: 26,
                                      color: colorScheme.onPrimary,
                                    )
                                  : const GlyphIcon(Glyphs.copy, size: 18),
                              onPressed: copyPasswordAction,
                            ),
                          ),
                          const SizedBox(width: CipherbookVisualTokens.space8),
                          _HeaderIconAction(
                            key: ValueKey('$_prefix-edit'),
                            tooltip: '编辑',
                            foreground: colorScheme.onSurface,
                            icon: const GlyphIcon(VaultGlyphs.edit, size: 18),
                            onPressed: editAction,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: CipherbookVisualTokens.space16),
                  Wrap(
                    spacing: CipherbookVisualTokens.space8,
                    runSpacing: CipherbookVisualTokens.space8,
                    children: actions,
                  ),
                ],
              );
            },
          ),
          if (_feedback case final feedback?) ...[
            const SizedBox(height: CipherbookVisualTokens.space8),
            Semantics(
              liveRegion: true,
              child: Text(
                feedback,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: _feedbackIsError
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryEntry(BuildContext context, String categoryName) {
    final colorScheme = context.colorScheme;
    final style = AppTextStyle.footnote
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant);
    return SizedBox(
      height: 44,
      child: PressSurface(
        key: ValueKey('$_prefix-move'),
        fill: const Color(0x00000000),
        shape: AppShape.full,
        foreground: colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(
          horizontal: CipherbookVisualTokens.space8,
        ),
        minimum: const BoxConstraints(minHeight: 44),
        tapTarget: Size.zero,
        onPressed: _moveBusy ? null : _showMovePicker,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              categoryName,
              key: ValueKey('$_prefix-category'),
              style: style,
            ),
            const SizedBox(width: CipherbookVisualTokens.space4),
            Text('移动', style: style),
            const SizedBox(width: 2),
            GlyphIcon(
              Glyphs.chevronForward,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required String categoryName,
    required bool hasTotp,
    required bool isWeak,
    required int? repeatedCount,
    required bool wideColumns,
  }) {
    final item = widget.item;
    final usernameCopyActive =
        _activeCopyFeedback == _CopyFeedbackTarget.username;
    final passwordCopyActive =
        _activeCopyFeedback == _CopyFeedbackTarget.password;
    final urlCopyActive = _activeCopyFeedback == _CopyFeedbackTarget.url;
    final totpCopyActive = _activeCopyFeedback == _CopyFeedbackTarget.totp;
    final credentialFields = <Widget>[
      if (item.username.trim().isNotEmpty)
        _CredentialField(
          key: ValueKey('$_prefix-credential-username'),
          label: '账号',
          feedbackActive: usernameCopyActive,
          value: item.username,
          valueKey: ValueKey('$_prefix-username-value'),
          actions: <Widget>[
            _InlineCopyFeedback(
              key: ValueKey('$_prefix-copy-username'),
              feedbackKey: ValueKey('$_prefix-inline-copy-username'),
              active: usernameCopyActive,
              semanticsMessage: '已复制账号',
              child: _InspectorIconAction(
                tooltip: '复制账号',
                icon: GlyphIcon(
                  usernameCopyActive ? Glyphs.check : Glyphs.copy,
                  size: 17,
                  color: usernameCopyActive
                      ? CipherbookVisualTokens.success
                      : null,
                ),
                onPressed: () =>
                    _copy(item.username, _CopyFeedbackTarget.username),
              ),
            ),
          ],
        ),
      _CredentialField(
        key: ValueKey('$_prefix-credential-password'),
        label: '密码',
        feedbackActive: passwordCopyActive,
        value: item.password.isEmpty
            ? '未设置'
            : _passwordVisible
            ? item.password
            : '••••••••••••',
        valueKey: ValueKey('$_prefix-password-value'),
        concealed: !_passwordVisible && item.password.isNotEmpty,
        actions: <Widget>[
          if (item.password.isNotEmpty)
            _InspectorIconAction(
              key: ValueKey('$_prefix-password-visibility'),
              tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
              icon: GlyphIcon(
                _passwordVisible ? Glyphs.eyeOff : Glyphs.eye,
                size: 17,
              ),
              onPressed: () {
                setState(() {
                  _passwordVisible = !_passwordVisible;
                });
              },
            ),
          if (item.password.isNotEmpty)
            _InlineCopyFeedback(
              key: ValueKey('$_prefix-copy-password-field'),
              feedbackKey: ValueKey('$_prefix-inline-copy-password'),
              active: passwordCopyActive,
              semanticsMessage: '已复制密码',
              child: _InspectorIconAction(
                tooltip: '复制密码',
                icon: GlyphIcon(
                  passwordCopyActive ? Glyphs.check : Glyphs.copy,
                  size: 17,
                  color: passwordCopyActive
                      ? CipherbookVisualTokens.success
                      : null,
                ),
                onPressed: () =>
                    _copy(item.password, _CopyFeedbackTarget.password),
              ),
            ),
        ],
      ),
      if (item.url.trim().isNotEmpty)
        _CredentialField(
          key: ValueKey('$_prefix-credential-url'),
          label: '网址',
          feedbackActive: urlCopyActive,
          value: item.url,
          valueKey: ValueKey('$_prefix-url-value'),
          actions: <Widget>[
            _InspectorIconAction(
              key: ValueKey('$_prefix-open-url'),
              tooltip: '打开网址',
              icon: const GlyphIcon(Glyphs.chevronForward, size: 17),
              onPressed: _openWebsite,
            ),
            _InlineCopyFeedback(
              key: ValueKey('$_prefix-copy-url'),
              feedbackKey: ValueKey('$_prefix-inline-copy-url'),
              active: urlCopyActive,
              semanticsMessage: '已复制网址',
              child: _InspectorIconAction(
                tooltip: '复制网址',
                icon: GlyphIcon(
                  urlCopyActive ? Glyphs.check : Glyphs.copy,
                  size: 17,
                  color: urlCopyActive ? CipherbookVisualTokens.success : null,
                ),
                onPressed: () => _copy(item.url, _CopyFeedbackTarget.url),
              ),
            ),
          ],
        ),
      if (hasTotp)
        _CredentialField(
          key: ValueKey('$_prefix-credential-totp'),
          label: '动态验证码',
          feedbackActive: totpCopyActive,
          value: _totpVisible ? item.totpSecret! : '••••••••••••',
          valueKey: ValueKey('$_prefix-totp-value'),
          concealed: !_totpVisible,
          actions: <Widget>[
            _InspectorIconAction(
              key: ValueKey('$_prefix-totp-visibility'),
              tooltip: _totpVisible ? '隐藏 TOTP 密钥' : '显示 TOTP 密钥',
              icon: GlyphIcon(
                _totpVisible ? Glyphs.eyeOff : Glyphs.eye,
                size: 17,
              ),
              onPressed: () {
                setState(() {
                  _totpVisible = !_totpVisible;
                });
              },
            ),
            _InlineCopyFeedback(
              key: ValueKey('$_prefix-copy-totp'),
              feedbackKey: ValueKey('$_prefix-inline-copy-totp'),
              active: totpCopyActive,
              semanticsMessage: '已复制 TOTP 密钥',
              child: _InspectorIconAction(
                tooltip: '复制 TOTP 密钥',
                icon: GlyphIcon(
                  totpCopyActive ? Glyphs.check : Glyphs.copy,
                  size: 17,
                  color: totpCopyActive ? CipherbookVisualTokens.success : null,
                ),
                onPressed: () =>
                    _copy(item.totpSecret!, _CopyFeedbackTarget.totp),
              ),
            ),
          ],
        ),
    ];

    final credentials = Column(
      key: ValueKey('$_prefix-credentials-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '登录信息',
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
        const SizedBox(height: CipherbookVisualTokens.space8),
        _CredentialGrid(
          key: ValueKey('$_prefix-credential-grid'),
          fields: credentialFields,
          columns: wideColumns ? 2 : 1,
        ),
      ],
    );
    final notes = _DocumentNotes(
      key: ValueKey('$_prefix-notes-section'),
      notes: item.notes,
      contentKey: ValueKey('$_prefix-notes-content'),
      emptyStateKey: ValueKey('$_prefix-notes-empty'),
    );
    final strengthValue = item.password.isEmpty
        ? '未设置'
        : isWeak
        ? '需要改进'
        : '通过基础检查';
    final strengthTone = item.password.isEmpty
        ? _SecurityTone.neutral
        : isWeak
        ? _SecurityTone.warning
        : _SecurityTone.safe;
    final reuseValue = repeatedCount == null ? '未发现重复' : '$repeatedCount 条记录共用';
    final reuseTone = repeatedCount == null
        ? _SecurityTone.safe
        : _SecurityTone.warning;
    final totpValue = hasTotp ? 'TOTP 已配置' : '未配置';
    final totpTone = hasTotp ? _SecurityTone.safe : _SecurityTone.neutral;
    final metadata = _MetadataStrip(
      key: ValueKey('$_prefix-metadata-strip'),
      prefix: _prefix,
      entries: [
        _MetadataEntry(
          keySuffix: 'strength',
          label: '密码强度',
          value: strengthValue,
          tone: strengthTone,
        ),
        _MetadataEntry(
          keySuffix: 'reuse',
          label: '重复使用',
          value: reuseValue,
          tone: reuseTone,
        ),
        _MetadataEntry(
          keySuffix: 'totp',
          label: '双重验证',
          value: totpValue,
          tone: totpTone,
        ),
        _MetadataEntry(
          keySuffix: 'updated',
          label: '更新',
          value: _formatTimestamp(item.updatedAt),
        ),
      ],
    );
    final relatedItems = widget.controller.vaultData.activeItems
        .where(
          (candidate) =>
              candidate.id != item.id && candidate.folder == item.folder,
        )
        .take(4)
        .toList(growable: false);

    final horizontal = wideColumns
        ? CipherbookVisualTokens.space24
        : CipherbookVisualTokens.space16;
    final metadataSection = Column(
      key: ValueKey('$_prefix-metadata-section'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DocumentRule(),
        const SizedBox(height: CipherbookVisualTokens.space16),
        metadata,
      ],
    );
    final document = Column(
      key: ValueKey(
        wideColumns ? '$_prefix-document-content' : '$_prefix-single-column',
      ),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        credentials,
        const SizedBox(height: CipherbookVisualTokens.space20),
        const _DocumentRule(),
        const SizedBox(height: CipherbookVisualTokens.space20),
        notes,
        const SizedBox(height: CipherbookVisualTokens.space20),
        metadataSection,
        if (relatedItems.isNotEmpty) ...[
          const SizedBox(height: CipherbookVisualTokens.space20),
          _RelatedItemsSection(
            key: ValueKey('$_prefix-related-section'),
            prefix: _prefix,
            items: relatedItems,
            wideColumns: wideColumns,
            onSelected: widget.onSelectItem,
          ),
        ],
        const SizedBox(height: CipherbookVisualTokens.space20),
        _buildShortcutStrip(context),
      ],
    );
    final scrollableView = SingleChildScrollView(
      key: ValueKey('$_prefix-scroll'),
      controller: _scrollController,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontal,
          CipherbookVisualTokens.space20,
          horizontal,
          CipherbookVisualTokens.space24,
        ),
        child: document,
      ),
    );

    return Scrollbar(
      key: ValueKey('$_prefix-scrollbar'),
      controller: _scrollController,
      thumbVisibility: MediaQuery.sizeOf(context).width >= 600,
      child: scrollableView,
    );
  }

  Widget _buildShortcutStrip(BuildContext context) {
    final colorScheme = context.colorScheme;
    final item = widget.item;
    final usernameCopyActive =
        _activeCopyFeedback == _CopyFeedbackTarget.toolbarUsername;
    final passwordCopyActive =
        _activeCopyFeedback == _CopyFeedbackTarget.toolbarPassword;
    final actions = <Widget>[
      _InlineCopyFeedback(
        key: ValueKey('$_prefix-shortcut-copy-username'),
        feedbackKey: ValueKey('$_prefix-inline-copy-toolbar-username'),
        active: usernameCopyActive,
        semanticsMessage: '已复制账号',
        child: _ShortcutAction(
          icon: GlyphIcon(
            usernameCopyActive ? Glyphs.check : Glyphs.copy,
            size: 16,
            color: usernameCopyActive ? CipherbookVisualTokens.success : null,
          ),
          label: _FixedCopyLabel(
            key: ValueKey('$_prefix-shortcut-copy-username-label'),
            active: usernameCopyActive,
            activeColor: CipherbookVisualTokens.success,
            normalLabel: '账号',
            width: _shortcutCopyLabelWidth,
          ),
          onPressed: item.username.trim().isEmpty
              ? null
              : () => _copy(item.username, _CopyFeedbackTarget.toolbarUsername),
        ),
      ),
      _InlineCopyFeedback(
        key: ValueKey('$_prefix-shortcut-copy-password'),
        feedbackKey: ValueKey('$_prefix-inline-copy-toolbar-password'),
        active: passwordCopyActive,
        semanticsMessage: '已复制密码',
        child: _ShortcutAction(
          icon: GlyphIcon(
            passwordCopyActive ? Glyphs.check : Glyphs.copy,
            size: 16,
            color: passwordCopyActive ? CipherbookVisualTokens.success : null,
          ),
          label: _FixedCopyLabel(
            key: ValueKey('$_prefix-shortcut-copy-password-label'),
            active: passwordCopyActive,
            activeColor: CipherbookVisualTokens.success,
            normalLabel: '密码',
            width: _shortcutCopyLabelWidth,
          ),
          onPressed: item.password.isEmpty
              ? null
              : () => _copy(item.password, _CopyFeedbackTarget.toolbarPassword),
        ),
      ),
      if (item.url.trim().isNotEmpty)
        _ShortcutAction(
          key: ValueKey('$_prefix-shortcut-open-url'),
          icon: const GlyphIcon(Glyphs.chevronForward, size: 16),
          label: const Text('网址'),
          onPressed: _openWebsite,
        ),
    ];

    return Column(
      key: ValueKey('$_prefix-footer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: ValueKey('$_prefix-toolbar-rule'),
          height: 1,
          child: ColoredBox(color: colorScheme.outlineVariant),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: CipherbookVisualTokens.space8,
          ),
          child: Wrap(
            spacing: CipherbookVisualTokens.space4,
            runSpacing: CipherbookVisualTokens.space4,
            children: actions,
          ),
        ),
      ],
    );
  }
}

class _InlineCopyFeedback extends StatelessWidget {
  const _InlineCopyFeedback({
    super.key,
    required this.feedbackKey,
    required this.active,
    required this.semanticsMessage,
    required this.child,
  });

  final Key feedbackKey;
  final bool active;
  final String semanticsMessage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: feedbackKey,
      container: true,
      liveRegion: active,
      label: active ? semanticsMessage : null,
      child: child,
    );
  }
}

class _FixedCopyLabel extends StatelessWidget {
  const _FixedCopyLabel({
    super.key,
    required this.active,
    required this.normalLabel,
    required this.width,
    this.activeColor,
  });

  final bool active;
  final String normalLabel;
  final double width;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        active ? _copySuccessLabel : normalLabel,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: active && activeColor != null
            ? TextStyle(color: activeColor)
            : null,
      ),
    );
  }
}

class _InspectorAvatar extends StatelessWidget {
  const _InspectorAvatar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final normalized = title.trim();
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colorScheme.secondaryContainer,
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        normalized.isEmpty ? '?' : normalized.characters.first.toUpperCase(),
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(color: context.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyle.footnote
          .of(context)
          .copyWith(color: context.colorScheme.onSurfaceVariant),
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Text(
      '·',
      style: AppTextStyle.footnote
          .of(context)
          .copyWith(color: context.colorScheme.onSurfaceVariant),
    );
  }
}

class _CredentialGrid extends StatelessWidget {
  const _CredentialGrid({
    super.key,
    required this.fields,
    required this.columns,
  });

  final List<Widget> fields;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (columns == 1) {
      return Column(
        children: [
          const _DocumentRule(),
          for (var index = 0; index < fields.length; index++) ...[
            if (index > 0) const _DocumentRule(),
            fields[index],
          ],
          const _DocumentRule(),
        ],
      );
    }

    final rows = <Widget>[];
    for (var index = 0; index < fields.length; index += columns) {
      final cells = <Widget>[];
      for (var column = 0; column < columns; column++) {
        if (column > 0) {
          cells.add(
            SizedBox(
              width: 1,
              child: ColoredBox(color: colorScheme.outlineVariant),
            ),
          );
        }
        final fieldIndex = index + column;
        cells.add(
          Expanded(
            child: fieldIndex < fields.length
                ? fields[fieldIndex]
                : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }

    return Column(
      children: [
        const _DocumentRule(),
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const _DocumentRule(),
          rows[index],
        ],
        const _DocumentRule(),
      ],
    );
  }
}

class _CredentialField extends StatelessWidget {
  const _CredentialField({
    super.key,
    required this.label,
    required this.value,
    required this.valueKey,
    this.actions = const [],
    this.concealed = false,
    this.feedbackActive = false,
  });

  final String label;
  final String value;
  final Key valueKey;
  final List<Widget> actions;
  final bool concealed;
  final bool feedbackActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CipherbookVisualTokens.space12,
        CipherbookVisualTokens.space12,
        CipherbookVisualTokens.space4,
        CipherbookVisualTokens.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    if (feedbackActive) ...[
                      const SizedBox(width: CipherbookVisualTokens.space8),
                      Text(
                        _copySuccessLabel,
                        maxLines: 1,
                        style: AppTextStyle.footnote
                            .of(context, emphasized: true)
                            .copyWith(color: CipherbookVisualTokens.success),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: CipherbookVisualTokens.space4),
                ExcludeSemantics(
                  excluding: concealed,
                  child: Text(
                    key: valueKey,
                    value,
                    maxLines: concealed ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline.of(context),
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            const SizedBox(width: CipherbookVisualTokens.space4),
          ...actions,
        ],
      ),
    );
  }
}

class _DocumentRule extends StatelessWidget {
  const _DocumentRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: ColoredBox(color: context.colorScheme.outlineVariant),
    );
  }
}

class _DocumentNotes extends StatelessWidget {
  const _DocumentNotes({
    super.key,
    required this.notes,
    required this.contentKey,
    required this.emptyStateKey,
  });

  final String notes;
  final Key contentKey;
  final Key emptyStateKey;

  @override
  Widget build(BuildContext context) {
    final normalized = notes.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '备注',
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
        const SizedBox(height: CipherbookVisualTokens.space8),
        if (normalized.isEmpty)
          Text(
            key: emptyStateKey,
            '暂无备注',
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          )
        else
          Text(
            key: contentKey,
            normalized,
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    );
  }
}

class _RelatedItemsSection extends StatelessWidget {
  const _RelatedItemsSection({
    super.key,
    required this.prefix,
    required this.items,
    required this.wideColumns,
    required this.onSelected,
  });

  final String prefix;
  final List<VaultItem> items;
  final bool wideColumns;
  final ValueChanged<VaultItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: ValueKey('$prefix-related-heading'),
          '同分类',
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
        const SizedBox(height: CipherbookVisualTokens.space8),
        if (wideColumns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RelatedItemsColumn(
                  prefix: prefix,
                  items: [
                    for (var index = 0; index < items.length; index += 2)
                      items[index],
                  ],
                  onSelected: onSelected,
                ),
              ),
              const SizedBox(width: CipherbookVisualTokens.space24),
              Expanded(
                child: _RelatedItemsColumn(
                  prefix: prefix,
                  items: [
                    for (var index = 1; index < items.length; index += 2)
                      items[index],
                  ],
                  onSelected: onSelected,
                ),
              ),
            ],
          )
        else
          _RelatedItemsColumn(
            prefix: prefix,
            items: items,
            onSelected: onSelected,
          ),
      ],
    );
  }
}

class _RelatedItemsColumn extends StatelessWidget {
  const _RelatedItemsColumn({
    required this.prefix,
    required this.items,
    required this.onSelected,
  });

  final String prefix;
  final List<VaultItem> items;
  final ValueChanged<VaultItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const _DocumentRule(),
          _RelatedItemRow(
            key: ValueKey('$prefix-related-${items[index].id}'),
            prefix: prefix,
            item: items[index],
            onPressed: () => onSelected(items[index]),
          ),
        ],
      ],
    );
  }
}

class _RelatedItemRow extends StatelessWidget {
  const _RelatedItemRow({
    super.key,
    required this.prefix,
    required this.item,
    required this.onPressed,
  });

  final String prefix;
  final VaultItem item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final title = item.title.trim().isEmpty ? '未命名' : item.title.trim();
    final summary = [
      if (item.username.trim().isNotEmpty) item.username.trim(),
      if (item.url.trim().isNotEmpty)
        item.url.trim().replaceFirst(
          RegExp(r'^https?://', caseSensitive: false),
          '',
        ),
    ].join(' · ');
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.all(CipherbookVisualTokens.radiusControl),
      foreground: colorScheme.onSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: CipherbookVisualTokens.space4,
        vertical: CipherbookVisualTokens.space8,
      ),
      minimum: const BoxConstraints(minHeight: 64),
      tapTarget: Size.zero,
      onPressed: onPressed,
      child: Row(
        children: [
          _InspectorAvatar(title: title),
          const SizedBox(width: CipherbookVisualTokens.space12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key: ValueKey('$prefix-related-title-${item.id}'),
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: CipherbookVisualTokens.space4),
                  Text(
                    key: ValueKey('$prefix-related-summary-${item.id}'),
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CipherbookVisualTokens.space8),
          GlyphIcon(
            Glyphs.chevronForward,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _InspectorIconAction extends StatelessWidget {
  const _InspectorIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: icon,
      style: const ButtonStyle(
        minimumSize: Size.square(CipherbookVisualTokens.controlHeight),
        maximumSize: Size.square(CipherbookVisualTokens.controlHeight),
        tapTargetSize: TapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _HeaderIconAction extends StatelessWidget {
  const _HeaderIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.foreground,
    this.primary = false,
    this.background,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color? foreground;
  final bool primary;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: icon,
      style: ButtonStyle(
        minimumSize: const Size.square(CipherbookVisualTokens.controlHeight),
        maximumSize: const Size.square(CipherbookVisualTokens.controlHeight),
        padding: EdgeInsets.zero,
        tapTargetSize: TapTargetSize.shrinkWrap,
        shape: AppShape.full,
        backgroundColor: primary
            ? WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return colorScheme.surfaceContainerHighest;
                }
                return background ?? colorScheme.primary;
              })
            : null,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurfaceVariant;
          }
          if (primary) {
            return colorScheme.onPrimary;
          }
          return foreground ?? colorScheme.onSurface;
        }),
        side: primary
            ? null
            : WidgetStateProperty.resolveWith((states) {
                return BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? colorScheme.outlineVariant
                      : colorScheme.outline,
                );
              }),
      ),
    );
  }
}

enum _SecurityTone { neutral, safe, warning }

class _MetadataEntry {
  const _MetadataEntry({
    required this.keySuffix,
    required this.label,
    required this.value,
    this.tone = _SecurityTone.neutral,
  });

  final String keySuffix;
  final String label;
  final String value;
  final _SecurityTone tone;
}

class _MetadataStrip extends StatelessWidget {
  const _MetadataStrip({
    super.key,
    required this.prefix,
    required this.entries,
  });

  final String prefix;
  final List<_MetadataEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 620) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Expanded(
                  child: _MetadataItem(
                    key: ValueKey('$prefix-metadata-${entry.keySuffix}'),
                    entry: entry,
                  ),
                ),
            ],
          );
        }

        final itemWidth =
            (constraints.maxWidth - CipherbookVisualTokens.space12) / 2;
        return Wrap(
          spacing: CipherbookVisualTokens.space12,
          runSpacing: CipherbookVisualTokens.space12,
          children: [
            for (final entry in entries)
              SizedBox(
                width: itemWidth,
                child: _MetadataItem(
                  key: ValueKey('$prefix-metadata-${entry.keySuffix}'),
                  entry: entry,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({super.key, required this.entry});

  final _MetadataEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CipherbookVisualTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: CipherbookVisualTokens.space4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  entry.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context, emphasized: true)
                      .copyWith(color: _securityToneColor(context, entry.tone)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _securityToneColor(BuildContext context, _SecurityTone tone) {
  return switch (tone) {
    _SecurityTone.neutral => context.colorScheme.onSurfaceVariant,
    _SecurityTone.safe => CipherbookVisualTokens.success,
    _SecurityTone.warning => CipherbookVisualTokens.warning,
  };
}

class _ShortcutAction extends StatelessWidget {
  const _ShortcutAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final Widget label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: const ButtonStyle(
        minimumSize: Size(0, CipherbookVisualTokens.controlHeight),
        padding: EdgeInsets.symmetric(
          horizontal: CipherbookVisualTokens.space4,
        ),
        tapTargetSize: TapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _MoveChoiceRow extends StatelessWidget {
  const _MoveChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox(
      height: CipherbookVisualTokens.mobileControlHeight,
      child: PressSurface(
        fill: selected
            ? colorScheme.surfaceContainerHighest
            : const Color(0x00000000),
        shape: AppShape.all(CipherbookVisualTokens.radiusControl),
        foreground: colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(
          horizontal: CipherbookVisualTokens.space12,
        ),
        minimum: const BoxConstraints(
          minHeight: CipherbookVisualTokens.mobileControlHeight,
        ),
        tapTarget: Size.zero,
        onPressed: selected ? null : onPressed,
        selected: selected,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.footnote.of(context, emphasized: selected),
        ),
      ),
    );
  }
}

String _kindLabel(VaultItemKind kind) {
  return switch (kind) {
    VaultItemKind.login => '登录密码',
    VaultItemKind.secureNote => '安全笔记',
  };
}

Uri? _normalizedWebsiteUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
