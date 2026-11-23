# Linux 打包、沙箱与分发约束

Ticket: Qxy0happy/Magpie#6 · 调查日期 2026-11-23 · 目标平台：KDE Plasma / KWin / Wayland，Vulkan + xdg-desktop-portal 应用

---

## 0. 结论（先给决策）

**主分发：Flatpak（首发自托管签名仓库，稳定后再申请 Flathub）；次分发：AppImage（无沙箱参考构建，覆盖非 Flatpak 用户）；附加：Arch AUR PKGBUILD（成本最低的原生包）。Debian/Fedora 官方仓库在首版不作为目标。**

理由摘要：

1. 交互设计本身已经建立在 portal 之上（ScreenCast 选窗口、GlobalShortcuts 注册热键），Flatpak 的 D-Bus 默认策略恰好允许 `org.freedesktop.portal.*`，不需要额外 talk-name；捕获流通过 portal 返回的 PipeWire fd 进入沙箱，不需要 `--filesystem=xdg-run/pipewire-0`。
2. Flatpak 的 Vulkan 驱动由 runtime 的 GL extension 提供（与宿主 Mesa/NVIDIA 解耦），比 AppImage 依赖宿主 ICD 更可预测；代价是无法使用第三方/私有 ICD。
3. AppImage 在"更新 + 签名 + app id"三点上结构性弱于 Flatpak，但它是唯一不需要任何基础设施、可在任意发行版上验证的无沙箱形态，适合作为降级通道。
4. Debian 与 Fedora 都没有 DXC（DirectXShaderCompiler）打包，而本项目运行时需要 `libdxcompiler.so`；Debian Policy 4.13 禁止 convenience copy，Fedora 允许但需 `Provides: bundled(...)`。因此这两个发行版的原生包成本显著高于 Arch（Arch `extra` 已有 `directx-shader-compiler`）。

**必须提前接受的降级**（详见 §9）：Flatpak 下无私有 Vulkan ICD、无宿主 Vulkan layer、效果文件只能放 app data 目录、全局热键只能走 portal、自启只能走 Background portal；AppImage 下热键依赖已安装的 `.desktop` + `Registry.Register`，否则退化为 KGlobalAccel 直连（仅 KDE 可用）。

---

## 1. 方法与本机基线（2026-11-23 实测，只读）

命令与结果（同一台 CachyOS/Plasma 6.8.3 机器）：

| 组件 | 版本 | 来源 |
|---|---|---|
| flatpak | 1.18.4 | `flatpak --version` |
| flatpak-builder | 1.4.12 | `flatpak-builder --version` |
| xdg-desktop-portal | 1.22.1 | `pacman -Q` |
| xdg-desktop-portal-kde | 6.8.3 | `pacman -Q` |
| plasma-workspace / kwin | 6.8.3 | `pacman -Q` |
| pipewire | 1.6.11 | `pacman -Q` |
| vulkan-icd-loader | 1.4.363 | `pacman -Q` |
| appimagetool | continuous build 370 (2026-11-06) | `appimagetool --version` |
| dxc | 未安装（Arch `extra/directx-shader-compiler 1.10.2605.37-1` 可装） | `command -v dxc`、archlinux.org API |

运行时实测（`busctl --user get-property`）：

| 属性 | 值 | 含义 |
|---|---|---|
| `org.freedesktop.portal.ScreenCast.version` | **6** | 支持 `pipewire-serial` |
| `ScreenCast.AvailableSourceTypes` | **7** | MONITOR(1) \| WINDOW(2) \| VIRTUAL(4) 全支持 |
| `ScreenCast.AvailableCursorModes` | **7** | Hidden \| Embedded \| Metadata |
| `org.freedesktop.portal.GlobalShortcuts.version` | **2** | 有 `ConfigureShortcuts` |
| `org.freedesktop.impl.portal.ScreenCast.version`（KDE 后端） | **6** | KDE 侧实现版本 |
| `org.freedesktop.impl.portal.GlobalShortcuts.version` | **2** | KDE 侧实现版本 |
| `org.freedesktop.host.portal.Registry.version`（在 `/org/freedesktop/portal/desktop`） | **1** | host app 可注册 app id |

`org.freedesktop.Platform//25.08` 与 `//26.08` 内实测存在：`libgtk-3.so.0`、`libvulkan.so.1`、`libpipewire-0.3.so.0`、`libEGL.so.1`、`libwayland-client.so.0`、`libshaderc`、`libSPIRV`；**不存在** `libdxcompiler.so` / `dxc`。

runtime metadata（`flatpak info --show-metadata org.freedesktop.Platform//25.08`）关键片段：

```
[Extension org.freedesktop.Platform.GL]
directory = lib/x86_64-linux-gnu/GL
subdirectories = true
merge-dirs = vulkan/icd.d;glvnd/egl_vendor.d;...;vulkan/explicit_layer.d
download-if = active-gl-driver
enable-if = active-gl-driver
autoprune-unless = active-gl-driver
```

