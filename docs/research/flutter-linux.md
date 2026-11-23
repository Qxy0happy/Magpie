# Flutter Linux 桌面端与原生 Vulkan 引擎的集成边界

- 票据：Qxy0happy/Magpie#3
- 日期：2026-11-23
- 结论性质：决策建议（研究票，不含实现）
- 实测环境：Flutter 3.50.1 / Dart 3.14.0；GTK 3.24.52；Plasma 6.8.3（KWin Wayland）；Vulkan 1.4.363
- 上游代码参照：`src/Magpie`（C++/WinRT + WinUI 3，配置界面）与 `src/Magpie.Core`（D3D11 渲染核心）

---

## 0. 结论摘要

推荐采用 **“常驻原生引擎 + 按需 Flutter 设置客户端”** 的两进程架构：

1. **`magpie`（原生 C++/Vulkan 引擎）是应用入口与常驻进程**，使用 `GApplication`（GIO，不依赖 GTK）持有 session D-Bus 名称，独占以下运行时职责：
   - `xdg-desktop-portal` ScreenCast 会话与 PipeWire 流；
   - `xdg-desktop-portal` GlobalShortcuts 会话（全局快捷键）；
   - StatusNotifierItem 托盘图标与菜单；
   - Vulkan 覆盖层（全屏或窗口化缩放窗口）、ImGui 覆盖层 UI；
   - 配置文件的解析、校验、持久化与 effect 元数据（MagpieFX 参数）；
   - 日志、通知、崩溃处理。
2. **`magpie-ui`（Flutter）是按需启动、可随时关闭的设置客户端**，只负责配置界面：
   - 通过 session D-Bus 读取引擎快照、提交配置、订阅状态；
   - 使用 `file_selector` 选择效果文件与截图目录；
   - 使用 Flutter 自带主题体系与 Settings portal 的 `color-scheme`；
   - 不持有任何 portal 会话、不注册全局快捷键、不创建托盘图标。
3. **不做任何纹理/帧互操作**。缩放结果始终由引擎自己的 Wayland surface 呈现，Flutter 不接收帧、不导入 dmabuf、不使用 `FlTextureRegistrar`。
4. **不使用 `dart:ffi` 承载引擎**。引擎与 UI 之间只有控制面，没有数据面；FFI 只会把崩溃域合并、把 GTK 主循环与 Vulkan 事件循环耦合在一起，收益为零。
5. 这一划分与地图的锁定决策“Flutter 只负责配置界面”一致：托盘、快捷键、覆盖层属于运行时，不应由 Flutter 进程承担。

如果产品最终决定“Flutter 常驻并承担托盘/快捷键”，则应改用**独立短生命周期引擎进程 + Unix domain socket**（§2.2），并接受 `tray_manager`/`hotkey_manager` 依赖 `nativeapi`（WIP）的风险（§4）。

---

## 1. Flutter Linux 嵌入器现状（源码与实测）

### 1.1 技术栈与进程内线程模型

- Flutter Linux 桌面嵌入器基于 **GTK 3**：引擎构建配置直接依赖 `gtk+-3.0`（[`engine/src/flutter/shell/platform/linux/config/BUILD.gn`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/config/BUILD.gn)，访问 2026-11-23）；本机 `pkg-config --modversion gtk+-3.0` 为 3.24.52。
- 嵌入器提供 `FlApplication`（继承 `GtkApplication`）与 `FlView`（GTK widget）。`FlApplication::activate` 创建 `FlView`、挂到 `GtkWindow`、注册插件并 realize（[`fl_application.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_application.cc)，访问 2026-11-23）。
- Flutter 的 **platform task runner 被接到 GLib 主循环**：`FlEngine` 创建 `FlTaskRunner`，把平台任务作为 GLib source 调度（[`fl_engine.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_engine.cc) 中 `platform_task_runner`，[`fl_task_runner.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_task_runner.cc)，访问 2026-11-23）。因此可以认为 **GTK 主循环就是 Flutter 的 platform thread**；UI/raster 线程由引擎另行创建（[Flutter 架构概览](https://docs.flutter.dev/resources/architectural-overview)：embedder “obtains threads for UI and rastering”，访问 2026-11-23）。
- 结论：任何原生工作都不得在 GTK 主循环上执行长任务；GTK API 只能在 GTK 线程调用；Vulkan 呈现必须在独立线程或独立进程。

### 1.2 渲染路径：Flutter 在 Wayland 上使用 subsurface

`fl_view.cc` 在 Wayland 显示环境下选择 `FlViewRendererSubsurface`，在 X11 下选择 OpenGL renderer：

```cpp
if (GDK_IS_WAYLAND_DISPLAY(gtk_widget_get_display(GTK_WIDGET(self)))) {
  self->renderer = FL_VIEW_RENDERER(fl_view_renderer_subsurface_new(...));
} else {
  self->renderer = FL_VIEW_RENDERER(fl_view_renderer_opengl_new(...));
}
```

来源：[`fl_view.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_view.cc)，访问 2026-11-23。

这有两个直接后果：

