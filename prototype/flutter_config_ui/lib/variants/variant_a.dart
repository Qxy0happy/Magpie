import 'package:material_ui/material_ui.dart';

import '../model.dart';
import '../theme.dart';
import '../widgets.dart';

/// Variant A — the closest translation of the WinUI shell:
/// a persistent left navigation rail plus stacked settings cards.
class VariantA extends StatefulWidget {
  const VariantA({super.key, required this.state});

  final PrototypeState state;

  @override
  State<VariantA> createState() => _VariantAState();
}

class _VariantAState extends State<VariantA> {
  int _section = 0;

  static const List<String> _sectionTitles = <String>['主页', '缩放模式', '设置', '关于'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildSidebar(context),
        Expanded(
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 110),
                  child: _buildSection(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final PrototypeState state = widget.state;
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: panelColorOf(context),
        border: Border(right: BorderSide(color: borderColorOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                BrandMark(size: 34),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Magpie',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Linux 配置原型',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: PrototypeBadge(),
          ),
          const SizedBox(height: 10),
          _NavItem(
            icon: Icons.home_outlined,
            label: '主页',
            selected: _section == 0,
            onTap: () => setState(() => _section = 0),
          ),
          _NavItem(
            icon: Icons.auto_awesome_mosaic_outlined,
            label: '缩放模式',
            selected: _section == 1,
            onTap: () => setState(() => _section = 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Text(
              '配置文件',
              style: labelStyle(context).copyWith(letterSpacing: 1),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (int i = 0; i < PrototypeState.profiles.length; i++)
                  _ProfileNavItem(
                    profile: PrototypeState.profiles[i],
                    selected: state.activeProfile == i,
                    onTap: () {
                      state.selectProfile(i);
                      setState(() => _section = 0);
                    },
                  ),
                _NavItem(
                  icon: Icons.add,
                  label: '新建配置',
                  selected: false,
                  onTap: () => setState(() => _section = 0),
                ),
              ],
            ),
          ),
          Divider(color: borderColorOf(context), height: 1),
          const SizedBox(height: 6),
          _NavItem(
            icon: Icons.settings_outlined,
            label: '设置',
            selected: _section == 2,
            onTap: () => setState(() => _section = 2),
          ),
          _NavItem(
            icon: Icons.info_outline,
            label: '关于',
            selected: _section == 3,
            onTap: () => setState(() => _section = 3),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KWin · Wayland', style: labelStyle(context)),
                const SizedBox(height: 2),
                Text('Flutter 3.50 · 原型', style: mutedStyle(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: panelColorOf(context).withValues(alpha: 0.55),
        border: Border(bottom: BorderSide(color: borderColorOf(context))),
      ),
      child: Row(
        children: [
          Text(
            _sectionTitles[_section],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 12),
          const Pill(
            label: 'KWin · Wayland',
            icon: Icons.monitor,
            compact: true,
          ),
          const Spacer(),
          ScalingStatusPill(isScaling: widget.state.isScaling),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
            tooltip: '通知',
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 16,
            backgroundColor: accentColor.withValues(alpha: 0.16),
            child: const Text(
              'Q',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    switch (_section) {
      case 0:
        return _buildHome(context);
      case 1:
        return _buildModes(context);
      case 2:
        return _buildSettings(context);
      default:
        return _buildAbout(context);
    }
  }

  Widget _buildHome(BuildContext context) {
    final PrototypeState state = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Pill(
                          label: 'Linux · Wayland',
                          icon: Icons.monitor,
                          compact: true,
                        ),
                        const SizedBox(width: 8),
                        const Pill(
                          label: 'portal 选源',
                          color: successColor,
                          icon: Icons.lock_outline,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '选择源窗口，然后开始放大',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Wayland 不允许应用枚举前台窗口。点击开始后，KDE 会请求你选择一个源窗口；'
                      '热键由桌面的 GlobalShortcuts portal 管理。',
                      style: mutedStyle(context),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: state.toggleScaling,
                          icon: Icon(
                            state.isScaling
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(state.isScaling ? '停止缩放' : '开始缩放'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            state.update(() {
                              state.fullscreenHotkey = nextHotkey(
                                state.fullscreenHotkey,
                              );
                            });
                          },
                          icon: const Icon(Icons.keyboard),
                          label: Text('${state.fullscreenHotkey} 全屏'),
                        ),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.timer_outlined),
                          label: Text('定时 ${state.timer}'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 260,
                child: MockWindowPreview(
                  title: '源窗口 · 游戏',
                  badge: state.isScaling ? '已授权' : '未授权',
                  scaled: state.isScaling,
                  scale: state.scale,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.memory,
                  label: 'GPU',
                  value: 'Radeon 780M · Vulkan',
                ),
              ),
              _divider(context),
              Expanded(
                child: _StatItem(
                  icon: Icons.monitor,
                  label: '合成器',
                  value: 'KWin 6.8 · Wayland',
                ),
              ),
              _divider(context),
              Expanded(
                child: _StatItem(
                  icon: Icons.lock_outline,
                  label: 'Portal',
                  value: 'ScreenCast v6 · 一次性授权',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _QuickCard(
                icon: Icons.fullscreen,
                title: '全屏缩放',
                subtitle: '覆盖当前输出',
                hotkey: state.fullscreenHotkey,
                active: state.isScaling,
                onTap: state.toggleScaling,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickCard(
                icon: Icons.crop_free,
                title: '窗口模式',
                subtitle: '保留桌面布局',
                hotkey: state.windowedHotkey,
                active: state.windowedMode,
                onTap: () => state.update(
                  () => state.windowedMode = !state.windowedMode,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickCard(
                icon: Icons.screenshot_monitor,
                title: '截图',
                subtitle: '保存放大后的画面',
                hotkey: state.screenshotHotkey,
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.tune,
                title: '当前配置',
                subtitle: '修改会立即反映到底部状态行',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledDropdown<int>(
                      label: '配置文件',
                      value: state.activeProfile,
                      items: List<int>.generate(
                        PrototypeState.profiles.length,
                        (int i) => i,
                      ),
                      labelOf: (int i) => PrototypeState.profiles[i].name,
                      onChanged: (int? value) {
                        if (value != null) {
                          state.selectProfile(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledDropdown<String>(
                      label: '缩放模式',
                      value: state.scalingMode,
                      items: PrototypeState.scalingModes
                          .map((ScalingModePreset mode) => mode.name)
                          .toList(),
                      labelOf: (String value) => value,
                      onChanged: (String? value) {
                        if (value != null) {
                          state.setScalingMode(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledDropdown<String>(
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
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LabeledSlider(
                label: '缩放倍率',
                valueLabel: '${state.scale.toStringAsFixed(1)}×',
                value: state.scale,
                min: 1,
                max: 3,
                divisions: 20,
                onChanged: state.setScale,
                hint: '窗口模式下会作为初始倍率；全屏模式会按输出尺寸等比缩放。',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LabeledDropdown<int>(
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledDropdown<String>(
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
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.terminal,
                title: 'Linux 适配',
                subtitle: '与 WinUI 版的行为差异',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  Pill(label: '源窗口由 portal 选择', icon: Icons.lock_outline),
                  Pill(
                    label: '全局热键由 KDE 管理',
                    color: successColor,
                    icon: Icons.keyboard,
                  ),
                  Pill(
                    label: '更新交给 Flatpak/发行版',
                    color: warningColor,
                    icon: Icons.sync,
                  ),
                  Pill(
                    label: '触控助手仅 Windows',
                    color: dangerColor,
                    icon: Icons.touch_app_outlined,
                  ),
                  Pill(label: '效果文件位于应用沙盒', icon: Icons.folder_outlined),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Windows 专属项在 Linux 上不做等价实现；设置页会用“由系统管理”或“仅 Windows”标注。',
                style: mutedStyle(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModes(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.auto_awesome_mosaic_outlined,
          title: '缩放模式',
          subtitle: '选择效果链；原型只展示信息架构，不运行真实效果',
          trailing: FilledButton.tonalIcon(
            onPressed: () {},
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新建模式'),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final ScalingModePreset mode in PrototypeState.scalingModes)
              SizedBox(
                width: 300,
                child: _ModeCard(
                  mode: mode,
                  selected: widget.state.scalingMode == mode.name,
                  onSelect: () => widget.state.setScalingMode(mode.name),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        LinuxNote(
          text:
              'Linux 版保留 MagpieFX/HLSL 效果源，经 DXC 编译为 SPIR-V；'
              '首版只验证内置效果，自定义效果目录位于 Flatpak 沙盒内。',
          icon: Icons.developer_board,
        ),
      ],
    );
  }

  Widget _buildSettings(BuildContext context) {
    final PrototypeState state = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(icon: Icons.tune, title: '通用'),
              const Divider(height: 22),
              SettingRow(
                title: '语言',
                subtitle: '首版跟随系统；本地化资源从 .resw 迁移到 Flutter ARB。',
                trailing: const Pill(label: '简体中文', icon: Icons.language),
              ),
              SettingRow(
                title: '主题',
                subtitle: '浅色 / 深色 / 跟随系统',
                trailing: const Pill(
                  label: '跟随系统',
                  icon: Icons.palette_outlined,
                ),
              ),
              ToggleRow(
                title: '显示托盘图标',
                subtitle: 'Flatpak 下通过 SNI 注册，需 StatusNotifierWatcher 权限。',
                value: true,
                onChanged: (_) {},
              ),
              ToggleRow(
                title: '单实例',
                subtitle: '由 GApplication 的 D-Bus 名称保证。',
                value: true,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.computer,
                title: '启动与更新',
                subtitle: 'Windows 专属项在 Linux 上的取舍',
              ),
              const Divider(height: 22),
              const SettingRow(
                title: '开机自启',
                subtitle: '交给桌面环境或 Flatpak Background portal。',
                enabled: false,
                trailing: Pill(label: '由系统管理', color: warningColor),
              ),
              const SettingRow(
                title: '自动更新',
                subtitle: '由 Flatpak 仓库或发行版包管理器负责。',
                enabled: false,
                trailing: Pill(label: '由系统管理', color: warningColor),
              ),
              const SettingRow(
                title: '触控助手',
                subtitle: 'Windows 版使用独立的 TouchHelper.exe。',
                enabled: false,
                trailing: Pill(label: '仅 Windows', color: dangerColor),
              ),
              const SettingRow(
                title: 'Win32 编程接口',
                subtitle: 'Linux 版改用 session D-Bus 接口。',
                enabled: false,
                trailing: Pill(label: '仅 Windows', color: dangerColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.keyboard,
                title: '快捷键',
                subtitle: 'Wayland 下由 GlobalShortcuts portal 管理；点击可循环示例值。',
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
                  () => state.windowedHotkey = nextHotkey(state.windowedHotkey),
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
              const SizedBox(height: 8),
              LinuxNote(
                text: 'Linux 下不能保证“抢占”桌面快捷键；如果 KDE 拒绝绑定，界面会显示为不可用而不是静默失败。',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(icon: Icons.folder_outlined, title: '效果与文件'),
              const Divider(height: 22),
              SettingRow(
                title: '效果目录',
                subtitle: 'Flatpak 沙盒内路径',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      '~/.var/app/…/data/magpie/effects',
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.open_in_new, size: 16),
                  ],
                ),
              ),
              SettingRow(
                title: '截图目录',
                subtitle: '首版使用 SaveFile portal 对话框',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('~/Pictures/Magpie', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 8),
                    Icon(Icons.open_in_new, size: 16),
                  ],
                ),
              ),
              SettingRow(
                title: '帧率限制',
                subtitle: '限制放大链路的输出帧率',
                trailing: Switch(
                  value: state.frameRateLimiter,
                  onChanged: (bool value) =>
                      state.update(() => state.frameRateLimiter = value),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAbout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Magpie for Linux',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '配置界面信息架构原型 · 0.1.0-prototype',
                      style: mutedStyle(context),
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Pill(label: 'GPL-3.0', icon: Icons.balance),
                        Pill(
                          label: 'Flutter 3.50',
                          color: violetColor,
                          icon: Icons.flutter_dash,
                        ),
                        Pill(
                          label: 'C++/Vulkan 引擎',
                          color: successColor,
                          icon: Icons.memory,
                        ),
                        Pill(
                          label: 'KDE Plasma · KWin',
                          color: warningColor,
                          icon: Icons.monitor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(icon: Icons.science_outlined, title: '原型范围'),
              const SizedBox(height: 10),
              Text(
                '这个原型只回答“配置界面应该怎样组织”。它使用假数据，不连接原生引擎，'
                '不会真的捕获窗口、编译效果或启动 Vulkan 缩放。',
                style: mutedStyle(context),
              ),
              const SizedBox(height: 14),
              const _AboutRow(label: '上游项目', value: 'Blinue/Magpie（GPL-3.0）'),
              const _AboutRow(
                label: '目标平台',
                value: 'KDE Plasma / KWin Wayland',
              ),
              const _AboutRow(
                label: '引擎边界',
                value: 'Flutter 只做配置 UI；缩放、捕获、覆盖层保持原生',
              ),
              const _AboutRow(label: '未实现', value: '真实捕获、效果编译、全局热键、托盘、打包'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: borderColorOf(context),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? accentColor
        : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? accentColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? accentColor : mutedColorOf(context),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileNavItem extends StatelessWidget {
  const _ProfileNavItem({
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
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? accentColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                ProfileAvatar(profile: profile, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      Text(profile.scalingMode, style: mutedStyle(context)),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check, size: 15, color: accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accentColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle(context)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hotkey,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String hotkey;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: accentColor),
              ),
              const Spacer(),
              if (active)
                const Pill(label: '运行中', color: successColor, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: mutedStyle(context)),
          const SizedBox(height: 12),
          Row(
            children: [
              KeyCap(hotkey),
              const Spacer(),
              Icon(Icons.arrow_forward, size: 14, color: mutedColorOf(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onSelect,
  });

  final ScalingModePreset mode;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onSelect,
      border: selected ? accentColor.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: violetColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 17,
                  color: violetColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mode.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected)
                const Pill(label: '使用中', color: successColor, compact: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(mode.description, style: mutedStyle(context)),
          const SizedBox(height: 14),
          Row(
            children: [
              Pill(label: mode.tag, color: violetColor, compact: true),
              const SizedBox(width: 6),
              Pill(
                label: '负载 ${mode.cost}',
                color: warningColor,
                compact: true,
              ),
              const Spacer(),
              Text(
                selected ? '已选择' : '选择',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? successColor : accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: labelStyle(context))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