沙箱内实际挂载：`/usr/lib/x86_64-linux-gnu/GL/{default,nvidia-620-73-04}`，且 ICD json 直接指向 `GL/default/lib/libvulkan_radeon.so`。这证明 **Vulkan 驱动来自 GL extension，而不是宿主 `/usr`**。

---

## 2. 需求 → 平台能力映射

| 引擎需求 | Flatpak 下的路径 | 是否需静态权限 |
|---|---|---|
| 选一个源窗口捕获 | ScreenCast portal（`types=WINDOW`）+ PipeWire fd | 否（portal 默认可用） |
| 接收 1920×1080 以上 dmabuf | `OpenPipeWireRemote()` 返回的 fd + `pw_context_connect_fd` | 否 |
| Vulkan 渲染 / 全屏 overlay | `--socket=wayland` + `--device=dri` | 是（两项） |
| 把 HLSL 编译为 SPIR-V | 内置 `libdxcompiler.so`，运行时编译并缓存 | 否（bundle） |
| 读取用户效果文件 | `$XDG_DATA_HOME/magpie/effects` | 否（app 自有目录） |
| 全局热键 | GlobalShortcuts portal（需有效 app id） | 否 |
| 托盘 | StatusNotifierItem | 是（`--talk-name=org.kde.StatusNotifierWatcher`） |
| 开机自启 | Background portal `RequestBackground(autostart=true)` | 否（需有效 app id） |
| 配置 UI ↔ 引擎 IPC | `$XDG_RUNTIME_DIR/app/$FLATPAK_ID/magpie.sock` | 否 |
| 保存截图（未来功能） | FileChooser SaveFile portal，或 `xdg-pictures` | 前者不需要，后者需要 |
| 网络 | 不需要 | 不声明 |

---

## 3. Flatpak 沙箱逐项约束

### 3.1 ScreenCast：能力最强、约束最少的一环

- 会话生命周期：`CreateSession` → `SelectSources`（每会话仅一次）→ `Start`（弹 KDE 选择器）→ `OpenPipeWireRemote`。[S5]
- `Start` 返回的 `streams` 中，v6 起推荐用 `pipewire-serial` + `PW_KEY_TARGET_OBJECT` 定位节点；node id 在 hotplug/分辨率/刷新率变化后可能被复用。[S5]
- **不需要** `--filesystem=xdg-run/pipewire-0`：portal 直接把 PipeWire remote 的 fd 通过 D-Bus 传给沙箱内进程，`OpenPipeWireRemote` 文档明确说该 fd 用于 `pw_context_connect_fd`，且该 remote 只暴露 screencast 节点。[S5]
  - OBS 的 Flatpak 声明了 `--filesystem=xdg-run/pipewire-0`，那是因为它自己还要做摄像头/音频采集；本项目只需要 screencast 流，不需要该权限。[S3]
- KWin 侧：`screencaststream.cpp` 在有 dmabuf 能力时提供 `SPA_DATA_DmaBuf`（含 syncobj 支持），否则回退 `SPA_DATA_MemFd`。[S12] 因此 Flatpak 沙箱不改变零拷贝路径。
- 持久化：`persist_mode` 0/1/2 与 `restore_token`（v4 起；xdg-desktop-portal 1.12.0 引入，Plasma 5.27 的 KDE 后端已实现）。[S5][S9][S10]
- **KDE 的窗口恢复是启发式**：保存 `{appId, title}`，恢复时按 appId 精确匹配、title 用 Levenshtein 距离取最相近且距离 < title 长度/2 的窗口。[S10] 结论：窗口流恢复可能选错窗口或恢复失败，产品上必须把"重新选择源窗口"当作一等流程，不能假设 token 必然成功。
- 捕获窗口时，KWin 提供的是该窗口内容，不会把 overlay 自身叠加进去（overlay 属于另一个 surface）。[推断，来自 KWin 窗口流按 surface 捕获的实现方式]

### 3.2 GlobalShortcuts：可用，但 app id 是硬门槛

- portal 自 xdg-desktop-portal **1.16.0** 引入；`ConfigureShortcuts`（接口 v2）在 **1.21.0** 引入；KDE 后端 v2 自 **Plasma 6.5** 起（v6.4 及更早为 v1）。[S6][S9][S11]
- **1.21.0 起 CreateSession 要求非空 app id**，否则同步返回 `NotAllowed "An app id is required"`（源码 `global-shortcuts.c`）。[S9][S22]
- Flatpak 内 app id = `FLATPAK_ID`，`.desktop` 由 app 自带，天然满足。
- **非沙箱形态（AppImage / 发行版包）不天然满足**：host app 的 app id 由 systemd unit 名 `app-<escaped-id>.scope` 推导，且必须能打开 `<id>.desktop`；从终端直接启动常常得到空 id。[S23]
  - 显式解决方式：在**任何其他 portal 调用之前**，用同一条 D-Bus 连接调用 `org.freedesktop.host.portal.Registry.Register(app_id, {})`（接口 v1，位于 `/org/freedesktop/portal/desktop`，自 portal 1.19.4 引入）；`app_id` 必须与某个已安装 `.desktop` 的 basename 一致，且同一连接只能注册一次，portal 重启需监听 `NameOwnerChanged` 重新注册。[S7][S9]
  - 实测：`Register("io.github.test.Magpie")` → `Could not register app ID: App info not found`；换成已安装的 `org.kde.konsole` 成功。[S25]
