import 'package:material_ui/material_ui.dart';

import '../model.dart';
import '../theme.dart';
import '../widgets.dart';

/// Variant C — a linear setup flow. The user is guided from source selection to
/// a saved profile; advanced settings are folded into the relevant step.
class VariantC extends StatefulWidget {
  const VariantC({super.key, required this.state});

  final PrototypeState state;

  @override
  State<VariantC> createState() => _VariantCState();
}

class _VariantCState extends State<VariantC> {
  static const List<String> _steps = <String>['源窗口', '缩放模式', '参数', '快捷键', '开始'];

  static const List<String> _sourceWindows = <String>[
    '游戏窗口 · 2560×1440',
    '浏览器 · 1920×1080',
    '终端 · 1280×800',
  ];

  int _step = 0;
  String _sourceMode = '启动时选择';
  String _sourceWindow = _sourceWindows.first;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.state.profileDraftName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step.clamp(0, _steps.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(context),
        _buildStepper(context),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStep(context),
                      const SizedBox(height: 18),
                      _buildStepNav(context),
                    ],
                  ),
                ),
              ),
              _buildPreviewSidebar(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: panelColorOf(context),
        border: Border(bottom: BorderSide(color: borderColorOf(context))),
      ),
      child: Row(
        children: [
          const BrandMark(size: 32),
          const SizedBox(width: 10),
          const Text(
            'Magpie',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 10),
          const PrototypeBadge(compact: true),
          const SizedBox(width: 18),
          Text('配置向导', style: mutedStyle(context)),
          const Spacer(),
          const Pill(
            label: 'KWin · Wayland',
            icon: Icons.monitor,
            compact: true,
          ),
          const SizedBox(width: 10),
          Pill(
            label: '第 ${_step + 1} / ${_steps.length} 步',
            color: accentColor,
            compact: true,
          ),
          TextButton(onPressed: () {}, child: const Text('跳过向导')),
        ],
      ),
    );
  }

  Widget _buildStepper(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: panelColorOf(context).withValues(alpha: 0.55),
        border: Border(bottom: BorderSide(color: borderColorOf(context))),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _steps.length; i++)
            Expanded(
              child: _StepItem(
                index: i,
                label: _steps[i],
                active: i == _step,
                completed: i < _step,
                onTap: () => _goTo(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return _buildSourceStep(context);
      case 1:
        return _buildModeStep(context);
      case 2:
        return _buildParamsStep(context);
      case 3:
        return _buildShortcutStep(context);
      default:
        return _buildFinishStep(context);
    }
  }

  Widget _buildSourceStep(BuildContext context) {
    return _StepScaffold(
      step: _step,
      title: '选择源窗口',
      description:
          'Wayland 不允许普通客户端枚举前台窗口。首版支持两种入口：启动时通过 portal 选择，'
          '或先启动覆盖层再选择源窗口。这里展示的是 portal 选择器的模拟。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChoiceCard(
            title: '启动时选择',
            subtitle: '每次开始缩放前，由 KDE 弹出 portal 选择器。',
            selected: _sourceMode == '启动时选择',
            onTap: () => setState(() => _sourceMode = '启动时选择'),
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            title: '运行时选择',
            subtitle: '先显示覆盖层，再从覆盖层选择源窗口；切换窗口更灵活。',
            selected: _sourceMode == '运行时选择',
            onTap: () => setState(() => _sourceMode = '运行时选择'),
          ),
          const SizedBox(height: 18),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(
                        icon: Icons.lock_outline,
                        title: '模拟 portal 选择器',
                        subtitle: 'ScreenCast v6 · 窗口源',
                      ),
                    ),
                    const Pill(
                      label: '一次授权',
                      color: warningColor,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final String window in _sourceWindows) ...[
                  _WindowChoice(
                    title: window,
                    selected: _sourceWindow == window,
                    onTap: () => setState(() => _sourceWindow = window),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          const LinuxNote(
            text:
                '窗口流不携带窗口身份或几何信息；选中后，应用只知道“有一个窗口流”，'
                '不知道用户选了哪个应用。',
            icon: Icons.info_outline,
          ),
        ],
      ),
    );
  }

  Widget _buildModeStep(BuildContext context) {
    final PrototypeState state = widget.state;
    return _StepScaffold(
      step: _step,
      title: '选择缩放模式',
      description: '不同模式的重心不同：兼容性、锐度、动画质量或复古观感。首版保留 MagpieFX/HLSL 源格式。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final ScalingModePreset mode in PrototypeState.scalingModes)
                SizedBox(
                  width: 300,
                  child: Panel(
                    onTap: () => state.setScalingMode(mode.name),
                    border: state.scalingMode == mode.name
                        ? accentColor.withValues(alpha: 0.5)
                        : null,
                    color: state.scalingMode == mode.name
                        ? accentColor.withValues(alpha: 0.06)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: violetColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: violetColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                mode.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (state.scalingMode == mode.name)
                              const Pill(
                                label: '已选择',
                                color: successColor,
                                compact: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(mode.description, style: mutedStyle(context)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Pill(
                              label: mode.tag,
                              color: violetColor,
                              compact: true,
                            ),
                            const SizedBox(width: 6),
                            Pill(
                              label: '负载 ${mode.cost}',
                              color: warningColor,
                              compact: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const LinuxNote(
            text:
                '效果参数与 MagpieFX 文件在后续步骤中配置；首版只验证内置效果，'
                '自定义效果目录位于 Flatpak 沙盒。',
            icon: Icons.developer_board,
          ),
        ],
      ),
    );
  }

  Widget _buildParamsStep(BuildContext context) {
    final PrototypeState state = widget.state;
    return _StepScaffold(
      step: _step,
      title: '调整参数',
      description: '这些参数会写入当前配置。原型只保存内存状态，不写入配置文件。',
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(icon: Icons.tune, title: '缩放与帧率'),
            const Divider(height: 22),
            LabeledSlider(
              label: '缩放倍率',
              valueLabel: '${state.scale.toStringAsFixed(1)}×',
              value: state.scale,
              min: 1,
              max: 3,
              divisions: 20,
              onChanged: state.setScale,
              hint: '全屏模式会按输出尺寸等比缩放；窗口模式使用初始倍率。',
            ),
            const SizedBox(height: 8),
            LabeledDropdown<int>(
              label: '帧率上限',
              value: state.frameRate,
              items: PrototypeState.frameRates,
              labelOf: (int value) => '$value fps',
              onChanged: (int? value) {
                if (value != null) {
                  state.setFrameRate(value);
                }
              },
            ),
            const SizedBox(height: 8),
            ToggleRow(
              title: '光标缩放',
              subtitle: '按倍率放大光标',
              value: state.cursorScaling,
              onChanged: (bool value) =>
                  state.update(() => state.cursorScaling = value),
            ),
            ToggleRow(
              title: '帧率限制',
              subtitle: '限制输出帧率，降低 GPU 占用',
              value: state.frameRateLimiter,
              onChanged: (bool value) =>
                  state.update(() => state.frameRateLimiter = value),
            ),
            ToggleRow(
              title: '自动隐藏光标',
              subtitle: '静止一段时间后隐藏光标',
              value: state.autoHideCursor,
              onChanged: (bool value) =>
                  state.update(() => state.autoHideCursor = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutStep(BuildContext context) {
    final PrototypeState state = widget.state;
    return _StepScaffold(
      step: _step,
      title: '快捷键与输出',
      description:
          'Linux 下全局热键通过 GlobalShortcuts portal 注册；如果 KDE 拒绝绑定，界面会显式提示。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.keyboard,
                  title: '快捷键',
                  subtitle: '点击右侧按钮可循环示例快捷键',
                ),
                const Divider(height: 22),
                HotkeyRow(
                  icon: Icons.fullscreen,
                  title: '全屏缩放',
                  value: state.fullscreenHotkey,
                  onTap: () => state.update(
                    () => state.fullscreenHotkey = nextHotkey(
                      state.fullscreenHotkey,
                    ),
                  ),
                ),
                HotkeyRow(
                  icon: Icons.crop_free,
                  title: '窗口模式缩放',
                  value: state.windowedHotkey,
                  onTap: () => state.update(
                    () =>
                        state.windowedHotkey = nextHotkey(state.windowedHotkey),
                  ),
                ),
                HotkeyRow(
                  icon: Icons.screenshot_monitor,
                  title: '截图',
                  value: state.screenshotHotkey,
                  onTap: () => state.update(
                    () => state.screenshotHotkey = nextHotkey(
                      state.screenshotHotkey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(icon: Icons.monitor, title: '输出与捕获'),
                const Divider(height: 22),
                LabeledDropdown<String>(
                  label: '输出',
                  value: state.output,
                  items: PrototypeState.outputs,
                  labelOf: (String value) => value,
                  onChanged: (String? value) {
                    if (value != null) {
                      state.update(() => state.output = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                LabeledDropdown<String>(
                  label: '捕获方式',
                  value: state.captureMethod,
                  items: PrototypeState.captureMethods,
                  labelOf: (String value) => value,
                  onChanged: (String? value) {
                    if (value != null) {
                      state.update(() => state.captureMethod = value);
                    }
                  },
                  hint: '首版只支持 portal；PipeWire 直连是宿主客户端的实验路径。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishStep(BuildContext context) {
    final PrototypeState state = widget.state;
    return _StepScaffold(
      step: _step,
      title: '确认并开始',
      description: '检查配置，保存为配置文件，或直接开始一次缩放。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.checklist,
                  title: '配置摘要',
                  subtitle: '来自前面步骤的内存状态',
                ),
                const Divider(height: 22),
                _SummaryRow(label: '源窗口', value: _sourceWindow),
                _SummaryRow(label: '选择方式', value: _sourceMode),
                _SummaryRow(label: '缩放模式', value: state.scalingMode),
                _SummaryRow(
                  label: '倍率',
                  value: '${state.scale.toStringAsFixed(1)}×',
                ),
                _SummaryRow(label: '帧率', value: '${state.frameRate} fps'),
                _SummaryRow(label: '捕获', value: state.captureMethod),
                _SummaryRow(label: '输出', value: state.output),
                _SummaryRow(label: '全屏热键', value: state.fullscreenHotkey),
                _SummaryRow(label: '窗口热键', value: state.windowedHotkey),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(icon: Icons.save_outlined, title: '保存为配置'),
                const SizedBox(height: 10),
                ToggleRow(
                  title: '保存到配置文件',
                  subtitle: '原型不会写入磁盘；真实实现会写入 XDG 配置目录。',
                  value: state.saveAsProfile,
                  onChanged: (bool value) =>
                      state.update(() => state.saveAsProfile = value),
                ),
                if (state.saveAsProfile) ...[
                  const SizedBox(height: 8),
                  Text('配置名称', style: labelStyle(context)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    onChanged: (String value) =>
                        state.update(() => state.profileDraftName = value),
                    decoration: const InputDecoration(
                      hintText: '例如：游戏 · 1440p',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: state.toggleScaling,
            icon: Icon(
              state.isScaling ? Icons.stop_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(state.isScaling ? '停止缩放' : '开始缩放'),
          ),
          const SizedBox(height: 8),
          Text(
            '开始后，KDE 会请求 portal 授权；覆盖层由原生 Vulkan 渲染，Flutter 仅负责这个配置窗口。',
            style: mutedStyle(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStepNav(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _step == 0 ? null : () => _goTo(_step - 1),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('上一步'),
        ),
        const Spacer(),
        Text('${_step + 1} / ${_steps.length}', style: mutedStyle(context)),
        const SizedBox(width: 12),
        if (_step < _steps.length - 1)
          FilledButton.icon(
            onPressed: () => _goTo(_step + 1),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('下一步'),
          )
        else
          FilledButton.icon(
            onPressed: widget.state.toggleScaling,
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('开始缩放'),
          ),
      ],
    );
  }

  Widget _buildPreviewSidebar(BuildContext context) {
    final PrototypeState state = widget.state;
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: panelColorOf(context),
        border: Border(left: BorderSide(color: borderColorOf(context))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MockWindowPreview(
              title: '源窗口 · ${_sourceWindow.split(' · ').first}',
              badge: state.isScaling ? '已授权' : '预览',
              scaled: state.isScaling,
              scale: state.scale,
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    icon: Icons.lock_outline,
                    title: 'Portal 状态',
                  ),
                  const SizedBox(height: 10),
                  _StatusLine(label: 'ScreenCast', value: 'v6 · 窗口源', ok: true),
                  _StatusLine(label: '源窗口', value: _sourceWindow, ok: true),
                  _StatusLine(label: '授权', value: '一次性 · 可恢复', ok: false),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(icon: Icons.terminal, title: 'Linux 差异'),
                  const SizedBox(height: 10),
                  const LinuxNote(
                    text: '不能自动跟随前台窗口；用户必须通过 portal 选择。',
                    icon: Icons.info_outline,
                  ),
                  const SizedBox(height: 8),
                  const LinuxNote(
                    text: '全局热键由 KDE 管理；失败时显式提示。',
                    icon: Icons.keyboard,
                  ),
                  const SizedBox(height: 8),
                  const LinuxNote(
                    text: '无自动更新、触控助手和 Win32 接口。',
                    icon: Icons.block,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(icon: Icons.checklist, title: '进度'),
                  const SizedBox(height: 10),
                  for (int i = 0; i < _steps.length; i++)
                    _ProgressRow(
                      label: _steps[i],
                      done: i < _step,
                      active: i == _step,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.step,
    required this.title,
    required this.description,
    required this.child,
  });

  final int step;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Pill(label: '第 ${step + 1} 步', compact: true),
            if (step == 4) ...[
              const SizedBox(width: 8),
              const Pill(label: '最后一步', color: successColor, compact: true),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(description, style: mutedStyle(context)),
        const SizedBox(height: 18),
        child,
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.index,
    required this.label,
    required this.active,
    required this.completed,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool active;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active
        ? accentColor
        : completed
        ? successColor
        : mutedColorOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active || completed
                    ? color.withValues(alpha: 0.14)
                    : Colors.transparent,
                border: Border.all(color: color, width: 1.5),
              ),
              child: completed
                  ? Icon(Icons.check, size: 13, color: color)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? color : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      border: selected ? accentColor.withValues(alpha: 0.5) : null,
      color: selected ? accentColor.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? accentColor : Colors.transparent,
              border: Border.all(
                color: selected ? accentColor : borderColorOf(context),
                width: 2,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: mutedStyle(context)),
              ],
            ),
          ),
          if (selected)
            const Pill(label: '已选择', color: successColor, compact: true),
        ],
      ),
    );
  }
}

class _WindowChoice extends StatelessWidget {
  const _WindowChoice({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.08)
                : inputFillColorOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accentColor.withValues(alpha: 0.5)
                  : borderColorOf(context),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.window_outlined,
                size: 18,
                color: selected ? accentColor : mutedColorOf(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check, size: 16, color: accentColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: labelStyle(context))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const Icon(Icons.check, size: 14, color: successColor),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? successColor : warningColor,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 72, child: Text(label, style: labelStyle(context))),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = done
        ? successColor
        : active
        ? accentColor
        : mutedColorOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : active
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? accentColor : null,
            ),
          ),
        ],
      ),
    );
  }
}
