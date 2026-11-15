import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../models/vault_models.dart';
import '../../state/vault_controller.dart';
import '../theme/cipherbook_visual_tokens.dart';

Future<bool> showCipherbookItemEditor({
  required BuildContext context,
  required VaultController controller,
  VaultItem? item,
  String? initialCategoryId,
}) async {
  final saved = await showFloatingDialog<bool>(
    context: context,
    child: _CipherbookItemEditor(
      controller: controller,
      item: item,
      initialCategoryId: initialCategoryId,
    ),
  );
  return saved ?? false;
}

class _CipherbookItemEditor extends StatefulWidget {
  const _CipherbookItemEditor({
    required this.controller,
    required this.item,
    required this.initialCategoryId,
  });

  final VaultController controller;
  final VaultItem? item;
  final String? initialCategoryId;

  @override
  State<_CipherbookItemEditor> createState() => _CipherbookItemEditorState();
}

class _CipherbookItemEditorState extends State<_CipherbookItemEditor> {
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;
  late String? _selectedCategoryId;
  bool _obscurePassword = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleController = TextEditingController(text: item?.title ?? '');
    _usernameController = TextEditingController(text: item?.username ?? '');
    _passwordController = TextEditingController(text: item?.password ?? '');
    _urlController = TextEditingController(text: item?.url ?? '');
    _notesController = TextEditingController(text: item?.notes ?? '');
    final candidateCategoryId =
        widget.initialCategoryId ??
        (item == null || item.folder.isEmpty ? null : item.folder);
    _selectedCategoryId =
        candidateCategoryId != null &&
            candidateCategoryId.isNotEmpty &&
            widget.controller.vaultData.categoryById(candidateCategoryId) !=
                null
        ? candidateCategoryId
        : null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - viewInsets - 32;
    final maxHeight = math.min(680.0, math.max(260.0, availableHeight));
    final categories = widget.controller.vaultData.categories;
    final colorScheme = context.colorScheme;

    return AnimatedPadding(
      duration: Duration.zero,
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
            child: Card(
              key: const ValueKey('prism-password-editor'),
              inert: true,
              shape: AppShape.all(
                CipherbookVisualTokens.radiusPanel,
              ).copyWith(side: CipherbookVisualTokens.strongBorderSide),
              child: FilledInputTheme(
                borderRadius: CipherbookVisualTokens.controlRadius,
                fillColor: CipherbookVisualTokens.surfaceRaised,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    CipherbookVisualTokens.space24,
                    CipherbookVisualTokens.space20,
                    CipherbookVisualTokens.space24,
                    CipherbookVisualTokens.space20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.item == null ? '新增密码' : '编辑密码',
                              style: AppTextStyle.headline.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            tooltip: '关闭',
                            icon: const GlyphIcon(Glyphs.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('prism-password-editor-title'),
                        controller: _titleController,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: '名称'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('prism-password-editor-username'),
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: '账号'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('prism-password-editor-password'),
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: '密码',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                            icon: GlyphIcon(
                              _obscurePassword ? Glyphs.eye : Glyphs.eyeOff,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('prism-password-editor-url'),
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: '网址'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('prism-password-editor-notes'),
                        controller: _notesController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(hintText: '备注'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '分类',
                        style: AppTextStyle.subheadline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: CipherbookVisualTokens.space4,
                        runSpacing: CipherbookVisualTokens.space4,
                        children: [
                          _CategoryChoice(
                            key: const ValueKey(
                              'prism-password-editor-category-none',
                            ),
                            label: '未分类',
                            selected: _selectedCategoryId == null,
                            onPressed: () {
                              setState(() {
                                _selectedCategoryId = null;
                              });
                            },
                          ),
                          for (final category in categories)
                            _CategoryChoice(
                              key: ValueKey(
                                'prism-password-editor-category-${category.id}',
                              ),
                              label: category.name,
                              selected: _selectedCategoryId == category.id,
                              onPressed: () {
                                setState(() {
                                  _selectedCategoryId = category.id;
                                });
                              },
                            ),
                        ],
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: 14),
                        Text(
                          error,
                          style: AppTextStyle.footnote
                              .of(context)
                              .copyWith(color: colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const ValueKey('prism-password-editor-save'),
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? '正在保存…' : '保存'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _error = '请输入名称。';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final item = widget.item;
    final result = await widget.controller.addOrUpdateItem(
      id: item?.id,
      title: title,
      username: _usernameController.text,
      password: _passwordController.text,
      url: _urlController.text,
      notes: _notesController.text,
      tags: item?.tags ?? const [],
      totpSecret: item?.totpSecret,
      categoryId: _selectedCategoryId ?? '',
    );
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = result.error?.toString() ?? '保存失败。';
    });
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
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
    return PressSurface(
      fill: selected ? CipherbookVisualTokens.accentSoft : Colors.transparent,
      shape: AppShape.all(CipherbookVisualTokens.radiusControl),
      side: selected
          ? CipherbookVisualTokens.accentBorderSide
          : CipherbookVisualTokens.borderSide,
      foreground: selected ? colorScheme.primary : colorScheme.onSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: CipherbookVisualTokens.space12,
        vertical: CipherbookVisualTokens.space8,
      ),
      minimum: const BoxConstraints(
        minHeight: CipherbookVisualTokens.controlHeight,
      ),
      tapTarget: Size.zero,
      selected: selected,
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.footnote.of(context, emphasized: selected),
      ),
    );
  }
}