- KDE 侧实现细节：`GlobalShortcutsPortal::version() == 2`；`BindShortcuts` 会弹 KDE 配置对话框，返回结果可能是请求集合的子集。[S6][S11]
- 已知缺陷：KDE bug 492992「后续启动不复用已创建的快捷键」，2025-01-11 标记 RESOLVED FIXED（针对 6.1.4 报告）。[S24] 首发应要求 Plasma ≥ 6.3，或在 6.5+ 使用 `ConfigureShortcuts` 让用户在系统设置里管理。
- 交互约束：`Activated` 携带 `activation_token`，用于在热键触发时合法地激活窗口（Wayland 焦点模型）。[S6]

### 3.3 Vulkan：可用，但驱动集合被 runtime 固定

- `--device=dri` 是 Flatpak 的"标准权限"（文档写作 "OpenGL rendering"），Vulkan 设备访问同样依赖它。[S1] 没有它，沙箱内只能落回 `lvp`（lavapipe 软件光栅）。[S25]
- ICD 由 `org.freedesktop.Platform.GL.*` extension 提供，且通过 `download-if/enable-if = active-gl-driver` 按宿主当前 GL 驱动自动选择；NVIDIA 走 `org.freedesktop.Platform.GL.nvidia-<driver>`。[S25]
- 结构后果（**推断**，由挂载布局可推）：宿主的 `/usr/share/vulkan/icd.d` 不可见，`VK_ICD_FILENAMES` 之类的宿主环境不会生效；AMDVLK、amdgpu-pro、Intel 私有驱动、自编译 Mesa 均不可用。可用的只有 Flathub GL extension 里的 Mesa（radeon/intel/nouveau/lvp/virtio）与 NVIDIA 扩展。
- 版本策略：runtime 自带 loader（25.08: 1.4.321；26.08: 1.4.357），Mesa 由 extension 独立升级，通常比宿主新；但新 GPU 上市初期宿主内核 + 旧 extension 可能不匹配，需要提示用户 `flatpak update`。

### 3.4 DXC / SPIR-V：必须自带，且 Flathub 要求从源码构建

- fdo runtime 无 `libdxcompiler.so`；沙箱内也无法访问宿主 `/usr/lib` 的 DXC。[S25]
- Flathub 要求"完全从源码构建、构建期无网络"。[S13] DXC 官方 Linux 构建流程：CMake ≥ 3.17.2、Python 3、C++14 编译器（GCC/Clang 均可），Ninja 推荐。[S21]
- 代价：DXC 会引入一份 LLVM，构建时间与产物体积都显著（数量级：数十分钟构建、数十 MB 产物）。建议作为独立 module 并固定 tag/commit；`libdxcompiler.so` 安装到 `/app/lib`。
- 运行时编译的缓存写在 `$XDG_CACHE_HOME/magpie/shaders`（Flatpak：`~/.var/app/<id>/cache/magpie/shaders`），沙箱可写，无需权限。
- DXC 的 SPIR-V 后端是"HLSL → Vulkan SPIR-V"的参考实现，但存在语义映射缺口（文档 `SPIR-V.rst` 明确列出 DirectX 与 Vulkan 的语义鸿沟）。[S21] 现有 MagpieFX 效果集需要逐条跑兼容性矩阵，这是效果迁移票的输入。

### 3.5 效果文件：只读 `/app` + 用户目录

