# KWin Wayland 下逐窗口捕获与全屏覆盖的可行性边界

- Ticket: Qxy0happy/Magpie#2
- 调研日期：2026-11-23（下文中所有 URL 的访问日期均为该日）
- 调研环境：KDE Plasma 6.8.3 / KWin 6.8.3 / Wayland 会话（`XDG_SESSION_TYPE=wayland`，`XDG_CURRENT_DESKTOP=KDE`），AMD Radeon 780M（radeonsi），单块已启用输出 DP-2（3840x2160，scale 2，HDR enabled），另一块 eDP-1 disabled。

---

## 1. 结论：锁定交互模型的可行边界

锁定模型是「xdg-desktop-portal ScreenCast 选源窗口 → 原生全屏覆盖层呈现放大结果」。逐项结论：

| 能力 | 结论 | 一句话说明 |
|---|---|---|
| 用户用 portal 选择一个源**窗口** | **可行** | `types=WINDOW`（bit 2），`multiple=false` 即单选；KDE 后端提供缩略图选择对话框 |
| 捕获被遮挡 / 最小化 / 位于其它虚拟桌面的窗口 | **可行** | KWin 用 `WindowScreenCastSource` 离屏渲染该窗口的 scene item，与可见性无关 |
| 长期保存授权（免每次弹窗） | **可行，但有条件** | `persist_mode=2` + `restore_token`（单次使用）；恢复靠 appId + 标题模糊匹配，可能失配 |
| 在指定输出上呈现全屏覆盖层 | **可行** | `wlr-layer-shell-unstable-v1`（KWin 实现 v5），`get_layer_surface` 直接指定 `wl_output` |
| 覆盖层真正置顶（含覆盖他人全屏窗口） | **可行（仅 layer-shell）** | layer-shell `overlay` 映射到 KWin 的 `OverlayLayer`，是枚举中最高层；`xdg_toplevel` 全屏做不到 |
| 普通 `xdg_toplevel` 全屏到指定输出 | **可行但不可置顶** | `set_fullscreen(wl_output)` 被尊重，但失焦后落到 `NormalLayer`，会被普通窗口覆盖 |
| 被动获知当前前台窗口 | **无受支持 API；KWin 私有路径技术可行** | 无对应 portal；`org_kde_plasma_window_management` 面向 shell 但 KWin **只对 sandboxed 客户端屏蔽**，宿主客户端可绑定并读到 `active` 状态 |
| 把覆盖层上的鼠标/键盘转发到源窗口 | **不可行（在单一捕获会话内）** | 覆盖层是独立 surface，指针事件归它；输入注入需另开 RemoteDesktop / InputCapture 会话并再次授权 |
| 点击穿透（覆盖层不拦截输入） | **可行** | `wl_surface.set_input_region` 设为空（或只保留小按钮矩形） |
| 采集光标 | **可行** | cursor_mode 三值全支持：Hidden(1) / Embedded(2) / Metadata(4)，本机 `AvailableCursorModes=7` |
| 10-bit / HDR 采集 | **不可行** | KWin 6.8 的 screencast 只协商 8-bit 格式（含 NV12），无 colorimetry 参数 |
| HDR 覆盖层呈现 | **不可行（当前）** | Vulkan 无 `wp_color_manager_v1` 对应通道；KWin 会把 swapchain 内容当 SDR |
| Vulkan 直接呈现到覆盖层 | **可行** | `VK_KHR_wayland_surface` 只依赖 `wl_surface`，与 shell role 正交；分数缩放需自行处理 |
| 源窗口身份 / 位置 | **不可行** | 窗口流只给 `source_type`（+ `pipewire-serial`），**没有** size / position / window id |

总体判定：**锁定模型可落地**，但必须接受三条硬约束：**(a) 源窗口对客户端是不透明的**（不能识别、不能定位；`source_type`，无 size/position/window id）；**(b) 覆盖层是只读镜像**（不做输入翻译）；**(c) 无 HDR/10-bit**。

