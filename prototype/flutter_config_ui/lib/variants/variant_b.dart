import 'package:material_ui/material_ui.dart';

import '../model.dart';
import '../theme.dart';
import '../widgets.dart';

/// Variant B — a profile-first workspace: profile rail, central pipeline and
/// preview, permanent inspector. No global navigation hierarchy.
class VariantB extends StatelessWidget {
  const VariantB({super.key, required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBarB(state: state),
        Expanded(
          child: Row(
            children: [
              _ProfileRail(state: state),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 110),
                  child: _Workspace(state: state),
                ),
              ),
              _Inspector(state: state),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBarB extends StatelessWidget {
  const _TopBarB({required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
          Text('工作台', style: mutedStyle(context)),
          const SizedBox(width: 10),
          Pill(
            label: state.profile.name,
            color: state.profile.color,
            icon: state.profile.icon,
            compact: true,
          ),
          const Spacer(),
          const Pill(
            label: 'KWin · Wayland',
            icon: Icons.monitor,
            compact: true,
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
            tooltip: '托盘与通知',
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
            tooltip: '全局设置',
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: state.toggleScaling,
            icon: Icon(
              state.isScaling ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 18,
            ),
            label: Text(state.isScaling ? '停止' : '开始缩放'),
          ),
        ],
      ),
    );
  }
}

class _ProfileRail extends StatelessWidget {
  const _ProfileRail({required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: panelColorOf(context),
        border: Border(right: BorderSide(color: borderColorOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text('配置文件', style: titleStyle(context))),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: '新建配置',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (int i = 0; i < PrototypeState.profiles.length; i++)
                  _ProfileCard(
                    profile: PrototypeState.profiles[i],
                    selected: state.activeProfile == i,
                    onTap: () => state.selectProfile(i),
                  ),
                const SizedBox(height: 4),
                _NewProfileButton(onTap: () {}),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('匹配规则', style: labelStyle(context)),
                const SizedBox(height: 4),
                Text(
                  'Linux 首版只支持手动选择或 portal 选源；'
                  '按窗口类名自动匹配留作后续增强。',
                  style: mutedStyle(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final ProfilePreset profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Panel(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        border: selected ? profile.color.withValues(alpha: 0.55) : null,
        color: selected ? profile.color.withValues(alpha: 0.08) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(profile: profile, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(profile.subtitle, style: mutedStyle(context)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 16, color: profile.color),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Pill(
                  label: profile.scalingMode,
                  color: profile.color,
                  compact: true,
                ),
                const SizedBox(width: 6),
                Pill(
                  label: '${profile.frameRate} fps',
                  color: warningColor,
                  compact: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewProfileButton extends StatelessWidget {
  const _NewProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColorOf(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.add, size: 16, color: mutedColorOf(context)),
                const SizedBox(width: 8),
                Text('新建配置', style: mutedStyle(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkspaceHeader(state: state),
        const SizedBox(height: 14),
        _PipelinePanel(state: state),
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      icon: Icons.fullscreen,
                      title: '输出预览',
                      subtitle: '全屏覆盖层由原生 Vulkan 呈现，Flutter 不参与',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Pill(
                    label: state.isScaling ? '运行中' : '待机',
                    color: state.isScaling
                        ? successColor
                        : mutedColorOf(context),
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MockWindowPreview(
                title: '输出预览 · ${state.output.split(' · ').first}',
                badge: state.isScaling ? 'Vulkan' : '未启动',
                scaled: state.isScaling,
                scale: state.scale,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    label: 'portal 选源',
                    icon: Icons.lock_outline,
                    compact: true,
                  ),
                  Pill(
                    label: 'layer-shell overlay',
                    color: violetColor,
                    icon: Icons.layers,
                    compact: true,
                  ),
                  Pill(
                    label: '8-bit SDR',
                    color: warningColor,
                    icon: Icons.contrast,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(icon: Icons.tune, title: '缩放参数'),
                    const Divider(height: 22),
                    LabeledSlider(
                      label: '倍率',
                      valueLabel: '${state.scale.toStringAsFixed(1)}×',
                      value: state.scale,
                      min: 1,
                      max: 3,
                      divisions: 20,
                      onChanged: state.setScale,
                    ),
                    const SizedBox(height: 10),
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
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(icon: Icons.monitor, title: '输出与光标'),
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
                      subtitle: '限制输出帧率',
                      value: state.frameRateLimiter,
                      onChanged: (bool value) =>
                          state.update(() => state.frameRateLimiter = value),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LinuxNote(
          text:
              '工作台以“当前配置”为中心：左侧切换配置，中间查看效果链与输出，右侧调整快捷键和高级项。'
              '这是与 Variant A 的主要结构差异。',
          icon: Icons.science_outlined,
        ),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    final ProfilePreset profile = state.profile;
    return Row(
      children: [
        ProfileAvatar(profile: profile, size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pill(
                    label: profile.subtitle,
                    color: profile.color,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(profile.matchRule, style: mutedStyle(context)),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('编辑配置'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: state.toggleScaling,
          icon: Icon(
            state.isScaling ? Icons.stop_rounded : Icons.play_arrow_rounded,
            size: 18,
          ),
          label: Text(state.isScaling ? '停止缩放' : '开始缩放'),
        ),
      ],
    );
  }
}

class _PipelinePanel extends StatelessWidget {
  const _PipelinePanel({required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: accentColor.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeader(
                  icon: Icons.auto_awesome_mosaic,
                  title: '效果链',
                  subtitle: '从 portal 帧到全屏输出',
                ),
              ),
              const SizedBox(width: 12),
              const Pill(
                label: 'MagpieFX → SPIR-V',
                color: violetColor,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PipelineNode(
                  icon: Icons.crop_free,
                  label: '源窗口',
                  value: state.captureMethod,
                ),
              ),
              const _PipelineArrow(),
              Expanded(
                child: _PipelineNode(
                  icon: Icons.auto_awesome,
                  label: state.scalingMode,
                  value: '${state.scale.toStringAsFixed(1)}×',
                  accent: true,
                ),
              ),
              const _PipelineArrow(),
              Expanded(
                child: _PipelineNode(
                  icon: Icons.speed,
                  label: '帧率',
                  value: '${state.frameRate} fps',
                ),
              ),
              const _PipelineArrow(),
              Expanded(
                child: _PipelineNode(
                  icon: Icons.monitor,
                  label: '输出',
                  value: state.output.split(' · ').first,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineNode extends StatelessWidget {
  const _PipelineNode({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final Color color = accent ? accentColor : mutedColorOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: panelColorOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent
              ? accentColor.withValues(alpha: 0.45)
              : borderColorOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: mutedStyle(context),
          ),
        ],
      ),
    );
  }
}

class _PipelineArrow extends StatelessWidget {
  const _PipelineArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Icon(Icons.arrow_forward, size: 14, color: mutedColorOf(context)),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({required this.state});

  final PrototypeState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: panelColorOf(context),
        border: Border(left: BorderSide(color: borderColorOf(context))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(icon: Icons.keyboard, title: '快捷键'),
                  const Divider(height: 20),
                  HotkeyRow(
                    icon: Icons.fullscreen,
                    title: '全屏',
                    value: state.fullscreenHotkey,
                    onTap: () => state.update(
                      () => state.fullscreenHotkey = nextHotkey(
                        state.fullscreenHotkey,
                      ),
                    ),
                  ),
                  HotkeyRow(
                    icon: Icons.crop_free,
                    title: '窗口',
                    value: state.windowedHotkey,
                    onTap: () => state.update(
                      () => state.windowedHotkey = nextHotkey(
                        state.windowedHotkey,
                      ),
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
            const SizedBox(height: 12),
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(icon: Icons.tune, title: '高级'),
                  const Divider(height: 20),
                  ToggleRow(
                    title: '覆盖层',
                    value: state.showOverlay,
                    onChanged: (bool value) =>
                        state.update(() => state.showOverlay = value),
                  ),
                  ToggleRow(
                    title: '自动隐藏光标',
                    value: state.autoHideCursor,
                    onChanged: (bool value) =>
                        state.update(() => state.autoHideCursor = value),
                  ),
                  ToggleRow(
                    title: '窗口模式',
                    value: state.windowedMode,
                    onChanged: (bool value) =>
                        state.update(() => state.windowedMode = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(icon: Icons.terminal, title: 'Linux 说明'),
                  const SizedBox(height: 10),
                  const LinuxNote(
                    text: '源窗口由 portal 选择，不能自动跟随前台窗口。',
                    icon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 8),
                  const LinuxNote(
                    text: '全局热键由 KDE 管理；绑定失败会显式提示。',
                    icon: Icons.keyboard,
                  ),
                  const SizedBox(height: 8),
                  const LinuxNote(
                    text: '更新由 Flatpak 或发行版负责，应用内没有更新器。',
                    icon: Icons.sync,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('保存为配置'),
            ),
            const SizedBox(height: 6),
            Center(child: Text('原型状态不持久化', style: mutedStyle(context))),
          ],
        ),
      ),
    );
  }
}