- Windows 版从 exe 同级 `effects\` 加载（`EffectCompiler.cpp` 中 `L"effects\\"` 相对路径）。[S25]
- Flatpak 中 `/app` 只读。必须实现两级搜索：
  1. `/app/share/magpie/effects`（随包、只读）
  2. `$XDG_DATA_HOME/magpie/effects`（Flatpak 中即 `~/.var/app/io.github.qxy0happy.Magpie/data/magpie/effects`）
- 不要申请 `--filesystem=xdg-data/magpie`：Flathub linter 对 `xdg-data`/`xdg-config`/`xdg-cache` 的宽泛访问直接报 error（`finish-args-arbitrary-xdg-data-*`）。[S14]
- 与非 Flatpak 安装共享效果目录被 Flatpak 文档明确劝阻（"Retaining and sharing configuration with non-Flatpak installations is to be avoided"）。[S1]

### 3.6 截图目录

现状：Windows 版仓库中没有截图功能（`rg -i screenshot src` 仅命中 overlay/效果渲染代码）。[S25] 因此这是为未来功能预留的约束：

- 首选：`org.freedesktop.portal.FileChooser` 的 SaveFile，用户选路径，经 document portal 获得可写 fd；不产生任何静态权限。[S1][S5]
- 备选：`--filesystem=xdg-pictures/Magpie:create`。`xdg-pictures` 本身不在 linter 的 error 列表里，但 Flathub 要求"有 portal 就用 portal"，评审可能要求解释。[S13][S14]
- 若要"自动保存到 ~/Pictures/Screenshots"，只能走备选权限；建议首版用 SaveFile，避免为未实现功能先申请权限。

### 3.7 托盘、自启、单实例、通知

- **托盘**：Flatpak 文档明确 StatusNotifier 需要 `--talk-name=org.kde.StatusNotifierWatcher`（多数实现不再需要 `--own-name`；Electron < 23.3 等老实现才需要）。[S23] linter 对通配 `org.kde.*` talk-name 报 error，具体名可以。[S14]
- **自启**：走 `org.freedesktop.portal.Background` 的 `RequestBackground(autostart=true)`；portal 1.21.0 起同样要求有效 app id。[S9] KDE 后端已实现 `Background`（本机 `kde.portal` 列出）。[S25]
- **单实例 / 配置 UI ↔ 引擎**：Flatpak 默认允许应用 own 自己的 app id 命名空间，`--own-name` 无需声明；linter 对 `--own-name=<自己的 id>` 反而报"unnecessary"。[S14] 用 `$XDG_RUNTIME_DIR/app/$FLATPAK_ID/` 下的 Unix socket 更简单，该目录默认可写。[S1]
- **通知**：允许通过 portal 使用，无需权限（`org.freedesktop.portal.*` 默认可达）。[S1]

### 3.8 建议的 finish-args（最小集）

```yaml
finish-args:
  - --socket=wayland                      # 仅 Wayland；不声明 x11/fallback-x11
  - --device=dri                          # Vulkan/GL 设备
  - --talk-name=org.kde.StatusNotifierWatcher   # 仅在提供托盘时
  # 可选，仅在不用 FileChooser portal 时：
  # - --filesystem=xdg-pictures/Magpie:create