需要特别澄清「能不能」与「该不该」的区别：KWin 6.8 把 `org_kde_plasma_window_management`、`zkde_screencast_unstable_v1`、`org_kde_kwin_fake_input` 等私有 global **只对 sandboxed 客户端屏蔽**，宿主（非 Flatpak）客户端可以绑定。因此技术上存在一条完全绕过 portal 的路径：读窗口列表（含 UUID、`active` 状态）→ 用 UUID 直接向 KWin 请求流。这条路径能解决「窗口身份」「前台跟随」甚至免去授权对话框，但它：(1) 是三份协议共同声明「regular clients must not use」的桌面环境实现细节；(2) 绕过用户同意，等于应用自行承担隐私责任；(3) 与锁定决策（经 portal 选源）冲突。因此报告把它列为**能力事实 + 明确不采用的旁路**，架构仍以 portal 为唯一采集入口。

---

## 2. 本机实测环境（只读验证）

命令与结果（不改配置、不开窗口）：

```
$ pacman -Q kwin xdg-desktop-portal xdg-desktop-portal-kde kpipewire pipewire
kwin 6.8.3-2
xdg-desktop-portal 1.22.1-2.1
xdg-desktop-portal-kde 6.8.3-1.1
kpipewire 6.8.3-1.1
pipewire 1:1.6.11-2

$ qdbus6 org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.DBus.Properties.Get org.freedesktop.portal.ScreenCast version
6
$ ... Get org.freedesktop.portal.ScreenCast AvailableSourceTypes
7            # MONITOR|WINDOW|VIRTUAL
$ ... Get org.freedesktop.portal.ScreenCast AvailableCursorModes
7            # HIDDEN|EMBEDDED|METADATA
$ ... impl portal RemoteDesktop / InputCapture / GlobalShortcuts version
2 / 2 / 2

$ wayland-info | grep -E "zwlr_layer_shell|zkde_screencast|fractional_scale|viewporter|presentation|color_manager|color_representation"
zwlr_layer_shell_v1 v5, zkde_screencast_unstable_v1 v6,
wp_fractional_scale_manager_v1 v1, wp_viewporter v1, wp_presentation v2,
org_kde_plasma_window_management v21, wp_color_manager_v1 v3,
wp_color_representation_manager_v1 v1, org_kde_kwin_fake_input v6

$ kscreen-doctor -o
DP-2: 3840x2160, Geometry 0,0 1920x1080, Scale 2, HDR: enabled, color depth 8..16 bpc

$ qdbus6 org.kde.KWin /KWin supportInformation
Compositing Type: OpenGL ES (Mesa 26.3.1, radeonsi)
```

推论：本机满足 KWin screencast 的 `isSupportedCompositingType()`（仅 OpenGL，见
<https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/plugins/screencast/screencastmanager.cpp>）。
注意 **HDR 已启用**，但采集路径是 8-bit，见 §3.6。

---

## 3. 能力矩阵（含来源）

> 源码引用统一取 Plasma/6.8 分支（与本机 6.8.3 对应），行号为该分支文件内容。

### 3.1 源选择与授权