1. Flutter 的内容不是一块可被外部读取的 GL 纹理，而是 GTK 顶层 surface 下的 **wl_subsurface**；外部进程无法从中取帧。
2. **不能把 Vulkan swapchain 呈现到 Flutter 正在使用的 `GdkWindow`/`wl_surface`**。GTK 与该 subsurface 已经拥有该 surface 的 buffer 提交权；Vulkan WSI 需要独占同一个 `wl_surface`。`VkWaylandSurfaceCreateInfoKHR` 明确要求传入 `wl_display*` 与 `wl_surface*`（[`vulkan_wayland.h`](https://github.com/KhronosGroup/Vulkan-Headers/blob/main/include/vulkan/vulkan_wayland.h)，访问 2026-11-23）。若强行复用，GTK 与 Vulkan 会竞争 commit，且 GTK 的 frame clock、输入区域和 resize 逻辑都会干扰 swapchain。

因此，**原生覆盖层必须拥有自己的 Wayland surface**；它与 Flutter 窗口只能是两个独立的顶层/表面。§2 进一步讨论同进程与跨进程的差异。

### 1.3 多窗口

- 引擎层已经支持“一个 `FlEngine` + 多个 `FlView`”：存在 `fl_view_new_for_engine`、`fl_view_new_sized_to_content`，通过 `fl_engine_add_view` 注册新视图（[`fl_view.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_view.cc)，访问 2026-11-23）。
- Dart 侧窗口 API 仍是 **experimental / feature flag**：`packages/flutter/lib/src/widgets/_window.dart` 明确写明 “Do not use this API in production applications”，且要求 `isWindowingEnabled`；见本机 Flutter 3.50.1 SDK 文件，以及 [flutter/flutter#177586 “Multi-Window Pre-launch Checklist”](https://github.com/flutter/flutter/issues/177586)（open，2025-10-27 创建，2026-10-22 更新，访问 2026-11-23）。
- Linux 上该实验路径仍有阻塞性缺陷：[#191166](https://github.com/flutter/flutter/issues/191166)（open，2026-08-16）：headless bootstrap 在插件注册时传入 `NULL FlView`，会使 `desktop_drop` 一类插件直接崩溃。
- 结论：**不要依赖 Flutter 多窗口 API**。Magpie 的运行时窗口（覆盖层）本来就是原生窗口；设置界面只需要一个 Flutter 窗口。若未来需要第二个 Flutter 窗口，应使用 `fl_view_new_for_engine` 共享同一 `FlEngine`（需要改 runner），而不是启动第二个 Dart engine。

`desktop_multi_window` 的实现方式是后者：在同一个 GTK 主循环里为每个窗口创建新的 `FlView`，即新的 `FlDartProject`/engine（[`multi_window_manager.cc`](https://github.com/MixinNetwork/flutter-plugins/blob/main/packages/desktop_multi_window/linux/multi_window_manager.cc) 第 102 行附近，访问 2026-11-23）。每个窗口一个 Dart VM，内存与生命周期成本高，且它自己注释说明需要绕过 Flutter 的 delete-event 以阻止关闭一个窗口时退出整个应用。对 Magpie 没有必要。

### 1.4 单实例与生命周期

- `GApplication` 的进程唯一性由 **application id + session D-Bus 名称**实现：同一 ID 只允许一个 primary instance，后续启动通过 D-Bus 把参数交给 primary（[GApplication 文档](https://docs.gtk.org/gio/class.Application.html)，访问 2026-11-23）。
- 但 Flutter Linux 默认 runner **显式关闭了唯一性**：模板 `my_application_new` 使用 `g_object_new(..., "application-id", APPLICATION_ID, "flags", G_APPLICATION_NON_UNIQUE, ...)`（本机 SDK：`packages/flutter_tools/templates/app/linux.tmpl/runner/my_application.cc.tmpl`，Flutter 3.50.1）。同时模板的 `local_command_line` 只是 `g_application_register` 后 `g_application_activate`，**不会把第二次启动的 argv 转发给 primary**。
- 关闭窗口会退出应用：`FlView` 在顶层窗口上连接 `delete-event`，回调调用 `fl_engine_request_app_exit`（[`fl_view.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_view.cc) 第 97、521 行附近，访问 2026-11-23）。
- 结论：若采用推荐的“引擎常驻 + UI 按需”，**由引擎持有主应用名称与启动语义**；Flutter UI 使用**自己的** application id（`io.github.qxy0happy.Magpie.Settings`）并保持唯一性，从而支持“第二次启动转发到已存在窗口”。UI 的关闭就是进程退出，无需隐藏到托盘，也不需要 `window_manager.setPreventClose`。窗口的 shell 身份（app_id）另行设为 `io.github.qxy0happy.Magpie`，以便与主 desktop 文件分组（runner 中分别设置 `application-id` 与 `g_set_prgname`）。
- 补充：pub.dev 上存在若干 single-instance 包（如 `windows_single_instance`、`flutter_single_instance`、`unix_single_instance`），但本票未发现它们在 Flutter Linux 桌面的广泛采用；`GApplication` 已内建唯一性，无需引入第三方插件。

### 1.5 托盘

- 现状：`tray_manager` 0.9.1（2026-11-22 发布）已改为基于 `nativeapi` 的 Linux/macOS/Windows 统一 C++ 核心；Linux 实现是 **StatusNotifierItem over D-Bus**，不再依赖 `libayatana-appindicator3`（[tray_manager README](https://github.com/leanflutter/tray_manager)，访问 2026-11-23）。
- KDE Plasma 提供 `org.kde.StatusNotifierWatcher` 与 StatusNotifierHost；本机实测存在 `org.kde.StatusNotifierWatcher`，且已有第三方应用注册的 SNI item（`busctl --user list`，2026-11-23）。因此 Plasma 6 上 SNI 可用。
- 已知限制（README 明示）：**Linux 不上报托盘图标点击事件**，面板保留点击并自行打开菜单；`getBounds()` 返回空；`popUpContextMenu()` 在 Linux 无效果。也就是说，“左键单击显示主窗口”这种 Windows 行为不能靠该插件实现，只能通过菜单项。
- 若采用推荐架构，托盘由引擎用 GDBus 直接实现（SNI + DBusMenu），可自行决定是否处理 `Activate`；Flutter 不参与。
- Flatpak 约束（[Flatpak Desktop Integration: StatusNotifier](https://docs.flatpak.org/en/latest/desktop-integration.html)，访问 2026-11-23）：StatusNotifier 至少需要 `--talk-name=org.kde.StatusNotifierWatcher`；部分实现还需要拥有 `org.kde.StatusNotifierItem-$PID-$ITEM_ID`，而 `--own-name=org.kde.*` 会引入冒充其他 KDE 服务的风险。文档指出当前 libappindicator/KNotifications 等已不再需要该 ownership。**因此引擎应把 SNI item 注册在自己的应用总线名称下（`io.github.qxy0happy.Magpie` + `/StatusNotifierItem`），只申请 `--talk-name=org.kde.StatusNotifierWatcher`，不要申请 `org.kde.*`。**
- 同时注意：Flatpak 文档明确“并非所有发行版都显示状态图标”，托盘只能作为辅助入口，不能是唯一控制方式；主窗口/CLI 仍需可用。

### 1.6 全局快捷键

- 现状：`hotkey_manager` 0.4.1（2026-11-22 发布）同样迁移到 `nativeapi`；README 明确：**原生 Wayland 下走 GlobalShortcuts portal**，X11/XWayland 走 X11 路径（[hotkey_manager README](https://github.com/leanflutter/hotkey_manager)，访问 2026-11-23）。
- portal 语义（[GlobalShortcuts 文档](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html)，访问 2026-11-23）：
  - 必须先 `CreateSession`，再 `BindShortcuts`；
  - `BindShortcuts` “通常会弹出对话框”，由用户确认/修改；
  - 返回的是 **实际绑定**，可能少于请求、也可能被桌面改写；
  - 会话与注册绑定到进程，进程退出即释放。
- 本机实测：`xdg-desktop-portal-kde` 暴露 `org.freedesktop.portal.GlobalShortcuts` version 2；仓库中存在 `src/globalshortcuts.cpp` 与 `GlobalShortcutsDialog.qml`（[KDE/xdg-desktop-portal-kde](https://github.com/KDE/xdg-desktop-portal-kde)，访问 2026-11-23）。
- 结论：快捷键的“注册与生命周期”必须归引擎（常驻进程）。Flutter 只负责录制用户期望的组合键、展示 portal 返回的实际绑定。**不能假设请求的组合键就是生效的组合键**——这是与 Win32 `RegisterHotKey` 最大的语义差异。

### 1.7 文件选择器

- `file_selector` 1.1.0（官方 `flutter/packages`）的 Linux 实现使用 `GtkFileChooserNative`（[`file_selector_plugin.cc`](https://github.com/flutter/packages/blob/main/packages/file_selector/file_selector_linux/linux/file_selector_plugin.cc)，访问 2026-11-23）。`GtkFileChooserNative` 在沙箱/桌面上会走 portal 的原生对话框。
- Dart 侧 Linux 实现支持 `openFile`、`getSaveLocation`、`getDirectoryPath`、多选目录（[`file_selector_linux.dart`](https://github.com/flutter/packages/blob/main/packages/file_selector/file_selector_linux/lib/file_selector_linux.dart)，访问 2026-11-23）。
- 用途：导入/导出效果文件、选择自定义效果所在目录、选择截图输出目录。Flatpak 下返回的可能是 document portal 的 FUSE 路径；引擎与 UI 在同一沙箱实例内，引擎可以直接读取。**这是“引擎与 UI 必须处于同一沙箱/命名空间”的具体理由之一。**

### 1.8 主题、颜色方案与字体缩放

- Flutter Linux 引擎通过 **Settings portal**（`org.freedesktop.portal.Settings`）读取 `org.freedesktop.appearance color-scheme`、`contrast`，以及部分 GNOME schema 键（`gtk-theme`、`text-scaling-factor`、`enable-animations` 等），再通过 settings channel 把 `platformBrightness`、文本缩放、动画开关送入引擎（[`fl_settings_portal.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_settings_portal.cc)、[`fl_settings_handler.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_settings_handler.cc)，访问 2026-11-23）。
- 本机实测（Plasma 6.8.3，`busctl`，2026-11-23）：
  - `org.freedesktop.appearance color-scheme` 返回 `2`（prefer dark）；
  - `accent-color` 返回 `(ddd) 0.239216 0.682353 0.913725`；
  - 说明 KDE 已实现 color-scheme 与 accent-color。
- 但 Flutter 只消费 `color-scheme`/`contrast`；**accent color 不由 Flutter 自动应用到 `ColorScheme`**。若要求与 KDE 强调色一致，UI 进程需自己通过 `dbus` 包读取 `accent-color` 并构造 `ColorScheme`（`package:dbus` 0.8.1，Canonical，MPL-2.0，2026-11-19 发布，[pub.dev](https://pub.dev/packages/dbus)，访问 2026-11-23）。
- 文本缩放：引擎读取的是 GNOME schema 的 `text-scaling-factor`；本机 KDE 对该键返回 `1`（默认值），`gtk-theme` 返回 `"Breeze"`（`busctl` 实测，2026-11-23）。这说明 KDE 的 Settings portal 会给出默认响应，但该值是否随 KDE“字体大小”设置变化仍需原型验证。Flutter 是自绘 UI，不会采用 `gtk-font-name`；因此 KDE 字体设置很可能不会改变 Flutter 文本大小。这是与 WinUI 的行为差异，需要在无障碍/界面缩放项中单列（见 §8）。
- 上游 Magpie 有 Light/Dark/System 三档主题设置；Flutter 侧直接映射到 `ThemeMode` 即可，System 档使用 `platformBrightness`。引擎侧（ImGui 覆盖层、托盘菜单）需要独立的主题/颜色逻辑，不能复用 Flutter 主题。

### 1.9 HiDPI 与分数缩放

- Flutter 的 device pixel ratio 来自 **整数** scale factor：`gtk_widget_get_scale_factor()` 返回 `gint`，并被直接传入视图几何与 `FlutterWindowMetricsEvent.device_pixel_ratio`（[`fl_view.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_view.cc) 第 189、216、798 行附近；`GdkMonitor` 的 `get_scale_factor` 同样返回 `int`，[`fl_display_monitor.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_display_monitor.cc)，访问 2026-11-23）。
- GTK3 的 `gtk_widget_get_scale_factor`/`gdk_monitor_get_scale_factor` 只返回 `gint`；Flutter 3.50 的 GTK3 嵌入器按整数使用，未使用 `wp_fractional_scale_v1`。本机 KWin 暴露了 `wp_fractional_scale_manager_v1`（`wayland-info`，2026-11-23），但 Flutter UI 不会使用它。
- 结论：
  - 在 125%/150% 缩放下，Flutter UI 只能得到 1x 或 2x 的整数 DPR；可能出现“位图被合成器缩放”的模糊，或尺寸偏大/偏小。**必须在原型中于 Plasma 6.8 的 125%/150% 下验收**，并把“UI 整数缩放、覆盖层分数缩放”视为两条独立路径。
  - 覆盖层由引擎自己的 Wayland surface + Vulkan 呈现，可以直接使用 `wp_fractional_scale_v1`（KWin 支持），因此缩放输出的清晰度不受 GTK3 限制。这正是“覆盖层必须原生”的另一个理由。
  - `GDK_SCALE` 是整数环境变量，可作为测试/规避手段，但不能提供真正的 150% 清晰渲染。

### 1.10 能力归属速查

| 能力 | Flutter Linux 内置 | 需要插件 | 需要原生代码 | 本方案归属 |
|---|---|---|---|---|
| 多窗口 | 引擎支持多 `FlView`；Dart 窗口 API 实验性 | `desktop_multi_window`（多 engine） | runner 改 `fl_view_new_for_engine` | 不需要（单设置窗口 + 原生覆盖层） |
| 托盘图标 | 无 | `tray_manager`（SNI） | GDBus SNI/DBusMenu | 引擎 |
| 全局快捷键 | 无 | `hotkey_manager`（portal/X11） | GDBus GlobalShortcuts | 引擎 |
| 文件选择器 | 无 | `file_selector`（官方，`GtkFileChooserNative`） | — | UI |
| 主题/深色 | `platformBrightness`（Settings portal） | — | 读取 accent-color | UI |
| HiDPI | 整数 DPR | — | fractional-scale（仅覆盖层） | UI（整数）/ 引擎（分数） |
| 单实例 | `GApplication` | — | runner 设置 app id/名称 | 引擎（主）/ UI（Settings） |
| 通知 | 无 | `local_notifier`（旧） | GNotification/`org.freedesktop.portal.Notification`（Flatpak 友好） | 引擎 |
| 窗口定位/置顶 | 无 | `window_manager`（Wayland 受限） | 合成器规则/不实现 | 不承诺 Wayland 下自由定位 |

### 1.11 其他桌面集成

- **通知**：Plasma 提供 `org.freedesktop.Notifications`（本机 `busctl` 可见），但 Flatpak 默认只放行 portal API。引擎应使用 GIO `GNotification`（会优先走 `org.freedesktop.portal.Notification`），或显式调用该 portal；只有在非 Flatpak 或额外声明 `--talk-name=org.freedesktop.Notifications` 时才直接使用 `org.freedesktop.Notifications`。不需要 `local_notifier`。
- **剪贴板/拖放**：Flutter 自带剪贴板；拖放（`desktop_drop`）在 Linux 上依赖 `FlView` 存在，且与实验性 multi-window 冲突（见 #191166）。本工单不依赖拖放。
- **无障碍**：Flutter Linux 通过 ATK/AT-SPI 暴露语义树（`FlViewAccessible`，见 [`fl_view.cc`](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/linux/fl_view.cc) 与 `fl_view_accessible.cc`，访问 2026-11-23）；原生托盘菜单由 SNI host 提供无障碍。ImGui 覆盖层不具备无障碍语义，这是上游既有状态。

---

## 2. 进程与通信模型选项

### 2.1 方案 A：同进程 FFI（引擎作为共享库）

Dart 通过 `dart:ffi` 加载 `libmagpie_engine.so`，在 Flutter 进程内启动引擎线程。

事实约束：

- `NativeCallable.listener` 可以从任意原生线程回调，但参数经 `SendPort` 投递、**没有返回值**，回调在未来某个时刻执行；`NativeCallable.isolateLocal` 只能在该 isolate 的 mutator thread 调用，其他线程调用会 abort（[`sdk/lib/ffi/ffi.dart`](https://github.com/dart-lang/sdk/blob/main/sdk/lib/ffi/ffi.dart)，访问 2026-11-23）。
- FFI 调用在调用线程上同步执行；长耗时调用会阻塞该 isolate 的事件循环。若在 UI isolate 调用 Vulkan 初始化（本机实测约 65–70 ms 热启动，见 §2.4），会直接造成掉帧。
- 引擎若要在同进程创建自己的 Wayland 顶层，需要第二个 `wl_display` 连接；GTK 与引擎各自是独立的 Wayland client，焦点/activation 语义更复杂。若尝试共享 GDK 的 `wl_display`，则必须把 Vulkan WSI 的事件分发塞进 GDK 的事件循环，并与 GTK 的 surface 生命周期耦合。
- 引擎崩溃 = 整个应用崩溃；Vulkan 驱动、PipeWire、DXC 编译都是高风险组件。

评价：**不推荐**。它把两个本可独立演进的运行时（GTK/Flutter 与 Vulkan/Wayland）绑死，且没有带来任何必要收益：控制消息量极小，IPC 成本可以忽略。

### 2.2 方案 B：独立短生命周期引擎进程 + Unix socket

Flutter 常驻（托盘/快捷键），每次缩放启动一个 `magpie-engine` 子进程；通过 `$XDG_RUNTIME_DIR` 下的 Unix domain socket 交换长度前缀 JSON；引擎退出即结束会话。

- 崩溃隔离：引擎崩溃不影响 UI；UI 崩溃会通过 socket 关闭使引擎退出（或反之，取决于生命周期策略）。
- 延迟：进程启动 + Vulkan 初始化约 0.1 s 量级（本机实测；portal 对话框交互占主导）；控制 RTT 在 Unix socket 上通常远低于 1 ms，但需在原型中测量。
- 权限：portal 会话必须由引擎进程发起；ScreenCast 的 `parent_window` 需要 Flutter 侧导出的 xdg-foreign handle（GTK3 提供 `gdk_wayland_window_export_handle`，见 §3.3），或传空字符串。
- 调试：两个进程、两个 gdb；协议需要自己定义与版本化；无内省。
- 打包：同一沙箱内的子进程最简单；若 UI 与引擎分别由 `flatpak run` 启动，则会落入不同 sandbox instance，Unix socket 路径是否共享需验证（见 §6.2）。
- 插件依赖：托盘/快捷键只能由 Flutter 常驻进程承担，即依赖 `tray_manager`/`hotkey_manager` → `nativeapi`（WIP）。

评价：如果产品坚持“Flutter 常驻”，这是合理选择；否则它不如方案 C 干净。

### 2.3 方案 C：常驻原生引擎 + D-Bus（推荐）

`magpie` 引擎常驻并持有 session D-Bus 名称；Flutter `magpie-ui` 是按需启动的客户端。控制面使用 D-Bus 方法/信号/属性。

理由：

1. **与锁定决策一致**：托盘、全局快捷键、覆盖层、portal 会话都是运行时职责，归引擎；Flutter 只做配置。
2. **portal 与快捷键天然属于引擎**：ScreenCast、GlobalShortcuts、SNI 都已经是 D-Bus 接口；再引入一套私有 socket 只会增加第二种 IPC 机制。
3. **单实例与激活由 `GApplication` 直接提供**：引擎以 `GApplication` 持有 app id；第二次启动自动转发到 primary，`activate` 可用来弹出设置窗口（[GApplication 文档](https://docs.gtk.org/gio/class.Application.html)，访问 2026-11-23）。
4. **可调试性最好**：`busctl --user introspect`、`dbus-monitor`、`gdbus call` 可以直接检查接口与信号；D-Bus 接口是自描述的。
5. **崩溃隔离彻底**：UI 崩溃不影响托盘、快捷键和正在进行的缩放；引擎崩溃时 UI 仍在，可显示错误并重启引擎。
6. **内存占用更合理**：Flutter 进程只在设置窗口打开时存在（引擎空闲时不加载 Dart VM/Skia）。
7. **跨 Flatpak 实例可发现**：session bus 是全局的，不同 sandbox instance 中的进程可以通过总线名称相互发现（需在清单中声明 own/talk name，见 §6.2）。

代价：

- 引擎需要实现 SNI + DBusMenu 与 GlobalShortcuts portal（约数百行 GDBus 代码）；这是本方案最主要的新增工作量。
- 引擎需要 GLib/GIO 依赖（但不是 GTK）。
- D-Bus 消息不适合承载帧数据；本方案本来也不需要（§3.4）。

### 2.4 方案对比矩阵

本机实测补充：Vulkan `vkCreateInstance` + `vkCreateDevice`（启用 `VK_KHR_wayland_surface`、`VK_KHR_swapchain`）在本机（Plasma 6.8.3，Vulkan 1.4.363，2 个物理设备）为 **65–70 ms（热）、118 ms（冷）**；不包含 swapchain、PipeWire 连接与 portal 交互。空进程 `fork+exec` 在本机 shell 的 1 ms 计时分辨率下不可测，可视为远小于 Vulkan 初始化。

| 维度 | A. 同进程 FFI（共享 GdkWindow） | A'. 同进程 FFI（自有 wl_display） | B. 短生命周期进程 + Unix socket | C. 常驻引擎 + D-Bus（推荐） | D. GTK 插件 + MethodChannel |
|---|---|---|---|---|---|
| 崩溃隔离 | 无 | 无 | 引擎崩溃隔离；UI 崩溃终止会话 | 双向隔离 | 无 |
| 首帧/启动 | 无进程开销；Vulkan 初始化（~70 ms）可放在引擎线程，但 FFI 同步调用若在 UI isolate 会卡顿；共享 surface 不可行 | 无进程开销；需自管 `wl_display` 与 GTK 事件循环 | +进程启动 +Vulkan 初始化（~0.1 s），portal 交互主导 | 引擎可预热 Vulkan instance；会话启动只建 swapchain/流 | 同 A |
| 控制延迟 | 函数调用，最低 | 同左 | Unix socket，通常 <1 ms（需实测） | D-Bus，通常 1–2 ms（需实测） | 平台通道，毫秒 |
| portal/权限 | 同进程，token 可用 | 同进程，但两个 Wayland client | 引擎发起 portal；parent handle 需跨进程传递 | 引擎独占 portal，最清晰 | 同 A |
| 调试 | 单 gdb，但线程/崩溃域混合 | 同左 | 两个 gdb + 自定义协议 | `busctl`/`dbus-monitor` + 两个 gdb | 单进程，平台通道日志 |
| Flatpak | 简单 | 简单 | 同沙箱子进程简单；跨实例需共享 runtime dir | 单沙箱；需声明 D-Bus name | 简单 |
| 实现成本 | 低（但技术债高） | 中高 | 中 | 中高（原生托盘/快捷键） | 低 |
| 结论 | 拒绝 | 拒绝 | 备选（Flutter 常驻时） | **推荐** | 拒绝 |

### 2.5 为什么不用 D-Bus 传输帧

- D-Bus 是控制总线，不是数据面；其消息大小、序列化与调度都不适合连续帧。若未来确实需要“设置界面里的静态预览”，让引擎在需要时返回一张 **PNG/JPEG 编码图**（几十 KB、低频）即可；不要为此引入 dmabuf 导入或 `FlTextureRegistrar`。
- 共享内存/`memfd` + `SCM_RIGHTS` 只在需要连续帧时才考虑（例如未来的实时预览窗口）；当前 Magpie 的配置界面没有实时预览需求（上游 `HomePage`/`ProfilePage`/`ScalingModesPage` 均无视频预览控件）。

---

## 3. GTK 主循环、Vulkan 与覆盖层

### 3.1 线程与事件循环

- Flutter：GTK 主循环 = platform thread；UI/raster 线程由 engine 管理（§1.1）。
- 引擎（推荐架构）：不链接 GTK；使用 GLib `GMainLoop`/`GMainContext` 处理 D-Bus（portal、SNI）与信号，Vulkan 呈现与 Wayland 事件在独立线程或独立 `GSource` 上处理。Wayland `wl_display` 的 fd 可以注册到 `GMainContext`（`g_source_add_unix_fd`），无需 GTK。
- 若坚持同进程：Vulkan 调用必须在非 platform 线程；GTK 调用必须 marshal 回 GTK 线程；`NativeCallable.listener` 只能做无返回值的异步通知。任何同步的 FFI 调用都会占用 UI isolate；若 UI 侧确实存在不可避免的同步原生调用（本方案不需要），应放到 `Isolate.run`/worker isolate，避免阻塞渲染与输入（[`Isolate.run`](https://api.dart.dev/dart-isolate/Isolate/run.html)，访问 2026-11-23）。工程复杂度高于拆进程，且没有性能收益（控制消息不是瓶颈）。

### 3.2 覆盖层窗口与 activation

- 覆盖层可以是：
  - `xdg_toplevel` + `set_fullscreen`；或
  - `zwlr_layer_shell_v1` 的 overlay/top layer（KWin 6.8 本机暴露 `zwlr_layer_shell_v1` version 5，`wayland-info`，2026-11-23）。
- 若使用 `xdg_toplevel`，聚焦/置顶受 KWin 的 focus-stealing prevention 约束。`xdg_activation_v1` 的 token 可以跨客户端传递（例如通过 `XDG_ACTIVATION_TOKEN` 环境变量传给新启动的子进程），但 token 可能因发起者未聚焦而无效；协议明确说明客户端无法得知 token 是否有效（[xdg-activation 协议](https://wayland.app/protocols/xdg-activation-v1)，访问 2026-11-23）。
- 因此：
  - 引擎由 UI 或启动器**在用户动作后立即启动**时，应把可用的 activation token 通过环境变量传入（若启动器提供）；引擎读取后应立即 unset，避免向子进程传播。
  - 若覆盖层使用 layer-shell，则不需要“抢焦点”即可置于最上层；但键盘交互（ImGui 工具栏）需要显式请求 keyboard interactivity，且是否获得焦点仍由合成器决定。该选择属于覆盖层/呈现票据（KwinCapture），本报告只指出它决定“是否需要 activation 链路”。
  - **设置窗口**的激活是另一个问题：若 UI 由引擎按需启动，新窗口通常会被 KWin 聚焦；若 UI 已存在并被隐藏，再 `present()` 可能被拒绝。建议 UI 关闭即退出、每次重新启动，避免“隐藏再唤起”的 activation 难题。

### 3.3 portal 父窗口

- `ScreenCast.Start(parent_window)` 的 `parent_window` 在 Wayland 下必须是 `wayland:<handle>`，handle 来自 xdg-foreign（[Window Identifiers](https://flatpak.github.io/xdg-desktop-portal/docs/window-identifiers.html)，访问 2026-11-23）。
- GTK3 提供 `gdk_wayland_window_export_handle()`（GDK 3.22+，使用 `zxdg_exporter_v2`/v1；本机头文件与 `libgdk-3.so.0` 符号均存在），因此 Flutter runner 可以把设置窗口的 handle 导出并传给引擎（[`gdkwindow-wayland.c`](https://github.com/GNOME/gtk/blob/gtk-3-24/gdk/wayland/gdkwindow-wayland.c)，访问 2026-11-23）。
- 但这不是必需：portal 允许 `parent_window` 为空字符串。若引擎在选源时还没有自己的窗口，传空即可；若希望对话框附着在设置窗口上，则由 UI 导出 handle 并通过 D-Bus 传给引擎。**建议 v1 传空，减少跨进程细节；原型阶段再验证是否需要附着。**
- 本机 KWin 暴露 `zxdg_exporter_v2`/`zxdg_importer_v2`（`wayland-info`，2026-11-23），所以该路径在 KWin 上可行。

### 3.4 帧数据是否需要进入 Flutter

**不需要。** 理由：

1. 锁定决策：Flutter 只渲染配置界面；缩放结果由引擎的全屏覆盖层呈现。
2. 上游配置界面没有实时预览；只有设置项、效果参数、快捷键、主题、日志等。
3. Flutter 在 Wayland 下用 subsurface 呈现，本身不是可共享纹理；跨进程导入 dmabuf 需要 `FlTextureRegistrar`（GL）与 EGL 图像扩展，复杂且没有收益。
4. 若将来要显示“当前源窗口缩略图”，由引擎在低频请求下返回编码后的 PNG（或写入临时文件并返回路径），Flutter 用 `Image.memory`/`Image.file` 显示即可。

唯一的例外是“覆盖层内的 ImGui 预览/调试视图”，那属于引擎自己的 Vulkan 渲染，不经过 Flutter。

---

## 4. 插件与依赖维护状态

| 包/组件 | 版本（发布） | 维护状态 | Linux 关键事实 | 本方案是否使用 |
|---|---|---|---|---|
| `tray_manager` | 0.9.1（2026-11-22） | `leanflutter`，活跃；已改为 `nativeapi` FFI 核心；README 称 `nativeapi` 为 WIP | SNI over D-Bus；面板接管点击，Linux 无图标点击事件；需 GTK3/X11/Xi 头文件构建 | 否（引擎用 GDBus 实现 SNI） |
| `window_manager` | 0.7.1（2026-11-22） | 活跃；已改为 `nativeapi` FFI；无平台插件代码 | Wayland 下 `grabKeyboard` 返回 false；客户端不能定位窗口；frameless 的阴影主要针对 X11/XWayland | 否（GTK runner 直接设置窗口属性） |
| `hotkey_manager` | 0.4.1（2026-11-22） | 活跃；`nativeapi` FFI | 原生 Wayland 用 GlobalShortcuts portal；桌面可改写/拒绝绑定；KDE 提供对话框 | 否（引擎直接使用 portal） |
| `desktop_multi_window` | 0.3.1（2026-08-26） | `MixinNetwork/flutter-plugins`，活跃但非官方；SDK 约束 `>=3.5.0 <4.0.0` | 每个窗口新建 `FlView` + 新 engine；同进程多 Dart VM；需绕过 delete-event | 否 |
| `local_notifier` | 0.1.6（2024-04-05） | 低活跃（仓库最后提交 2025-03） | Linux 依赖 `libnotify` | 否（引擎用 `org.freedesktop.Notifications`） |
| `file_selector` | 1.1.0（2025-11-21） | 官方 `flutter/packages`，活跃 | `GtkFileChooserNative`；支持打开/保存/目录 | **是**（UI） |
| `dbus` | 0.8.1（2026-11-19） | Canonical，MPL-2.0，活跃 | 纯 Dart D-Bus 客户端 | **是**（UI 连接引擎、读取 accent-color） |
| `nativeapi` | 0.6.x（2026-11-22） | `libnativeapi/nativeapi`，README 自述 “Work In Progress” | 统一 C++ 核心，托盘/窗口/快捷键/对话框 | 仅当采用方案 B 时被动依赖 |

结论：

- **推荐架构下，Flutter 侧只保留 `file_selector` 与 `dbus` 两个依赖**；托盘、快捷键、窗口管理、通知全部由引擎原生实现。这样避免把 `nativeapi`（WIP）作为生产关键路径。
- 如果必须复用 `tray_manager`/`hotkey_manager`，必须把它们封装在 UI 内部的 `TrayService`/`ShortcutService` 接口之后，并锁定版本；`nativeapi` 的 API 与二进制分发方式（FFI 核心库的构建/打包）需要在原型中验证。
- `window_manager` 的 Wayland 能力不足以支撑“自定义标题栏 + 任意定位”的完整 WinUI 视觉复刻；若追求像素级一致，应评估由 GTK runner 实现 frameless + CSD 的可行性，而不是依赖该插件。

---

## 5. 推荐架构细节

### 5.1 进程与组件

```
┌──────────────────────────────┐        session D-Bus        ┌──────────────────────────────┐
│ magpie (native engine)       │◀───────────────────────────▶│ magpie-ui (Flutter)          │
│  GApplication, app id        │  methods / signals / props  │  GtkApplication (Settings)   │
│  - config store + schema     │                             │  - settings pages            │
│  - portal ScreenCast         │                             │  - effect param widgets      │
│  - portal GlobalShortcuts    │                             │  - file_selector             │
│  - SNI tray + DBusMenu       │                             │  - theme / accent color      │
│  - Vulkan overlay + ImGui    │                             │  - logs view                 │
│  - PipeWire / DXC / cache    │                             │                              │
└──────────────┬───────────────┘                             └──────────────────────────────┘
               │ owns
     ┌─────────┴──────────┬───────────────────┐
     │ xdg-desktop-portal │ KWin / Wayland    │
     │ (ScreenCast,       │ (wl_surface,      │
     │  GlobalShortcuts)  │  layer-shell)     │
     └────────────────────┴───────────────────┘
```

- **入口**：桌面文件 `Exec=magpie`。`magpie` 是引擎；首次启动注册 `GApplication`、托盘、快捷键，并 `spawn` `magpie-ui` 显示设置窗口。
- **启动 UI 的环境**：引擎 spawn 时应显式设置 `GDK_BACKEND=wayland`（首版仅支持 Wayland），避免 GDK 回退到 XWayland，导致 app_id、分数缩放与 activation 行为不一致。
- **第二次启动**：`GApplication` 检测到已有 primary，转发 `activate`，新进程退出；primary 负责显示/聚焦设置窗口（若 UI 不存在则启动）。
- **UI 关闭**：Flutter 进程退出；引擎继续驻留托盘。用户从托盘“退出”才结束引擎。
- **引擎退出**：关闭 portal 会话、销毁覆盖层、注销 SNI 与快捷键、退出 `GMainLoop`。

### 5.2 生命周期与崩溃处理

- 引擎崩溃：D-Bus 名称消失；UI 若在运行，检测到 name-owner-changed/方法失败，显示错误并提供“重启引擎”。UI 可通过 `GApplication` 的 spawn 逻辑重启引擎（同一 bundle 内的 `magpie`），或提示用户从菜单重启。
- UI 崩溃：引擎不受影响；下一次“设置”动作重新启动 UI。
- 会话崩溃（引擎内的 Vulkan/PipeWire 线程）：引擎可选择只结束当前会话并回到 idle；若整个进程崩溃，则托盘/快捷键一并消失，UI 显示错误。**建议引擎把“会话”与“控制面”分离：控制面绝不因会话错误退出**。
- 日志：引擎写 `$XDG_STATE_HOME/magpie/log`（Flatpak 下 `~/.var/app/<id>/state/...`），同时通过 D-Bus `Log` 信号发送限流的最近日志；UI 显示尾部并支持“打开日志目录”（`file_selector` 不适用，直接调用 `xdg-open`/`QDesktopServices` 等价物；Dart 用 `url_launcher` 或 `Process.start('xdg-open')`）。
- 调试成本：UI 继续使用 `flutter attach`/DevTools；引擎使用 gdb、Vulkan validation layers、RenderDoc；D-Bus 接口用 `busctl introspect`、`dbus-monitor`。两个进程独立重启，定位问题时不需要重启另一个。

### 5.3 D-Bus 接口草案

- 名称：`io.github.qxy0happy.Magpie`（与 Flatpak app id、desktop 文件 basename 一致；引擎通过 `GApplication` 持有）。
- 对象：`/io/github/qxy0happy/Magpie/Engine`
- 接口：`io.github.qxy0happy.Magpie.Engine1`

属性：

| 属性 | 类型 | 说明 |
|---|---|---|
| `Version` | `s` | 引擎版本 |
| `ProtocolVersion` | `u` | IPC 协议版本 |
| `ConfigRevision` | `u` | 配置乐观并发版本 |
| `State` | `s` | `idle` / `selecting` / `scaling` / `error` |
| `Capabilities` | `as` | 例如 `screencast-window`、`global-shortcuts`、`fractional-scale` |

方法：

| 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `GetSnapshot` | — | `s config_json, s effects_json, s system_json` | 一次性返回配置、效果目录、GPU/显示器/版本等 |
| `ApplyConfig` | `s config_json, u expected_revision` | `u new_revision` | 引擎校验并原子写入；冲突返回错误 |
| `ReloadConfig` | — | `u new_revision` | 外部修改后重载 |
| `StartScaling` | `s profile_id, s mode` | `o session_path` | 触发 portal 选源并启动覆盖层；异步进度用信号 |
| `StopScaling` | `o session_path` | — | 结束会话 |
| `TakeScreenshot` | `o session_path` | `s path` | 由引擎保存 |
| `SetTrayVisible` | `b` | — | 对应上游 `ShowNotifyIcon` |
| `GetLogTail` | `u lines` | `as` | 最近日志 |
| `Quit` | — | — | 退出引擎（托盘“退出”） |

信号：

| 信号 | 参数 | 说明 |
|---|---|---|
| `StateChanged` | `s state, s detail` | 选源/缩放/错误 |
| `SessionStarted` | `o session_path, s title, u width, u height` | 选源成功、覆盖层已创建 |
| `SessionEnded` | `o session_path, s reason` | 正常结束、用户取消、错误 |
| `Stats` | `a{sv}` | 1 Hz 的 FPS/帧时间/分辨率（仅在 scaling 时） |
| `ConfigChanged` | `u new_revision` | 其他客户端或外部修改 |
| `Log` | `s line` | 限流日志 |

错误：使用 D-Bus error（`io.github.qxy0happy.Magpie.Error.Failed` 等），并附带人类可读消息；UI 负责本地化展示。

- **不要**在 D-Bus 上传帧；`Stats` 只传数值。
- 大配置（含效果参数）以 JSON 字符串传递；单条消息远低于 D-Bus 上限。若未来配置超过数 MB，再考虑分片或改用文件路径（同一沙箱可读）。

### 5.4 配置所有权与 schema

- **引擎是配置的唯一权威**：读取、校验、迁移、持久化、向 UI 提供 JSON 文档；UI 不直接写配置文件。
- 磁盘格式：`$XDG_CONFIG_HOME/magpie/config.json`（Flatpak：`~/.var/app/<id>/config/magpie/config.json`），带 `schema_version`、`profiles`、`scaling_modes`、`shortcuts`（期望值）、`theme`、`language` 等。上游 `AppSettings` 已使用 rapidjson 持久化 JSON（`src/Magpie/AppSettings.cpp`），迁移时可保留字段语义。
- UI 侧模型由 `config.schema.json` 生成（Dart `json_serializable`）或手写并加 CI 校验；C++ 侧继续用 rapidjson + 显式校验。**建议在仓库根放置单一 `config.schema.json`**，CI 做 Dart/C++ 双向 round-trip 与默认值一致性检查。这是避免“两个实现漂移”的最低成本手段。
- 效果参数元数据：引擎解析 MagpieFX/HLSL 注解后，通过 `GetSnapshot` 返回参数描述（名称、类型、范围、默认值、是否可动画、本地化标签）。UI 只做通用控件渲染，不解析 HLSL。这与上游 `EffectHelper`/`ScalingModesPage` 的职责划分一致。
- 快捷键：配置里保存“用户期望的组合键”；实际绑定以 portal 返回为准。UI 必须展示“当前实际绑定”，并在 portal 改写时提示用户。引擎重新注册后通过 `GetSnapshot`/`ConfigChanged` 同步。

### 5.5 本地化边界

- Flutter UI：ARB + `gen-l10n`，运行时切换语言；覆盖所有设置页、对话框、错误消息。
- 引擎：托盘菜单、通知、覆盖层/ImGui 文案、效果参数标签需要独立本地化。上游 `.resw`（20+ 语言）不能直接被 Flutter 使用。
- 建议单一源（JSON/CSV）生成 ARB 与引擎的 gettext/JSON 目录；在 CI 中检查键集合一致。该工作属于本地化票据，但**必须在架构上承认“两套运行时、两套字符串”**，否则托盘菜单会成为遗漏点。
- 引擎的 D-Bus 错误应返回稳定 error name + 参数，由 UI 本地化；不要把已翻译字符串作为协议内容。

### 5.6 单实例与窗口身份

- 引擎：`GApplication` + app id `io.github.qxy0happy.Magpie`，持有 session bus 名称；第二次启动由 GApplication 转发 `activate`，primary 负责显示设置窗口。若需要 `--profile`、`--start` 等 CLI 参数在第二次启动时也转发，引擎必须使用 `G_APPLICATION_HANDLES_COMMAND_LINE` 并在 `command-line` 信号中解析；仅 `activate` 不携带 argv。
- UI：`GtkApplication` + **独立** app id `io.github.qxy0happy.Magpie.Settings`，保持唯一性并注册自己的 D-Bus 名称；第二次运行 `magpie-ui` 会转发到已有实例并聚焦窗口。
  - 窗口的 shell 身份（Wayland app_id）设为 `io.github.qxy0happy.Magpie`，使任务栏图标/分组与主 desktop 文件一致。GDK3 提供 `gdk_wayland_window_set_application_id()`（本机头文件，GDK 3.24）；在 runner 中创建窗口后显式调用它，或让 `g_get_prgname()` 返回主 id。不要沿用模板把 `application-id`（应为 Settings）与 `g_set_prgname` 都设为同一个值。
  - 因此不需要为 Settings 单独提供可见的 desktop 文件；主 desktop 文件即可承载图标与名称。
- 托盘“设置”动作：引擎直接 `spawn` `magpie-ui`；若 UI 已经存在，`GtkApplication` 的唯一性会把新进程转成对 primary 的 `Activate`，从而聚焦已有窗口。**UI 关闭即退出**，不隐藏；这样避免“隐藏窗口再激活”的 Wayland 焦点问题。
- 若用户直接运行 `magpie-ui` 而引擎尚未启动：UI 应检测 `io.github.qxy0happy.Magpie` 是否在总线上；若不在，按 bundle 相对路径启动引擎（`magpie --daemon`），等待名称出现后再继续。该恢复路径需要防止重复启动（引擎自身的 `GApplication` 唯一性即可兜底）。
- KWin 对“由另一个进程发起的 Activate”是否授予焦点仍需原型验证（见 §8）；失败时的退路是 UI 退出并重新启动（新窗口通常会被聚焦）。

---

## 6. 打包与运行约束

### 6.1 Flutter Linux 产物

- `flutter build linux --release` 产物位于 `build/linux/x64/release/bundle/`：可执行文件 + `lib/`（`libapp.so`、`libflutter_linux_gtk.so`、插件库）+ `data/`（assets）（[Flutter Linux 构建文档](https://docs.flutter.dev/platform-integration/linux/building)，访问 2026-11-23）。
- Flutter 官方 Linux 分发文档给出的是“保留整个 bundle + 系统依赖”与 Snap Store 发布路径，deb/rpm 依赖第三方指南；**没有 Flatpak/AppImage 的官方模板**，清单需要自行维护。这提高了打包票据的权重。
- 本机 Flutter 3.50.1 的 `libflutter_linux_gtk.so` 为 **42 MB**，动态依赖包括 GTK3/GDK3、GLib/GIO、X11 系列、EGL/OpenGL、fontconfig/freetype、dbus-1 等（`ldd`，2026-11-23）。即使只在 Wayland 运行，Flutter 引擎仍链接 X11 库；Flatpak runtime 已包含这些库。
- 模板设置 `CMAKE_INSTALL_RPATH "$ORIGIN/lib"`（本机 SDK `linux.tmpl/CMakeLists.txt.tmpl`），因此 **bundle 目录必须整体保留相对布局**。
- 推荐 bundle 布局（引擎与 UI 同级，保证 Flutter 能找到 `data/` 与 `lib/`）：

```
bundle/
  magpie            # 原生引擎（desktop Exec）
  magpie-ui         # Flutter 设置客户端
  lib/              # Flutter 引擎、libapp.so、插件库、libdxcompiler.so、libpipewire...
  data/             # flutter_assets
```

  若发行版要求 `/usr/bin`，使用 wrapper 脚本 `exec /usr/lib/magpie/magpie "$@"`；`/proc/self/exe` 指向真实引擎，其同级 `magpie-ui`/`data`/`lib` 仍正确。Flatpak 同理：bundle 安装到 `/app/magpie/`，`/app/bin/magpie` 为 wrapper（或直接把整个 bundle 放 `/app/bin`）。

- 引擎的共享库依赖：`libvulkan.so.1`（不要随包发布 ICD/驱动）、`libwayland-client`、`libpipewire-0.3`、`libdxcompiler.so`、GLib/GIO。为引擎设置 `RPATH=$ORIGIN` 或 `$ORIGIN/lib`。
- DXC：`libdxcompiler.so` 体积较大；可静态链接或随包发布，需在构建票据中量化体积与启动加载时间。效果缓存与 DXC 属于 CoreInventory 范围，本报告只声明打包位置。

### 6.2 Flatpak

- 基本权限（[Flatpak Sandbox Permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html)，访问 2026-11-23）：
  - `--socket=wayland`（必需）；如需 X11 回退：`--socket=fallback-x11 --share=ipc`；
  - `--device=dri`（GPU/DRM；Vulkan 与 OpenGL 必需）；
  - 不需要 `--filesystem=host`；配置文件在 `~/.var/app/<id>/`；
  - session D-Bus 默认被过滤，但 portal API 与“应用自己的名称”可用；必要时在 `finish-args` 中显式声明 `--own-name=io.github.qxy0happy.Magpie`、`--own-name=io.github.qxy0happy.Magpie.Settings`、`--talk-name=org.kde.StatusNotifierWatcher`（托盘），以及两端互通的 `--talk-name`。
- Portal 在沙箱内可用；ScreenCast/GlobalShortcuts 的权限由 portal 对话框授予，PipeWire fd 通过 portal 传入沙箱。
- **推荐**引擎与 UI 处于同一 Flatpak 实例：由引擎 `spawn` UI 子进程即可保证。若分两次 `flatpak run`，D-Bus 仍可发现对方，但 Unix socket/临时文件不共享，document portal 文件句柄与 `parent_window` 的处理更复杂。
- `file_selector` 返回的 document portal 路径在同一沙箱内可读，引擎可直接加载用户导入的效果文件。
- Vulkan loader 由 runtime 提供；驱动由 `org.freedesktop.Platform.GL.*` 扩展提供（NVIDIA 专有驱动另有扩展）。**不要把 `libvulkan.so.1` 或 Mesa 驱动打进应用**，否则会与 runtime/宿主冲突。
- 自动启动：地图把“Windows 专属的自动启动”排除；Linux 的 XDG autostart 是否作为功能保留需在打包/产品票据中确认。推荐 v1 **不做登录自启**：用户从菜单启动 `magpie`，引擎驻留托盘；这样也避免 Flatpak 的 autostart 复杂度。

### 6.3 AppImage

- AppImage 依赖 FUSE 2（`libfuse2`）；没有 FUSE 时可用 `--appimage-extract-and-run`（[AppImage FUSE 文档](https://docs.appimage.org/user-guide/troubleshooting/fuse.html)，访问 2026-11-23）。
- AppImage 不在沙箱内：portal 仍可用，但应用身份取决于已安装的 `.desktop` 文件；ScreenCast 的 `restore_token`/权限存储按 app id 关联，未安装桌面文件时可能无法稳定恢复权限。**这是 AppImage 的主要风险**，需在原型中验证；Flatpak 应作为首选发行格式。
- Vulkan loader/驱动应使用宿主；GTK3 与 Flutter 依赖可随包或依赖宿主，需在目标发行版矩阵中验证。
- AppImage 同样要求 bundle 相对布局；建议 `usr/lib/magpie/{magpie,magpie-ui,lib,data}` + `AppRun` wrapper。

### 6.4 其他格式

- 发行版包（AUR/Arch、Fedora、Debian）：把 bundle 放 `/usr/lib/magpie`，`/usr/bin/magpie` wrapper；桌面文件、图标、AppStream 元数据由打包脚本提供。
- Snap：Flutter 官方文档提到 Snap Store 发布，但 Snap 的 confinement 与 portal/GPU 组合需要单独验证；不作为首版目标。

---

## 7. 风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| `nativeapi` 为 WIP（若采用 Flutter 托盘/快捷键） | 生产关键路径依赖未稳定 API/二进制 | 推荐架构不使用；若使用则封装接口、锁版本、准备 GDBus 备选 |
| Flutter 多窗口 API 实验性 + Linux headless 缺陷 | 不能依赖官方多窗口；`desktop_multi_window` 多 engine 成本高 | 单 Flutter 窗口；原生覆盖层；未来用 `fl_view_new_for_engine` |
| GTK3 整数缩放 | 125%/150% 下 UI 模糊或尺寸不符 | 原型验收；提供 UI 缩放设置；覆盖层用 fractional-scale 协议 |
| Wayland focus/activation | 覆盖层或设置窗口无法获得焦点 | 覆盖层优先 layer-shell；UI 关闭即退出、重新启动；传递 `XDG_ACTIVATION_TOKEN`（若可得） |
| portal 选窗失败/用户取消 | 无法开始缩放 | 引擎把 portal 错误映射为稳定 error name；UI 展示可操作的提示 |
| Flatpak D-Bus own/talk name 策略 | 引擎与 UI 无法互相发现 | 清单显式声明名称；原型中 `flatpak run` 验证；备选同沙箱 Unix socket |
| Flatpak StatusNotifier 权限 | 托盘不显示；若申请 `org.kde.*` 则引入冒充风险 | SNI item 注册在应用自身总线名下；仅申请 `--talk-name=org.kde.StatusNotifierWatcher`；托盘不作为唯一入口 |
| Flatpak 通知权限 | 直接调用 `org.freedesktop.Notifications` 可能被拒 | 使用 `GNotification`/`org.freedesktop.portal.Notification`；必要时声明 talk-name |
| AppImage 无桌面文件 | portal 权限/restore token 不稳定 | Flatpak 首选；AppImage 提供 `.desktop` 安装说明 |
| 配置 schema 双实现漂移 | UI 与引擎对字段理解不一致 | 单一 `config.schema.json` + CI round-trip；引擎权威校验 |
| 效果元数据/本地化双运行时 | 托盘/覆盖层字符串遗漏、参数标签不一致 | 单一字符串源生成 ARB + 引擎目录；CI 键集合检查 |
| 引擎依赖 GLib/PipeWire/DXC | 打包体积与运行时依赖增加 | 明确 bundle 内容；Flatpak runtime 复用；体积在构建票据中量化 |
| 引擎崩溃导致托盘/快捷键消失 | 用户失去入口 | UI 检测并重启；引擎控制面与会话分离；日志/通知 |
| 上游功能中 Windows 专属项 | 误做 parity | 明确排除：更新器、触控助手、Win32 互操作、管理员启动、Windows 自动启动；触摸支持不迁移 |

---

## 8. 开放问题与原型验收

必须在后续 HITL/原型票据中回答：

1. **设置窗口的激活**：KWin 6.8 下，由托盘菜单启动/唤起 Flutter 窗口是否会被聚焦？`org.freedesktop.Application.Activate` 的 platform_data 是否携带 activation token，以及引擎能否通过 `XDG_ACTIVATION_TOKEN` 把它传给新启动的 UI 子进程？
2. **Flatpak 跨实例 D-Bus**：同一 app id 的多个 sandbox instance 之间，own/talk name 的默认策略与显式 `finish-args` 是否足够？若不足，第二实例无法发现 primary；需要在 launcher 中增加 lock file/`flock` 兜底，或改为只允许引擎作为唯一入口。
3. **125%/150% 缩放**：Flutter UI 的实际 DPR、字体清晰度、窗口尺寸；是否需要应用内 UI scale。
4. **portal `parent_window`**：空字符串在 KDE 下是否导致对话框层级/焦点问题；是否需要从 GTK runner 导出 xdg-foreign handle。
5. **GlobalShortcuts 的 KDE 交互**：`BindShortcuts` 对话框的文案、用户拒绝/改写后的 UI 表达；快捷键冲突处理。
6. **UI 视觉壳**：GTK CSD 标题栏 vs frameless + Flutter 自绘标题栏；后者在 Wayland 下的 resize/阴影/最大化行为需要单独验证。
7. **配置 schema**：是否采用 JSON Schema + 代码生成；迁移上游字段的映射表。
8. **本地化管线**：`.resw` → ARB + 引擎目录的生成器与 CI 校验。
9. **引擎控制面线程模型**：GMainContext 与 Vulkan/Wayland 线程的边界；D-Bus 方法不得阻塞渲染线程。
10. **预览需求**：产品是否真的需要设置界面中的静态预览；若需要，按“低频 PNG over D-Bus/文件”设计，不引入 dmabuf。
11. **功能范围**：Linux 是否保留“portable mode”（配置写在可执行文件旁）与“登录自启”；两者与 Windows 实现机制不同，需要产品明确。地图只明确排除了 Windows 专属的自动启动机制。

原型最小验收（建议下一个工单）：

- 一个 `GApplication` 引擎进程：注册 SNI 托盘、GlobalShortcuts 会话、一个自定义 D-Bus 接口；`activate` 启动一个 Flutter 窗口。
- Flutter 窗口：通过 `dbus` 包调用 `GetSnapshot`、`ApplyConfig`、`StartScaling`、`StopScaling`；显示状态与日志尾部；使用 `file_selector` 选择一个目录。
- 在 Plasma 6.8 Wayland 下验证：托盘菜单、快捷键 portal 对话框、portal 选窗、全屏覆盖层（可先用纯色 Vulkan 清屏）、引擎崩溃后 UI 报错、UI 关闭后引擎驻留。
- 在 Flatpak 中重复上述流程；记录 Vulkan 初始化、UI 冷启动、D-Bus RTT、内存占用。
- 在 100%/125%/150% 缩放下截图对比 UI 与覆盖层清晰度。

---

## 9. 对地图其他票据的接口约束

- **KwinCapture / 覆盖层**：引擎必须拥有自己的 `wl_display` 与 `wl_surface`；不要把 Vulkan 呈现塞进 GTK/`FlView` 的 surface。覆盖层是否使用 layer-shell、如何获取焦点，会决定是否需要 xdg-activation 链路。
- **CoreInventory / 效果**：效果元数据必须通过引擎的 `GetSnapshot` 暴露给 UI；UI 不解析 HLSL。DXC 与 `libdxcompiler.so` 的打包位置由本报告的 bundle 布局约束。
- **LinuxPackaging**：bundle 必须保持 `magpie`/`magpie-ui`/`lib`/`data` 同级；Flatpak 首选，AppImage 需验证 app id/桌面文件；Vulkan loader 不随包。
- **配置/领域模型**：配置权威在引擎；UI 是远程编辑器；需要单一 schema 与迁移策略。
- **本地化**：两套运行时、两套字符串目录；需要统一源与 CI 校验。

---

## 10. 来源

以下均为 2026-11-23 访问。

**Flutter 官方文档与源码**

- Flutter Linux 平台页：<https://docs.flutter.dev/platform-integration/linux>
- Flutter Linux 构建与分发：<https://docs.flutter.dev/platform-integration/linux/building>
- Flutter 桌面支持：<https://docs.flutter.dev/platform-integration/desktop>
- Flutter 架构概览（embedder/线程）：<https://docs.flutter.dev/resources/architectural-overview>
- Linux embedder 源码目录：<https://github.com/flutter/flutter/tree/master/engine/src/flutter/shell/platform/linux>
  - `fl_application.cc`、`fl_view.cc`、`fl_engine.cc`、`fl_task_runner.cc`、`fl_settings_portal.cc`、`fl_settings_handler.cc`、`fl_display_monitor.cc`
  - `config/BUILD.gn`（`gtk+-3.0`）
- Flutter 多窗口实验 API：`packages/flutter/lib/src/widgets/_window.dart`（本机 Flutter 3.50.1 SDK）
- 多窗口 checklist：<https://github.com/flutter/flutter/issues/177586>
- Linux headless bootstrap 缺陷：<https://github.com/flutter/flutter/issues/191166>
- Linux 多窗口原生句柄缺失（已关闭）：<https://github.com/flutter/flutter/issues/189859>
- `dart:ffi` / `NativeCallable`：<https://github.com/dart-lang/sdk/blob/main/sdk/lib/ffi/ffi.dart>
- `Native.isLeaf`（同步、非阻塞语义）：<https://api.dart.dev/main/latest/dart-ffi/Native/isLeaf.html>

**GTK / GLib**

- `GApplication`（单实例、D-Bus）：<https://docs.gtk.org/gio/class.Application.html>
- `gdk_wayland_window_export_handle`（GTK3 xdg-foreign）：<https://github.com/GNOME/gtk/blob/gtk-3-24/gdk/wayland/gdkwindow-wayland.c>
- GTK3 `gtk_widget_get_scale_factor` 返回 `gint`：`/usr/include/gtk-3.0/gtk/gtkwidget.h`（本机 GTK 3.24.52）
- `GtkFileChooserNative`：<https://docs.gtk.org/gtk3/class.FileChooserNative.html>
- `file_selector_linux` 源码：<https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector_linux>

**XDG Desktop Portal**

- ScreenCast（v6）：<https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html>
- GlobalShortcuts（v2）：<https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html>
- Settings（color-scheme/accent-color/contrast）：<https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html>
- Window Identifiers（`parent_window` 格式）：<https://flatpak.github.io/xdg-desktop-portal/docs/window-identifiers.html>
- KDE 实现：<https://github.com/KDE/xdg-desktop-portal-kde>（`src/globalshortcuts.cpp`、`GlobalShortcutsDialog.qml`、`ScreenChooserDialog.qml`、`PipeWireDelegate.qml`）

**Wayland / Vulkan**

- `xdg-activation-v1`：<https://wayland.app/protocols/xdg-activation-v1>
- `VkWaylandSurfaceCreateInfoKHR`：<https://github.com/KhronosGroup/Vulkan-Headers/blob/main/include/vulkan/vulkan_wayland.h>

**插件/包**

- `tray_manager`：<https://github.com/leanflutter/tray_manager> ；<https://pub.dev/packages/tray_manager>
- `window_manager`：<https://github.com/leanflutter/window_manager> ；<https://pub.dev/packages/window_manager>
- `hotkey_manager`：<https://github.com/leanflutter/hotkey_manager> ；<https://pub.dev/packages/hotkey_manager>
- `desktop_multi_window`：<https://pub.dev/packages/desktop_multi_window> ；<https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/desktop_multi_window>
- `local_notifier`：<https://github.com/leanflutter/local_notifier> ；<https://pub.dev/packages/local_notifier>
- `nativeapi`（WIP）：<https://github.com/libnativeapi/nativeapi>
- `dbus`：<https://pub.dev/packages/dbus>
- `file_selector`：<https://pub.dev/packages/file_selector>

**打包**

- Flatpak 沙箱权限：<https://docs.flatpak.org/en/latest/sandbox-permissions.html>
- Flatpak 运行时：<https://docs.flatpak.org/en/latest/available-runtimes.html>
- AppImage FUSE：<https://docs.appimage.org/user-guide/troubleshooting/fuse.html>

**本机实测（2026-11-23，Plasma 6.8.3 / KWin Wayland / Flutter 3.50.1）**

- `busctl --user get-property org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.ScreenCast AvailableSourceTypes` → `u 7`（MONITOR|WINDOW|VIRTUAL）
- `... AvailableCursorModes` → `u 7`；`... ScreenCast version` → `u 6`
- `... GlobalShortcuts version` → `u 2`；`... RemoteDesktop version` → `u 2`
- `... Settings.Read org.freedesktop.appearance color-scheme` → `v v u 2`
- `... Settings.Read org.freedesktop.appearance accent-color` → `v v (ddd) 0.239216 0.682353 0.913725`
- `... Settings.Read org.gnome.desktop.interface text-scaling-factor` → `v v d 1`；`gtk-theme` → `v v s "Breeze"`
- `wayland-info` → `zxdg_exporter_v2` v1、`zxdg_importer_v2` v1、`zwlr_layer_shell_v1` v5、`wp_fractional_scale_manager_v1` v1、`xdg_activation_v1` v1
- `busctl --user list` → `org.kde.StatusNotifierWatcher`、`org.freedesktop.Notifications`
- `ldd libflutter_linux_gtk.so` → GTK3/GDK3、X11、EGL、fontconfig、dbus-1 等；文件大小 42 MB
- Vulkan 探针（`vkCreateInstance` + `vkCreateDevice`，启用 wayland/swapchain 扩展）：热启动 65–70 ms，冷启动 118 ms（10 次中位数约 67 ms）

---

## 11. 决策记录（本票产出）

- **采用**：常驻原生引擎（`GApplication`，无 GTK）+ 按需 Flutter 设置客户端；session D-Bus 控制面；引擎独占 portal/托盘/快捷键/覆盖层/配置。
- **拒绝**：同进程 FFI；Vulkan 呈现到 Flutter/GTK surface；Flutter 多窗口 API；`desktop_multi_window`；`local_notifier`；把 `nativeapi` 放入生产关键路径。
- **保留使用**：`file_selector`（UI）、`dbus`（UI）。
- **交付给其他票据**：overlay 的 layer-shell/activation 选择（KwinCapture）；效果元数据与 DXC 打包（CoreInventory）；Flatpak/AppImage 布局与验证（LinuxPackaging）；配置 schema 与本地化管线（领域模型/本地化票据）。