```

不声明：`--share=network`、`--socket=pulseaudio`、`--share=ipc`（仅 X11 需要）、`--filesystem=host/home`、`--device=all`。

linter 预期结果：`finish-args-only-wayland` 是 **warning**（不是 error）；无 xdg-data/config/cache 宽泛访问；无 wildcard talk-name。[S14]

### 3.9 Entitlements（新机制，默认不影响我们）

- 沙箱 runtime 在 metadata 的 `[Policy entitlement]` 段声明 `version` 与 `grant`。**entitlement version 0（或未声明）时所有 entitlement 隐式授予**；一旦声明 version 1，就必须显式列出 `org.freedesktop.portal.ScreenCast`、`org.freedesktop.portal.GlobalShortcuts` 等。[S8]
- 本机 Flatpak 1.18.4 支持 `flatpak build-finish --add-policy=...`。[S25]
- 决策：首版不声明 entitlement version（保持 0），避免把自己锁进一个还在演进的机制；在清单里注释说明，等 Flatpak 默认值变化时再评估。

---

## 4. AppImage 约束

### 4.1 运行与依赖

- 需要 FUSE 2.x 才能挂载；Arch 有 `extra/fuse2`（本机已装 2.9.9-6），Ubuntu 24.04 需 `libfuse2t64`；无法装 FUSE 时用 `--appimage-extract-and-run` 或 `APPIMAGE_EXTRACT_AND_RUN=1`。[S16]
- 依赖宿主：glibc（向前兼容受限）、GTK3（Flutter Linux embedder 需要 [S26]）、Vulkan loader/ICD、libpipewire、Wayland。
- 建议：用 linuxdeploy 的 GTK 插件把 GTK3 及其模块打进 AppDir（体积 +10~20 MB，避免宿主 GTK 版本/主题漂移）；**不要**打包 Mesa/ICD——会与宿主内核、DRM 版本冲突。[推断，通用 AppImage 实践]

### 4.2 portal 与 app id（最容易踩的坑）

- 无沙箱不影响 portal 可用性：任何进程都能调用 `org.freedesktop.portal.Desktop`。
- 但 portal 1.21.0 起，GlobalShortcuts 与 Background 的 autostart 都要求有效 app id；host app 的 app id 来自 systemd scope + `.desktop`，手动运行 AppImage 通常为空。[S9][S23]
- 因此 AppImage **必须**：随包提供 `io.github.qxy0happy.Magpie.desktop`；首次运行时安装到 `~/.local/share/applications/`（或由 AppImageLauncher 完成）；进程启动后、任何 portal 调用之前，在专用 D-Bus 连接上调用 `Registry.Register("io.github.qxy0happy.Magpie", {})`；监听 portal 的 `NameOwnerChanged` 以便重启后重注册。[S7]
- 若不做上述工作，可接受的降级是：热键改走 KGlobalAccel（KDE 专属，正好符合本项目"KDE only"的定位），但会与 portal 路径形成两套代码，且破坏"沙箱内外一致"的目标。

### 4.3 更新与签名

- 更新信息由 `appimagetool -u "zsync|<url>.zsync"` 嵌入；有 `zsyncmake` 时会生成 `.zsync`。[S16]
- 签名：`appimagetool --sign`（GPG，可 `--sign-key`），签名嵌入文件；**验证**需要外部工具（AppImageUpdate 的 `validate`），AppImage 自身不会验证。[S16]
- AppImageUpdate：最新发布仍是 `2.0.0-alpha-1-20251018`（2025-10-18），仓库 2026-10-30 仍有提交，87 个 open issues。[S17] 结论：可以作为"检查更新 + 增量下载"的实现，但不能假设它有发行版级成熟度；必须自建发布 manifest 与回滚路径。

---

## 5. 发行版包

### 5.1 Arch / AUR

- 依赖清单（原生构建）：`vulkan-icd-loader`、`vulkan-driver`（宿主自选）、`pipewire`、`wayland`、`libxkbcommon`、`gtk3`（Flutter UI）、`directx-shader-compiler`（DXC，`extra` 已有 1.10.2605.37-1）。
- DXC 直接依赖系统包即可，无需 vendoring——这是 Arch 相对 Debian/Fedora 的最大优势。
- AUR PKGBUILD 只做构建，不做签名；用户自行 `makepkg`，校验靠 `sha256sums`/`b2sums` 与上游 tag。[S20]
- 成本：一个 PKGBUILD + 一次性验证；无更新基础设施（用户 `paru -Syu` 重建 VCS 包或等 stable 版本 bump）。

### 5.2 Debian / Ubuntu

- **DXC 不存在**：`sources.debian.org` 精确查询为空，ftp-master madison 无输出。[S25]
- Debian Policy 4.13 原文："Debian packages should not make use of these convenience copies unless the included package is explicitly intended to be used in this way… If the included code is not already in Debian, it should be packaged separately as a prerequisite if possible."[S18]
- 结论：要进 Debian 主档案，必须先有人把 DXC 打成独立源码包（LLVM 子模块、构建时间长），再让 Magpie 依赖它。首版不现实；可行路径是 PPA/第三方仓库，但那就退化成"自建 apt 仓库"，与 Flatpak 自托管仓库的维护成本相当而覆盖面更小。
- 另外：Debian 的 `xdg-desktop-portal` 版本可能低于 1.21，GlobalShortcuts 的 app-id 行为与 `ConfigureShortcuts` 不可用，需要运行时探测接口版本。[S9]

### 5.3 Fedora

- DXC 同样没有 dist-git 包（`src.fedoraproject.org/rpms/directx-shader-compiler` 404）。[S25]
- Fedora 允许 vendoring，但必须声明："All packages whose upstreams have no mechanism to build against system libraries MAY opt to carry bundled libraries, but if they do, they MUST include an indication of what they bundle"，用 `Provides: bundled(<libname>)`。[S19]
- 结论：Fedora 原生包在政策上可行（bundle DXC 并声明），但需要一个 sponsor + review，且 DXC 每次升级都要跟；首版优先级低于 AppImage。COPR 可作为过渡渠道。

### 5.4 发行版/AppImage 共同的 app id 问题

见 §3.2 / §4.2：被 systemd 以 `app-<id>.scope` 启动（桌面启动器通常如此）且存在匹配 `.desktop` 时，host app 才有 app id；从终端启动常常没有。产品上应把 `Registry.Register` 作为启动早期步骤，而不是依赖启动方式。

---

## 6. 更新机制与签名对比

| 形态 | 更新载体 | 完整性/签名 | 增量 | 运维成本 |
|---|---|---|---|---|
| Flatpak（自托管） | OSTree repo + `.flatpakrepo` | OSTree commit + summary 由 GPG 签名；客户端默认 `--gpg-verify`；`flatpak build-update-repo --gpg-sign=KEY` | 静态 delta（`--generate-static-deltas`） | 中：GPG 密钥管理、CI、静态托管（GitHub Pages 可行） |
| Flatpak（Flathub） | Flathub + flat-manager | Flathub 侧签名与构建可追溯 | 是 | 低（托管），但受政策约束 |
| AppImage | 内嵌 update information + `.zsync` | 可选 GPG 内嵌签名，验证靠外部工具；默认不强制 | zsync 块级增量 | 低-中：需要自己发布 `.zsync` 与签名 |
| Arch/AUR | pacman / AUR | 官方仓库包签名；AUR 仅校验和 | 包级 | 低 |
| Debian/Fedora | apt/dnf 仓库元数据签名 | 仓库级 | 包级 | 高（打包 + 审阅 + 分支维护） |

Flatpak 细节依据：仓库用 archive-z2 + 静态 delta；`.flatpakrepo` 内嵌 base64 GPG key；`--gpg-sign` 签 summary；`--no-gpg-verify` 才关闭校验（默认开启）。[S24][S25]

---

## 7. 兼容矩阵（Plasma / portal / Flatpak runtime）

| 能力 | 需要的 xdg-desktop-portal | 需要的 KDE 后端 | 本机实测 |
|---|---|---|---|
| ScreenCast 基本会话 | 1.1.0 | Plasma 5.x | ✔ |
| 光标模式（v2） | 1.4.0 | — | ✔ |
| `VIRTUAL` 源类型 | 1.10.0 | Plasma 5.27 代码已有 | ✔ (bitmask 4) |
| `persist_mode` / `restore_token` | 1.12.0 | Plasma 5.27 | ✔ |
| `mapping_id`（v5） | 1.17.2 | Plasma 6.x | ✔ (v6) |
| `pipewire-serial`（v6） | 1.21.2 | KDE impl 6 | ✔ |
| GlobalShortcuts v1 | 1.16.0 | Plasma 5.27 | ✔ |
| `ConfigureShortcuts`（v2） | 1.21.0 | Plasma **6.5** | ✔ |
| GlobalShortcuts 要求 app id | 1.21.0 | — | 需遵守 |
| host `Registry` 接口 | 1.19.4 | — | ✔ (v1) |
| 快捷键复用修复 | — | 修复于 2025-01，预计 Plasma 6.3（bug 492992） | — |

Flatpak 侧：`--device=input`/`usb` 需要 `--require-version=1.16.0`（linter 强制）；本项目不用这两项。entitlements 需要支持 `--add-policy` 的 Flatpak（1.17+，本机 1.18.4）。[S14][S25]

runtime 选择：Flathub 当前 fdo 默认分支 **26.08**（本地已装 25.08 与 26.08，两者都含 GTK3/Vulkan/PipeWire）；KDE runtime 分支到 **6.11**。[S25]

---

## 8. 三种形态横向对比

| 维度 | Flatpak | AppImage | 发行版包（Arch AUR） |
|---|---|---|---|
| 捕获（ScreenCast） | portal，需用户授权；可持久化 | portal，同样需要 app id | portal，同样 |
| 全局热键 | portal，app id 天然满足 | portal 需 Register + .desktop；可退 KGlobalAccel | 同 AppImage |
| Vulkan | runtime GL extension（Mesa/NVIDIA），无私有 ICD | 宿主 ICD（含私有），版本随用户 | 宿主 ICD |
| DXC | 必须从源码构建并 bundle | bundle 预编译/自建 | 依赖 `extra/directx-shader-compiler` |
| 效果文件 | 仅 app data 目录 | 任意路径 | `/usr/share/magpie/effects` + 用户目录 |
| 文件系统 | 默认隔离 | 完全访问 | 完全访问 |
| 托盘 | 需 SNI 权限 | 直接可用 | 直接可用 |
| 自启 | Background portal | XDG autostart 文件 | XDG autostart / systemd user unit |
| 更新 | 好（delta + GPG） | 弱（AppImageUpdate alpha） | 中（包管理器） |
| 签名 | 默认强制 | 可选、需外部验证 | 仓库级 |
| 测试/调试 | `flatpak run`、`flatpak-builder --sandbox` | 直接运行 | 直接运行 |
| 覆盖面 | 所有装 Flatpak 的发行版 | 所有发行版（需 FUSE2） | Arch 系 |
| 主要风险 | Flathub 政策（KDE-only）、构建链复杂度 | 更新与签名、宿主依赖漂移 | 覆盖面窄；Debian/Fedora 另议 |

---

## 9. 推荐方案（decision-complete）

### 9.1 形态与顺序

1. **主：Flatpak，自托管 GPG 签名仓库**（`.flatpakrepo` + `.flatpakref` 放项目 Pages/Release 附件）。
   - app id：`io.github.qxy0happy.Magpie`（GitHub 托管 ID 规则：4 段、小写域）。[S13]
   - runtime：`org.freedesktop.Platform//26.08` + `org.freedesktop.Sdk//26.08`（已实测含所需库）。若评审要求 GTK 应用用 GNOME runtime，备选 `org.gnome.Platform`（最新稳定分支）；若后续引入 KDE 库，再切 `org.kde.Platform`。
   - branch：`stable`；Flathub 的 beta 分支只在稳定版被接受后才有意义。[S13]