| 能力 | 结论 | 机制 | 限制 | 来源 |
|---|---|---|---|---|
| 选择单个窗口 | 支持 | `SelectSources(types=2, multiple=false)` → `Start()` 弹出选择对话框 | 每个 session 只能 `SelectSources` 一次、`Start` 一次 | [ScreenCast portal v6 文档](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html) |
| 后端支持窗口源 | 支持 | `AvailableSourceTypes = Monitor\|Window\|Virtual = 7` | —— | 本机 D-Bus 属性 + [screencast.h](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/screencast.h) |
| 选择 UI | KDE 原生对话框（缩略图列表） | `ScreenChooserDialog` + KWayland `PlasmaWindowModel` | 对话框只能看到窗口标题/缩略图；应用无法自定义筛选（例如「排除自己」「只显示游戏」） | [screencast.cpp L343-415](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/screencast.cpp) |
| 授权持久化 | 支持 | `persist_mode=1/2` + `restore_token`（单次使用，每次 `Start` 返回新 token） | token 由前端 permission store 保存；后端只拿到 `restore_data` | [文档 Session persistence](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html) + [screen-cast.c](https://github.com/flatpak/xdg-desktop-portal/blob/main/desktop-portal/screen-cast.c) |
| 恢复时的窗口匹配 | 模糊匹配 | 存 `appId + title`，按 Levenshtein 距离匹配，距离 < 标题长度/2 即接受 | **可能匹配到错误的窗口实例**；标题变化大则回退到对话框 | [screencast.cpp L41-107, L370-395](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/screencast.cpp) |
| 取消 | 支持 | Request 响应码 1（Cancelled）；session 需关闭重建 | 取消后不能复用该 session 重新 Start | ScreenCast 文档（生命周期） |
| 用户侧终止 | 支持 | KDE 后端常驻 SNI「Screen casting」菜单 → End；前端发 `Session::Closed` | 应用必须处理 `Closed` | [screencast.cpp L470-500](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/screencast.cpp) |

### 3.2 采集内容与流格式

| 能力 | 结论 | 机制 | 限制 | 来源 |
|---|---|---|---|---|
| 被遮挡/最小化窗口仍更新 | 支持 | 对窗口 `refOffscreenRendering()`，渲染 `windowItem` 到离屏 framebuffer | 若应用自身停止绘制（最小化暂停），流冻结 | [windowscreencastsource.cpp L52-95, L112-152](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/plugins/screencast/windowscreencastsource.cpp) |
| 跨虚拟桌面 | 支持 | 同上：按窗口对象而非视图采集 | 覆盖层所在桌面与源窗口桌面无关（覆盖层默认在所有桌面） | 同上；[layershellv1window.cpp](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/layershellv1window.cpp) |
| 弹窗/菜单/工具提示 | 一并采集 | transient popup 加入 `m_windows`，取并集包围盒 | **打开菜单会改变流尺寸 → 触发格式重协商**；放大布局需容忍尺寸突变 | windowscreencastsource.cpp L31-50, L196-208 |
| 流尺寸 | 由窗口 frameGeometry × `targetScale` 决定 | `textureSize()`；尺寸变化通过 `pw_stream_update_params` | 客户端必须处理 `SPA_PARAM_Format` 变化 | [screencaststream.cpp L155-235, L690-706](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/plugins/screencast/screencaststream.cpp) |
| 缓冲类型 | dmabuf（DRM modifier 协商）或 MemFd 回退 | 消费者提供 `SPA_FORMAT_VIDEO_modifier` → dmabuf；不提供 → MemFd | 消费者可主动选择 MemFd 规避 GPU 互操作 | 同上 L240-300 |
| 像素格式 | 8-bit RGBA/BGRA 系 + NV12 | `supportedFormats[]` 共 11 项；窗口源固定 `DRM_FORMAT_ARGB8888` | **无 10-bit（XRGB2101010/P010）**，无 colorimetry | 同上 L35-95；windowscreencastsource.cpp `drmFormat()` |
| 部分更新 | 支持 | `SPA_META_VideoDamage`（最多 16 rect）+ `SPA_META_Header`（pts/seq） | 缩放后 damage 需自行映射（分数缩放时非整像素） | screencaststream.cpp L195-220, L729-800 |
| 显式同步（可选） | 支持 | `SPA_META_SyncTimeline` + `planeCount+2` blocks（acquire/release syncobj），仅在生产者 DRM 支持 timeline 时提供；同时提供 implicit-sync 回退参数 | 消费者需主动选择；Vulkan 无法直接消费 DRM syncobj | screencaststream.cpp L169-221, L930-944 |
| 光标 Hidden | 支持 | `m_source->setRenderCursor(false)` | —— | screencaststream.cpp L595-612 |
| 光标 Embedded | 支持 | 把 cursorItem 画进流 | **仅当光标物理位置在窗口内**才包含 | windowscreencastsource.cpp `includesCursor()` |
| 光标 Metadata | 支持 | `SPA_META_Cursor`：id / position / hotspot / RGBA bitmap | 光标不在窗口内时 `id=0`（隐藏）；bitmap 仅在光标图像变化时重发 | screencaststream.cpp L830-885 |
| 会话持久性 | 会话 = PipeWire 流生命周期 | 消费者断流（`PW_STREAM_STATE_UNCONNECTED`）→ KWin `close()` → `closed` 事件 → portal 关会话 | **不能为了重配而断开 pw_stream** | screencaststream.cpp L118-145；screencastmanager.cpp `integrateStreams()` |

### 3.3 覆盖层

| 能力 | 结论 | 机制 | 限制 | 来源 |
|---|---|---|---|---|
| 指定输出 | 支持 | `zwlr_layer_shell_v1.get_layer_surface(surface, wl_output, layer, scope)`；输出对象直接来自 `wl_output` | 输出被禁用/拔出 → KWin 销毁该 layer window | [layershell_v1.cpp L105-140](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/wayland/layershell_v1.cpp) |
| 铺满输出 | 支持 | `anchor = 全四边` + `set_size(0,0)`；`exclusive_zone = -1` → 用完整输出几何（含面板区域） | `exclusive_zone >= 0` 时改用 workArea（避开面板） | [layershellv1integration.cpp L55-135](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/layershellv1integration.cpp) |
| 置顶 | 支持 | layer=`overlay` → `OverlayLayer`，KWin `Layer` 枚举最顶层（高于 `OnScreenDisplayLayer`、`ActiveLayer`） | KWin 锁屏 overlay 也在该层，顺序取决于 stacking | [effect/globals.h `enum Layer`](https://raw.githubusercontent.com/KDE/kwin/master/src/effect/globals.h)；[layershellv1window.cpp `belongsToLayer()`](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/layershellv1window.cpp) |
| 键盘交互 | 可选 | `set_keyboard_interactivity(0/1/2)`；KWin `acceptsFocus()` 直接取该值 | 设为 0 则永不获焦，按键继续送往当前焦点窗口 | layershell_v1.cpp L244-247；layershellv1window.cpp `acceptsFocus()` |
| 输入穿透 | 支持 | `wl_surface.set_input_region(empty)`；也可只保留一个小矩形（如关闭按钮） | 穿透后事件落到**下方任意窗口**，在没有输入翻译的前提下对放大画面无意义 | Wayland 核心协议 `wl_surface.set_input_region` |
| 不可见的客户端装饰/任务栏 | 自动 | KWin 对 layer window `setSkipTaskbar/SkipSwitcher/SkipPager(true)` | 用户无法从任务栏找回覆盖层，需全局快捷键 | layershellv1window.cpp L41-45 |
| xdg_toplevel 全屏 | 支持指定输出 | `set_fullscreen(wl_output)` → `m_fullScreenRequestedOutput` | 非激活时层降级到 `NormalLayer`；被普通窗口覆盖 | [xdgshellwindow.cpp `setFullScreen` / `initialDesktop`](https://raw.githubusercontent.com/KDE/kwin/master/src/xdgshellwindow.cpp)；[window.cpp `belongsToLayer`](https://raw.githubusercontent.com/KDE/kwin/master/src/window.cpp) |
| 退出全屏 | 支持 | 销毁 layer surface / `xdg_toplevel.unset_fullscreen` | —— | 同上 |
| 分数缩放 | 支持 | `wp_fractional_scale_v1` (v1) + `wp_viewporter` | 需要按 `preferred_scale` 出像素并设 viewport destination，否则线性放大模糊 | 本机 `wayland-info`；[fractional-scale 协议](https://wayland.app/protocols/fractional-scale-v1) |
| 多显示器 | 每个输出一个 layer surface | 分别 `get_layer_surface` 到不同 `wl_output` | 单一 surface 不能跨输出 | layershell_v1.cpp |
| 输出识别 | 支持 | `wl_output` v4 的 `name`/`description`；或 `zxdg_output_manager_v1` 逻辑几何 | 逻辑坐标 ≠ 像素坐标（分数缩放） | 本机 wayland-info |

### 3.4 前台窗口检测

| 途径 | 结论 | 说明 | 来源 |
|---|---|---|---|
| portal | **不存在** | 本机 portal 全部接口中没有 ActiveWindow 类接口（Inhibit/Background/ScreenCast/RemoteDesktop/GlobalShortcuts/InputCapture…） | 本机 `Introspect` + [portal 文档索引](https://flatpak.github.io/xdg-desktop-portal/docs/) |
| `org_kde_plasma_window_management` | **受支持性：否；技术可行性：是（宿主客户端）** | KWin 的 `KWinDisplay::allowInterface()` 只在 `client->isSandboxed()` 时屏蔽该 global；宿主客户端绑定后会收到全部窗口（v21 带 UUID）与 `active` 状态位。协议自述面向 shell 且「Only one client can bind this interface at a time」 | [wayland_server.cpp L124-165](https://raw.githubusercontent.com/KDE/kwin/master/src/wayland_server.cpp)；[pwm bind 处理 L220-235](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/wayland/plasmawindowmanagement.cpp)；[plasma-window-management.xml](https://invent.kde.org/libraries/plasma-wayland-protocols/-/blob/master/src/protocols/plasma-window-management.xml) |
| `zkde_screencast_unstable_v1`（按 UUID 直接采集） | **技术可行，明确不采用** | 同一 `allowInterface` 只拦 sandboxed；宿主客户端可用 `stream_window(uuid)` 直接建流，**不经过 portal 同意对话框** | wayland_server.cpp 同上；[screencast_v1.cpp](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/wayland/screencast_v1.cpp) |
| `org.kde.KWin.queryWindowInfo` | 交互式，非被动 | 需要用户点击选择窗口才返回 | [dbusinterface.cpp L157-177](https://raw.githubusercontent.com/KDE/kwin/master/src/dbusinterface.cpp) |
| `org.kde.KWin.getWindowInfo(uuid)` | 需要已有 uuid | 只能用于反查 | 同上 L179-187 |
| KWin script | **可行（KDE 私有路径）** | `workspace.activeWindow` + `windowActivated` 信号；通过 `/Scripting.loadScript` 注入 JS | [KWin scripting API](https://develop.kde.org/docs/plasma/kwin/api/)；[scripting.cpp](https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/scripting/scripting.cpp) |
| `org.kde.KWin.activeOutputName` | 只能给活动输出名 | 不能给窗口 | dbusinterface.cpp L78-81 |

结论：**没有受支持的前台窗口 API**。在 KWin 上实际有两条私有路径：(a) 绑定 `org_kde_plasma_window_management` 读 `active` 状态（宿主客户端可用，协议面向 shell、未文档化给第三方）；(b) 通过 `/Scripting` 注入脚本使用 `workspace.activeWindow` / `windowActivated`。两者都是版本耦合的非稳定契约，其中 (a) 还依赖 KWin 不收紧 `allowInterface`。因此产品上「自动跟随前台窗口」只能作为可选增强，且必须在不可用时优雅降级为「用户在 portal 里显式选窗口」。

### 3.5 输入

| 能力 | 结论 | 机制 | 限制 | 来源 |
|---|---|---|---|---|
| 覆盖层接收指针 | 由 input region 决定 | surface 局部坐标 | 覆盖后源窗口收不到 | Wayland 核心 |
| 覆盖层接收键盘 | `keyboard_interactivity` | none/on_demand/exclusive | 与 input region 独立 | layershell_v1.cpp L244 |
| 输入注入 | 需另开会话 | `RemoteDesktop`（KDE 实现走 `org_kde_kwin_fake_input`）或 `InputCapture`（KWin EIS，`connectToEIS`） | 再次弹授权；依赖 KDE 私有协议；RemoteDesktop 会话禁止持久化 | [waylandintegration.cpp L275-320](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/waylandintegration.cpp)；[inputcapture.cpp L420-450, L600-615](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/inputcapture.cpp) |
| `org_kde_kwin_fake_input` 直用 | **不应使用** | 协议明文 Warning：「Regular clients must not use this protocol」 | 无用户可见授权语义，随时破坏兼容 | [fake-input.xml](https://invent.kde.org/libraries/plasma-wayland-protocols/-/blob/master/src/protocols/fake-input.xml) |
| 全局快捷键 | 支持 | `org.freedesktop.portal.GlobalShortcuts` v2 → KDE 实现基于 KGlobalAccel（System Settings → Shortcuts 可改） | 首次需 `BindShortcuts` 对话框；组件名取自 appId | [GlobalShortcuts 文档](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html)；[globalshortcuts.cpp](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/globalshortcuts.cpp) |

### 3.6 色彩 / HDR / 呈现后端

| 能力 | 结论 | 说明 | 来源 |
|---|---|---|---|
| 10-bit 采集 | 不支持 | 格式表无 10-bit；窗口源硬编码 ARGB8888 | screencaststream.cpp L35-95；windowscreencastsource.cpp |
| HDR 采集 | 不支持 | 流参数无 colorimetry/transfer function；渲染目标 sRGB 8-bit | 同上 |
| HDR 覆盖层 | 不支持 | Vulkan 无 `wp_color_manager_v1` 桥接；KWin 将 swapchain 视作 SDR | 本机 `wp_color_manager_v1` v3 存在；Vulkan 侧无对应扩展 |
| Vulkan 呈现 | 支持 | `VK_KHR_wayland_surface` 由 `wl_surface` 创建 `VkSurfaceKHR`；shell role 与 WSI 正交 | [VK_KHR_wayland_surface](https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/main/appendices/VK_KHR_wayland_surface.adoc) |
| 导入 dmabuf | 支持但需自建管线 | `VK_EXT_external_memory_dma_buf` + `VK_EXT_image_drm_format_modifier`；kpipewire 自身走 EGL/GBM 导入，可作参照 | [VK_EXT_external_memory_dma_buf](https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/main/appendices/VK_EXT_external_memory_dma_buf.adoc)；[VK_EXT_image_drm_format_modifier](https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/main/appendices/VK_EXT_image_drm_format_modifier.adoc)；[dmabufhandler.cpp](https://invent.kde.org/plasma/kpipewire/-/blob/Plasma/6.8/src/dmabufhandler.cpp) |
| 帧率/呈现时序 | 可优化 | `wp_presentation` v2；`wp_fifo_manager_v1`（KWin 支持 commit timing） | 本机 wayland-info |

---

## 4. 硬约束与失败模式

### 4.1 会话与流的硬约束

1. **一次性语义**：`SelectSources` 每 session 一次，`Start` 一次；取消或失败必须重建 session。这决定了应用内部要有「会话状态机」，不能把 session 当长连接随意重配。
   —— [ScreenCast 文档](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html)
2. **restore token 单次使用**：每次 `Start` 返回新 token，旧的立即失效；必须原子地持久化新 token，否则下次要重新弹窗。
3. **断流即毁会话**：KWin 在 `PW_STREAM_STATE_UNCONNECTED` 时 `close()` 流并通知 portal；portal 流空即关 session。因此暂停/重建 PipeWire 连接会导致授权作废（要重新走 token/对话框）。
   —— screencaststream.cpp L118-145；screencast.cpp `streamClosed()`
4. **窗口关闭 = 会话结束**：`WindowScreenCastSource` 在窗口 closed 后发 `closed`，链路 KWin → portal → 应用 `Session::Closed`。应用必须重新选源，不能期望「同一 session 换源」。

### 4.2 语义硬约束

5. **源身份不可知**：窗口流 metaData 只有 `source_type=Window`（KDE 后端未设置 `id`/`size`/`position`）。判断「用户在放大哪个窗口」只能靠用户自己说，或者用 KWin 私有途径。
   —— [screencasting.cpp L150-205](https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/Plasma/6.8/src/screencasting.cpp)
6. **流尺寸会突变**：弹窗、最大化、改变窗口大小都会改变捕获包围盒 → 重新协商格式。覆盖层的缩放滤镜必须接受运行时尺寸变化（含短暂 0 尺寸/格式切换）。
7. **8-bit 上限**：HDR/宽色域内容会被合成器压到 SDR 8-bit 再进流；这决定了「放大后观感」不会优于 SDR。
8. **layer-shell 是「桌面组件」协议**：协议本身声明只面向桌面环境组件，KWin 目前不校验，但这意味着它不是稳定第三方 API；KWin 未来可收紧（例如要求特定 scope 或客户端身份）。
9. **portal 是同意层，不是技术门**：KWin 的 `allowInterface()` 只对 `isSandboxed()` 的客户端屏蔽 `org_kde_plasma_window_management` / `zkde_screencast_unstable_v1` / `org_kde_kwin_fake_input`。宿主进程既能列窗口也能直接建流，意味着任何「安全上依赖 portal 弹窗」的设计假设在非 Flatpak 发行形态下不成立。若产品要承诺「不偷看」，必须由应用自身保证只走 portal。
   —— [wayland_server.cpp L124-165](https://raw.githubusercontent.com/KDE/kwin/master/src/wayland_server.cpp)
10. **私有协议无稳定性承诺**：三份协议均写明是桌面环境实现细节、regular clients 不得使用、可不升版本号做不兼容变更。

### 4.3 失败模式清单

| 场景 | 实际发生 | 应用应做 |
|---|---|---|
| 源窗口被遮挡 | 无影响（离屏渲染） | 无需处理 |
| 源窗口最小化 | 无影响；但若应用停止绘制则画面冻结 | UI 提示「源应用已暂停绘制」可选 |
| 切换虚拟桌面 | 无影响；覆盖层默认在所有桌面 | 可选：跟随桌面自动隐藏覆盖层（需 KWin script 或 logind 无关信号） |
| 源窗口关闭 | 流 closed → session 关闭 | 捕获 `Session::Closed`，回到选源状态，提示用户 |
| 输出被禁用/拔出（覆盖层所在） | layer window 被销毁（`handleOutputRemoved` → `closed`） | 监听 `wl_output` 移除，重建到新输出或退出 |
| 合成器重启（KWin 崩溃/重登） | Wayland 连接断 → 流 closed → 会话失效；旧 token 已用掉 | 全量重建 session（用最近保存的 token；若 token 已被消费则重新弹窗） |
| 用户从 SNI 结束共享 | `Session::Closed` | 同上 |
| 权限被撤销（permission store 清空） | 已运行的流**不会**被立即切断（代码中无 revoke→close 路径）；影响下一次 restore | 不能把「撤销」当作即时安全手段；应提供自己的停止开关 [推断] |
| 锁屏 | 采集路径无锁屏检查，离屏渲染继续进行 → 流可能继续输出内容；覆盖层是否盖住锁屏取决于 stacking | 必须监听 `org.freedesktop.login1.Session.LockedHint`，锁屏时隐藏/销毁覆盖层 [推断，需实测] |
| 消费者崩溃 | pw_stream 断开 → KWin 关流 → 会话关闭 | 崩溃恢复后重新授权 |
| 合成器切到 Vulkan 后端 | `isSupportedCompositingType()` 只接受 OpenGL → `sendFailed("Unsupported compositing type")` | 启动时探测能力，给出明确错误 |
| 覆盖层被第三方录制 | layer-shell window 默认可被 monitor 采集捕获 | 记录在用户文档（放大画面会被录进屏幕录像） |

---

## 5. 对交互契约与架构的影响

### 5.1 契约必须写死的条目

1. **源选择只经 portal**。受支持的窗口枚举/前台窗口 API 不存在；KWin 私有协议虽然可用，但按锁定决策不作为采集入口（理由见 §1 与 §4.2-9/10）。因此内部实现也应禁止走 `plasma_window_management` + `zkde_screencast` 旁路，避免把非稳定、绕过同意的东西写进主路径。
2. **捕获对象不透明**：UI 里只能显示「已共享的窗口（用户选择）」，不能显示窗口标题/图标/尺寸；需要标题就让用户自己填备注。
3. **覆盖层只读**：不做输入转发；键鼠操作留在源窗口所在输出。覆盖层仅在角落保留一个极小的 input region 用于「停止/设置」按钮，其余区域 `input_region` 为空实现穿透。
4. **显示控制走全局快捷键**：显示/隐藏覆盖层、切换缩放模式、退出，全部通过 `GlobalShortcuts`（首次绑定弹窗，之后可在系统设置改键）。
5. **会话是稀缺资源**：单例、长活；任何「重新选源」都走显式用户操作 + token 流程；出错时降级为「覆盖层隐藏 + 提示」而不是静默重连。

### 5.2 架构落点

- **捕获层**：`pw_stream` + `PW_KEY_TARGET_OBJECT = pipewire-serial`（v6 语义，避免 node id 复用）。优先请求 dmabuf + modifier；失败回退 MemFd（KWin 支持，见 `newStreamParams` 的 `buffertypes`）。
- **呈现层**：`wl_surface` → `zwlr_layer_shell_v1.get_layer_surface(output, overlay, scope="magpie-overlay")` → `VkSurfaceKHR`（`VK_KHR_wayland_surface`）。`anchor` 全边、`size 0,0`、`exclusive_zone -1`。
- **缩放策略**：以输出像素尺寸渲染；分数缩放用 `wp_fractional_scale_v1` 的 `preferred_scale` 决定 buffer 分辨率 + `wp_viewport_set_destination`（**注意**：该 viewport 要设在传给 WSI 的同一个 `wl_surface` 上，需原型验证，见 §6）。
- **零拷贝路径**：dmabuf → `VK_EXT_image_drm_format_modifier`（`VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT`）+ `VK_EXT_external_memory_dma_buf`；要求 Vulkan 设备与 KWin 渲染设备同 GPU（`VK_KHR_external_memory_capabilities` 的 device UUID/LUID 校验），多 GPU 机器要有回退。
- **同步**：优先使用 KWin 的 implicit-sync 回退参数（不声明 `SPA_META_SyncTimeline`）；如需显式同步，需自行处理 syncobj（Vulkan 只能吃 sync_file，需 `DRM_IOCTL_SYNCOBJ_HANDLE_TO_FD` 转换）——列为原型项。
- **配置 UI**：Flutter 只做配置窗口（独立 `xdg_toplevel`），不做覆盖层；`parent_window` 可不传（对话框可能不置顶，可接受）。若必须传，需要 xdg-foreign export handle，Flutter GTK embedder 未暴露该 API [推断]。
- **生命周期**：`Session::Closed`、`pw_stream` 状态、`wl_output` 移除、logind `LockedHint` 四个信号源统一进状态机。

### 5.3 对「效果」的影响

- MagpieFX/HLSL → SPIR-V（DXC）路径与采集格式无关，但**所有效果只能在 8-bit SDR 上工作**；HDR 相关 effect 参数在 Linux 上没有意义。
- damage 区域驱动的局部重绘在放大链路上价值有限（缩放后几乎全屏失效），可按「有 damage 即整帧重绘」起步，后续再优化。

---

## 6. 待原型验证（按风险排序）

1. **Vulkan dmabuf 导入 + 同步**：KWin 的 ARGB8888 + 厂商 modifier 能否被目标 GPU 的 Vulkan 直接导入；implicit-sync 下是否需要 CPU/GPU fence 兜底；多 GPU（iGPU + dGPU）行为。
2. **layer-shell + Vulkan WSI + 分数缩放**：在 `wl_surface` 上先设 shell role 再建 `VkSurfaceKHR` 是否被 Mesa WSI 接受；`wp_viewport_set_destination` 与 WSI 的 commit 是否冲突；`preferred_scale` 变化时的重建流程。
3. **锁屏行为**：锁屏时覆盖层是否仍可见、流是否继续；`LockedHint` 驱动的隐藏是否足够。属于安全相关，必须实测。
4. **恢复匹配可靠性**：同一 appId 多实例、标题变化、窗口重建后的 `tryMatchWindows` 结果；失配时是否总回退到对话框。
5. **覆盖层「按钮 + 穿透」混合**：小 input region 是否稳定命中；点击按钮时是否会把焦点从源窗口抢走（`keyboard_interactivity=0` 下应不抢）。
6. **光标 meta 呈现**：缩放后光标坐标/热区映射；`id=0` 时隐藏；光标 bitmap 重发的时机。
7. **HDR 输出观感**：HDR 显示器上 8-bit SDR 覆盖层的亮度/色域表现，是否需要 KWin 侧 `wp_color_manager` 支持才可接受。
8. **性能**：4K60 窗口捕获 + Vulkan 放大 + layer-shell 呈现的端到端延迟与掉帧；`wp_presentation` 反馈能否用于自校准。
9. **KWin 私有能力回归**：`/Scripting`、`plasma_window_management`、`zkde_screencast` 直连、layer-shell scope 限制，在各 Plasma 小版本上的稳定性；尤其确认 `allowInterface` 仍只对 sandboxed 客户端收紧（这是「前台跟随」增强能否存活的前提）。
10. **portal 流与私有窗口列表的关联**：确认是否存在任何字段能把 ScreenCast 流映射回窗口 UUID。若无（当前看是无），则「显示源窗口标题/缩略图」只能靠用户输入或私有采集旁路。
11. **覆盖层与锁屏/OSD 的层内顺序**：OverlayLayer 内的 stacking 规则（锁屏 overlay、我方 overlay、KWin OSD）在真实交互下的可见性。

---

## 附：与锁定决策的对照

- 「Flutter 只做配置 UI；原生 C++/Vulkan 做捕获/缩放/呈现」——与上述结论一致：覆盖层必须是 Wayland 原生 surface，Flutter 无法承担 layer-shell + Vulkan WSI。
- 「Wayland first; KDE Plasma/KWin only」——可行，但必须接受对 KWin 专有语义的依赖（layer-shell 的 overlay 层、顶点级别无 HDR、无受支持的前台窗口 API）。KWin 私有协议（窗口列表、按 UUID 采集、fake input）技术上可绕过 portal，但明确不进入主路径。
- 「保持 MagpieFX/HLSL 源，DXC 编译 SPIR-V」——可行，但效果运行在 8-bit SDR 管线。
- 「全配置 UI 对齐，排除 Windows-only」——HDR/10-bit、自建窗口选择器、前台窗口自动跟随应标记为 Linux 不可移植项；「选择窗口」这一动作本身由 portal 对话框提供，只是应用无法定制也无法得知结果。
