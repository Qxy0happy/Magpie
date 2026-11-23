import 'package:material_ui/material_ui.dart';

import 'model.dart';
import 'theme.dart';
import 'widgets.dart';

class PrototypeSwitcher extends StatelessWidget {
  const PrototypeSwitcher({
    super.key,
    required this.state,
    required this.variantIndex,
    required this.variantNames,
    required this.onVariant,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final PrototypeState state;
  final int variantIndex;
  final List<String> variantNames;
  final ValueChanged<int> onVariant;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF1B1D23) : Colors.white).withValues(
            alpha: 0.97,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColorOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => onVariant(variantIndex - 1),
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一个变体',
            ),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PrototypeBadge(compact: true),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          variantNames[variantIndex],
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${variantIndex + 1}/${variantNames.length}',
                        style: mutedStyle(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.summary,
                    overflow: TextOverflow.ellipsis,
                    style: mutedStyle(context),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => onVariant(variantIndex + 1),
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一个变体',
            ),
            const SizedBox(width: 4),
            Container(width: 1, height: 30, color: borderColorOf(context)),
            IconButton(
              onPressed: () => _showState(context),
              icon: const Icon(Icons.data_object),
              tooltip: '查看完整状态',
            ),
            IconButton(
              onPressed: onToggleTheme,
              icon: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              tooltip: '切换主题',
            ),
            IconButton(
              onPressed: () => _showHelp(context),
              icon: const Icon(Icons.help_outline),
              tooltip: '说明',
            ),
          ],
        ),
      ),
    );
  }

  void _showState(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StateInspector(state: state);
      },
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [PrototypeBadge(), SizedBox(width: 8), Text('怎么用这个原型')],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '这是 3 个结构不同的配置界面变体，不是最终视觉稿。它们共用同一份内存状态。',
                    style: mutedStyle(context),
                  ),
                  const SizedBox(height: 10),
                  _helpRow(
                    context,
                    '切换变体',
                    '底部栏左右箭头、键盘 1 / 2 / 3，或启动时 --dart-define=PROTOTYPE_VARIANT=b。',
                  ),
                  _helpRow(context, '比较什么', '导航、信息层级、主要操作位置；先不要纠结配色和圆角。'),
                  _helpRow(
                    context,
                    'Linux 差异',
                    'portal 选源、KDE 全局热键、Flatpak 更新、无触控助手等已在界面中标注。',
                  ),
                  _helpRow(
                    context,
                    '反馈方式',
                    '告诉我要 A 的导航 + B 的工作台 + C 的向导步骤，或指出某项放错了位置。',
                  ),
                  _helpRow(context, '状态', '底部栏的状态按钮会显示完整内存状态；切换变体不会清空状态。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Widget _helpRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(label, style: labelStyle(context))),
          Expanded(child: Text(value, style: mutedStyle(context))),
        ],
      ),
    );
  }
}

class StateInspector extends StatelessWidget {
  const StateInspector({super.key, required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: panelColorOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColorOf(context)),
        ),
        child: AnimatedBuilder(
          animation: state,
          builder: (BuildContext context, Widget? child) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const PrototypeBadge(),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '完整状态',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                  Text('原型状态仅存在于内存；切换变体不会清空。', style: mutedStyle(context)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _stateItem(context, '当前配置', state.profile.name),
                      _stateItem(context, '缩放模式', state.scalingMode),
                      _stateItem(
                        context,
                        '倍率',
                        '${state.scale.toStringAsFixed(1)}×',
                      ),
                      _stateItem(context, '帧率', '${state.frameRate} fps'),
                      _stateItem(context, '捕获', state.captureMethod),
                      _stateItem(context, '输出', state.output),
                      _stateItem(context, '全屏热键', state.fullscreenHotkey),
                      _stateItem(context, '窗口热键', state.windowedHotkey),
                      _stateItem(context, '截图热键', state.screenshotHotkey),
                      _stateItem(context, '计时器', state.timer),
                      _stateItem(
                        context,
                        '光标缩放',
                        state.cursorScaling ? '开' : '关',
                      ),
                      _stateItem(
                        context,
                        '帧率限制',
                        state.frameRateLimiter ? '开' : '关',
                      ),
                      _stateItem(
                        context,
                        '自动隐藏光标',
                        state.autoHideCursor ? '开' : '关',
                      ),
                      _stateItem(context, '覆盖层', state.showOverlay ? '开' : '关'),
                      _stateItem(
                        context,
                        '窗口模式',
                        state.windowedMode ? '开' : '关',
                      ),
                      _stateItem(context, '正在缩放', state.isScaling ? '是' : '否'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: state.reset,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('重置状态'),
                      ),
                      const SizedBox(width: 10),
                      Text('关闭面板后继续切换变体', style: mutedStyle(context)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _stateItem(BuildContext context, String label, String value) {
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: inputFillColorOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColorOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle(context)),
          const SizedBox(height: 3),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