2. **次：AppImage**（同一 CI 产物，`--appimage-extract-and-run` 写进文档）。
   - 附带 `io.github.qxy0happy.Magpie.desktop` 的安装脚本；启动时 `Registry.Register`；热键失败时提示"从应用菜单启动"。
3. **附加：AUR PKGBUILD**（`magpie` 稳定版 + `magpie-git`），依赖系统 DXC。
4. **Flathub 申请**：1.0 之后提交，明确说明"KDE Plasma/KWin 专属"并请求例外；Flathub 明文拒绝"仅能在特定桌面环境运行"的应用（可个案例外）。[S13] 若被拒，自托管仓库仍是完整可用的分发通道。

### 9.2 Flatpak 清单骨架

```yaml
app-id: io.github.qxy0happy.Magpie
runtime: org.freedesktop.Platform
runtime-version: '26.08'
sdk: org.freedesktop.Sdk
command: magpie
finish-args:
  - --socket=wayland
  - --device=dri
  - --talk-name=org.kde.StatusNotifierWatcher
modules:
  - name: dxcompiler          # 从源码构建，固定 tag；产物 /app/lib/libdxcompiler.so
  - name: flutter-engine      # flatpak-flutter [S15] 生成的离线源码清单
  - name: magpie              # CMake；安装到 /app/bin, /app/share/magpie/effects
```

路径约定：

