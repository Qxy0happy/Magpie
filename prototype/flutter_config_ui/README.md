# Magpie Linux 配置界面原型

> **PROTOTYPE — throwaway.** This directory is a disposable UI exploration, not
> production code. It uses fake data, does not connect to the engine, and does
> not persist anything. Do not merge it into `dev`.

## 问题

把现有 WinUI 配置界面迁移到 Flutter 后，导航、页面分组、主操作位置和 Linux
差异应该如何组织？

对应票据：[Flutter 配置界面信息架构原型](https://github.com/Qxy0happy/Magpie/issues/8)。

## 计划

在同一个窗口里提供 **3 个结构不同的变体**，用底部浮条切换。它们共享同一份
内存状态，方便对比同一项设置在不同信息架构里的位置。

| 变体 | 结构 | 主要区别 |
|---|---|---|
| **A · 侧栏 + 设置卡片** | 常驻左侧导航 + 堆叠设置卡片 | 最接近现有 WinUI 的层级；按页面组织。 |
| **B · 配置优先工作台** | 配置列表 + 效果链/预览 + 常驻检查器 | 以“当前配置”为中心；主操作是切换配置并开始缩放。 |
| **C · 设置向导** | 顶部步骤条 + 线性流程 + 右侧预览 | 按任务顺序组织；适合首次配置或引导。 |

## 运行

```bash
cd prototype/flutter_config_ui
flutter run -d linux
```

选择初始变体（可选，`a` / `b` / `c`）：

```bash
flutter run -d linux --dart-define=PROTOTYPE_VARIANT=b
```

只看构建产物：

```bash
flutter build linux --debug
./build/linux/x64/debug/bundle/magpie_config_ui_prototype
```

## 操作

- 底部浮条左右箭头切换变体，循环。
- 键盘 `1` / `2` / `3` 直接切到 A / B / C；`←` / `→` 循环。
- 底部浮条中间显示当前状态摘要；`{}` 按钮打开完整状态面板；`?` 打开说明。
- 右侧太阳/月亮图标切换浅色/深色主题。
- 快捷键行右侧的编辑按钮会循环示例键位，用来观察状态更新。
- 状态只存在内存；切换变体不会清空，关闭应用即丢失。

## 需要你判断

请优先比较信息架构，而不是配色和圆角：

1. 哪个变体最接近你对“Linux 版 Magpie 配置界面”的预期？
2. 导航是否覆盖了现有 WinUI 的功能：主页、缩放模式、配置文件、设置、关于？
3. “开始缩放”是否足够显眼？在 Wayland 下它必须先经过 portal 选源。
4. Linux 差异是否出现在正确的位置：portal 选源、KDE 全局热键、Flatpak
   更新、无触控助手、效果文件沙盒。
5. 是否想把不同变体的部分组合起来，例如 A 的导航 + B 的工作台 + C 的向导步骤？

反馈时可以直接说“要 A 的导航，B 的中间区域，C 的右侧预览”，或指出某一项放错了页面。

## Linux 差异标注

原型里已经显式标注：

- **源窗口选择**：Wayland 不允许枚举前台窗口；首版通过 `xdg-desktop-portal`
  的 ScreenCast 选择器获取窗口流。
- **全局热键**：由 KDE 的 GlobalShortcuts portal 管理；失败时显式提示。
- **更新**：由 Flatpak 仓库或发行版包管理器负责；应用内没有更新器。
- **触控助手**：Windows 专属，Linux 版不提供。
- **编程接口**：Windows 使用 Win32 消息/窗口属性；Linux 版改为 session D-Bus。
- **效果文件**：Flatpak 沙盒内路径；截图使用 SaveFile portal。
- **采集格式**：KWin 6.8 的窗口流是 8-bit SDR；原型不假装支持 HDR。

## 边界

未实现：真实 portal 捕获、PipeWire 导入、Vulkan 计算、MagpieFX 编译、全局热键、
托盘、配置持久化、安装包、测试。

这个原型只回答“信息架构怎么组织”。技术可行性和引擎架构由地图上的研究票与
决策票处理。