| 内容 | 路径 |
|---|---|
| 内置效果 | `/app/share/magpie/effects`（只读） |
| 用户效果 | `$XDG_DATA_HOME/magpie/effects` |
| 配置 | `$XDG_CONFIG_HOME/magpie/` |
| 着色器缓存 | `$XDG_CACHE_HOME/magpie/shaders` |
| 引擎 IPC | `$XDG_RUNTIME_DIR/app/$FLATPAK_ID/magpie.sock` |

### 9.3 可接受的降级（写进 README/FAQ）

- 无 NVIDIA 私有驱动扩展时（旧分支/未安装），Vulkan 初始化失败 → 提示 `flatpak update` 并说明宿主驱动要求。
- 第三方 ICD（AMDVLK、amdgpu-pro）不可用；需要时改用 AppImage/AUR 版本。
- 窗口恢复 token 失效或匹配错误 → 重新弹出选择器（不得静默失败）。
- 托盘不可用（用户禁用 SNI/未声明权限）→ 提供"显示主窗口"的热键与命令行入口。
- 截图为 SaveFile 对话框，不是"自动保存到图片目录"。

### 9.4 验收清单（发布前必须跑）

1. `flatpak-builder --sandbox --user --install --force-clean build io.github.qxy0happy.Magpie.yaml` + `flatpak-builder-lint`（0 error）。
2. `flatpak run --command=sh ... -c 'ls /usr/lib/x86_64-linux-gnu/GL/default/lib | grep vulkan'`，并在应用内枚举 Vulkan 物理设备（确认不是 lvp）。
3. ScreenCast 全流程：`CreateSession`（**必须带 `handle_token` 与 `session_handle_token`**，见 §10）→ `SelectSources(types=2, multiple=false, cursor_mode=4)` → `Start(parent_window)` → `OpenPipeWireRemote`；确认收到 dmabuf（`SPA_DATA_DmaBuf`）而非 MemFd。
4. `persist_mode=2` 后重启应用，验证 restore_token 生效；再 `flatpak permission-reset io.github.qxy0happy.Magpie`，验证重新授权。
5. GlobalShortcuts：`BindShortcuts` 两个动作 → 重启 → `ListShortcuts` 仍在；`ConfigureShortcuts` 能打开系统设置页（Plasma ≥ 6.5）。
6. 托盘图标出现在 Plasma 系统托盘；`plasmashell` 重启后自动恢复。
7. `RequestBackground(autostart=true)` 后重新登录，应用自动启动且无窗口抢焦点。
8. 用户效果：向 `~/.var/app/<id>/data/magpie/effects` 投放 `.hlsl`，重启后出现在列表；损坏文件只报错不崩溃。
9. 打包与签名：`flatpak build-update-repo --gpg-sign=... --generate-static-deltas`，在干净用户下 `flatpak install <repo>.flatpakref` 并 `flatpak update`。
10. AppImage：在无 Flatpak 的干净 Arch 容器中运行；FUSE 缺失时 `--appimage-extract-and-run` 路径可用；GPG 签名可用 `validate` 通过。

---

## 10. 运行/测试注意（本次调查踩到的真实问题）

- **`CreateSession` 不带 `session_handle_token` 会让 xdg-desktop-portal 1.22.1 直接 abort**：`xdp-session.c:296: assertion failed: (session->token != NULL)`，服务被 systemd 重启，调用方收到 `Remote peer disconnected`。文档把这两个 token 写作可选，但实现并非如此。[S5][S25]
  - 影响：所有自动化测试、脚本化冒烟测试都必须显式传 `handle_token` + `session_handle_token`；否则看起来像"portal 坏了"。
  - 建议向上游报 issue（不在本票范围）。
- `Registry.Register` 的错误信息是 `App info not found for '<id>'`，说明是 `.desktop` 缺失而非 D-Bus 权限问题；排查时先 `ls ~/.local/share/applications/<id>.desktop`。[S25]
- `flatpak remote-ls` 在多安装（system+user）环境下必须加 `--installation=`，否则直接报错退出。[S25]

---

## 11. 未决问题

1. Flathub 是否接受"KDE Plasma 专属"的上架请求（政策允许个案例外）；若不接受，是否需要把自托管仓库作为长期唯一渠道。
2. Flutter 引擎从源码构建（flatpak-flutter）在 aarch64 上的可行性、构建时长与 Flathub 构建配额；是否需要 `flathub.json` 限定 `x86_64`（会影响覆盖面）。
3. DXC 版本策略：跟随 Arch `extra`（1.10.2605.x）还是固定较旧的稳定 tag 以匹配已验证的 HLSL 特性集；SPIR-V 后端的语义缺口需要逐效果评估。
4. 是否需要在首版就提供 `ConfigureShortcuts`（要求 Plasma ≥ 6.5），还是用 `BindShortcuts` + 文档说明（兼容 Plasma 5.27+）。
5. 多 GPU / 混合显卡下，Flatpak 内 Vulkan 设备枚举与宿主是否一致（需要真实双显卡机器验证）。
6. HDR / 10-bit 输出：PipeWire dmabuf 格式与 Vulkan swapchain 的协商（属于渲染票，但会影响 runtime/驱动最低版本）。
7. 托盘是否为首版必需：若否，可去掉 `--talk-name`，进一步缩小权限面。
8. 是否需要为 Flatpak 提供 beta 通道（自托管仓库可自由建 `beta` 分支，不受 Flathub 限制）。

---

## 12. 来源（访问日期均为 2026-11-23）

- [S1] Flatpak — Sandbox Permissions. <https://docs.flatpak.org/en/latest/sandbox-permissions.html>
- [S2] Flatpak — Basic concepts（runtime/bundled libraries）. <https://docs.flatpak.org/en/latest/basic-concepts.html>
- [S3] Flathub — com.obsproject.Studio manifest（对照用 finish-args）. <https://github.com/flathub/com.obsproject.Studio/blob/master/com.obsproject.Studio.json>
- [S4] Flatpak — Available runtimes. <https://docs.flatpak.org/en/latest/available-runtimes.html>
- [S5] XDG Desktop Portal — org.freedesktop.portal.ScreenCast (v6). <https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html>
- [S6] XDG Desktop Portal — org.freedesktop.portal.GlobalShortcuts (v2). <https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html>
- [S7] XDG Desktop Portal — org.freedesktop.host.portal.Registry (v1). <https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.host.portal.Registry.html>
- [S8] XDG Desktop Portal — Entitlements. <https://flatpak.github.io/xdg-desktop-portal/docs/entitlements.html>
- [S9] xdg-desktop-portal — NEWS（1.10/1.12/1.16/1.19.4/1.21.0/1.21.2）. <https://github.com/flatpak/xdg-desktop-portal/blob/main/NEWS.md>
- [S10] KDE — xdg-desktop-portal-kde `src/screencast.cpp`（persist/restore、窗口 Levenshtein 匹配）. <https://github.com/KDE/xdg-desktop-portal-kde/blob/master/src/screencast.cpp>
- [S11] KDE — xdg-desktop-portal-kde `src/globalshortcuts.cpp`（version 1→2、ConfigureShortcuts）. <https://github.com/KDE/xdg-desktop-portal-kde/blob/master/src/globalshortcuts.cpp>
- [S12] KWin — `src/plugins/screencast/screencaststream.cpp`（dmabuf/syncobj、MemFd 回退）. <https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.8/src/plugins/screencast/screencaststream.cpp>
- [S13] Flathub — Requirements（含 DE-locked、source build、no network、ID 规则）. <https://docs.flathub.org/docs/for-app-authors/requirements>
- [S14] Flathub — flatpak-builder-lint 规则与源码 `finish_args.py`. <https://docs.flathub.org/docs/for-app-authors/linter> ; <https://github.com/flathub-infra/flatpak-builder-lint/blob/main/flatpak_builder_lint/checks/finish_args.py>
- [S15] flatpak-flutter（Flutter 离线源码构建）. <https://github.com/TheAppgineer/flatpak-flutter>
- [S16] AppImage — FUSE 排错、更新信息、签名. <https://docs.appimage.org/user-guide/troubleshooting/fuse.html> ; <https://docs.appimage.org/packaging-guide/optional/updates.html> ; <https://docs.appimage.org/packaging-guide/optional/signatures.html>
- [S17] AppImageUpdate（发布与活跃度）. <https://github.com/AppImageCommunity/AppImageUpdate>
- [S18] Debian Policy §4.13 Embedded code copies. <https://www.debian.org/doc/debian-policy/ch-source.html#s-embedded-code>
- [S19] Fedora Packaging Guidelines — Bundling / `Provides: bundled(...)`. <https://docs.fedoraproject.org/en-US/packaging-guidelines/#bundling>
- [S20] Arch package guidelines / AUR submission guidelines. <https://wiki.archlinux.org/title/Arch_package_guidelines> ; <https://wiki.archlinux.org/title/AUR_submission_guidelines>
- [S21] DXC — HLSL→SPIR-V 映射与构建说明. <https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/SPIR-V.rst> ; <https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/BuildingAndTestingDXC.rst>
- [S22] xdg-desktop-portal 源码 `src/global-shortcuts.c`（app id 检查）、`src/xdp-app-info*.c`（host app id 推导）、`src/xdp-session.c`（token 断言）。随 1.22.1 tarball 审阅。
- [S23] Flatpak — Desktop Integration（StatusNotifier 权限）. <https://docs.flatpak.org/en/latest/desktop-integration.html>
- [S24] KDE Bug 492992（GlobalShortcuts 复用，RESOLVED FIXED 2025-01-11）. <https://bugs.kde.org/show_bug.cgi?id=492992>
- [S25] 本机实测（只读命令）：`flatpak --version`、`pacman -Q ...`、`flatpak info --show-metadata org.freedesktop.Platform//25.08`、`flatpak run --command=sh ... -c 'ls ...'`、`busctl --user get-property ...`、`busctl --user call ... Registry.Register`、`journalctl --user -u xdg-desktop-portal`、`curl archlinux.org/packages/search/json`、`curl sources.debian.org/api/search`、`pacman -Ss`。
- [S26] Flutter — Build and release a Linux app（GTK3 / 分发渠道现状）. <https://docs.flutter.dev/deployment/linux>
