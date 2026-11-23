# 现有 C++ 核心的平台抽象与复用边界

- 盘点对象：`Qxy0happy/Magpie`，本地提交 `5833e431`（`refactor: 避免使用 fmt::sprintf`），工作树干净。
- 盘点范围：`src/Magpie.Core`（21,497 行 `.cpp`/`.h`）、`src/Shared`（2,374 行，被 Core 引用的部分约 2,294 行）、`src/Magpie` 中与核心边界相关的部分（18,431 行 C++/WinRT + 4,629 行 XAML + 21 个 `.resw`）、`src/Effects`（117 个 `.hlsl`，105,390 行）。
- 访问/核查日期：2026-11-23。
- 口径：LOC 为物理行数（含空行与注释）。复用比例为 LOC 加权估算，不是工作量估算；判断依据是"这段代码是否包含 Windows/D3D11 类型或语义"。事实均有 `file:line` 或外部来源；估算与推断单独标注。

## 0. 结论摘要

1. 现有核心已经有两个"半成品接口"——`FrameSourceBase` 和 `PresenterBase` 都是抽象类，但它们的公开签名直接暴露 `HWND`、`ID3D11Texture2D`、`com_ptr<ID3D11RenderTargetView>`、`DeviceResources&`。真正的平台抽象不是"从零设计"，而是**把这两个类的签名泛化，并把 `DeviceResources`、`ScalingWindow`、`ShortcutService` 提升为接口**。
2. 纯逻辑复用集中在三处：MagpieFX 解析/HLSL 代码生成（约 1.7k 行不依赖 GPU）、效果/选项数据模型（约 0.9k 行）、通用容器与缓存（约 2k 行）。`src/Effects` 的 105k 行 HLSL 作为数据资产整体保留。
3. 必须重写的是"语义层"：`ScalingWindow`（2,158 行）、`SrcTracker`（667 行）、`CursorManager`（1,344 行）、两个 Presenter（793 行）、四种帧源的实现（约 1.3k 行）、`DeviceResources`/`TextureHelper`/`DDSHelper`（2.2k 行）。它们不是"把 D3D11 调用换成 Vulkan 调用"就能迁移，因为 Wayland 不提供 Win32 的窗口枚举、任意定位、全局输入和窗口矩形语义。
4. Core 的 LOC 估算：**直接复用约 21%，保留逻辑换后端约 12%，重写约 67%**；叠加 `src/Shared` 后为 **27.5% / 11.3% / 61.2%**。真正的风险不在比例，而在少数语义缺口（见第 7 节）：窗口模式缩放的自动定位、按进程/类名自动匹配 Profile、全局热键、光标控制、源窗口身份。
5. 建议的抽取顺序是"**先数据与效果前端，再设备与效果后端，再捕获，最后呈现/窗口/产品闭环**"。Windows 树整体冻结、不做 `#ifdef` 双后端；仅做一次机械性的项目引用调整，保留其作为效果输出的对照 oracle。

## 1. 模块盘点总表

判定图例：**复** = 原样或近乎原样复用；**抽** = 保留算法/数据模型，替换平台后端；**重** = 按 Linux 语义重写；**删** = 不进入 Linux 版本。

| # | 模块 | 主要文件（LOC） | 合计 | Windows/D3D11 依赖点 | 判定 | 说明 |
|---|---|---|---|---|---|---|
| 1 | 效果解析与代码生成 | `EffectCompiler.cpp`(1855)、`include/EffectCompiler.h`(28)、`include/EffectDesc.h`(112)、`EffectHelper.h`(47) | 2042 | `ID3DBlob`、`ID3DInclude`、`D3DCompile`、`DXGI_FORMAT`、Win32 文件 IO；COM 仅用于 `ID3DBlob`/`ID3DInclude` | 抽（约 59% 可原样） | MagpieFX 指令解析、注释剥离、参数/纹理/采样器/通道解析、HLSL prologue 生成是纯字符串处理；编译器后端与 `ID3DInclude` 需替换 |
| 2 | 效果缓存 | `EffectCacheManager.cpp/.h`(289)、`LruMemoryCache.h`(118)、`MemoryCache.h`(101)、`YasHelper.h`(68) | 576 | 文件 IO、`wil::srwlock`、YAS 二进制归档；无 D3D11 | 抽（约 78% 可原样） | 内存 LRU 与 YAS 序列化可移植；缓存键/版本需加入后端与格式能力标签 |
| 3 | 效果绘制（pass 调度） | `EffectDrawer.cpp/.h`(729) | 729 | `ID3D11Device/Context`、SRV/UAV、`Dispatch`、`SIZE`/`POINT`、`ScalingWindow::Get()` | 重（约 25% 可留） | 输出尺寸表达式、缩放类型、pass 依赖/重绘规划可留；资源绑定与 dispatch 必须重写 |
| 4 | 效果性能分析 | `EffectsProfiler.cpp/.h`(169)、`StepTimer.cpp/.h`(200) | 369 | `ID3D11Query`（disjoint/timestamp）、Win32 等待（`WaitMessage`/`SetWaitableTimerEx`） | 抽（约 33% 可原样） | 计时数据模型、FPS 统计、时间线 UI 可留；查询与等待机制重写 |
| 5 | 渲染器（前后端编排） | `Renderer.cpp/.h`(1472) | 1472 | 双 `ID3D11Device`、`OpenSharedResource`、`IDXGIKeyedMutex`、`ID3D11Fence`、Win32 消息循环、WinRT 协程 | 重（约 12% 可留） | 效果链组装、目标矩形/对齐、FPS 限制、截图流程可留；跨设备共享与消息循环重写 |
| 6 | 呈现器 | `PresenterBase.cpp/.h`(102)、`AdaptivePresenter.cpp/.h`(387)、`CompSwapchainPresenter.cpp/.h`(304) | 793 | `HWND`、`IDXGISwapChain4`、DirectComposition、`IPresentationManager`、`ID3D11Fence` | 重（约 5%） | 接口形状可留；两种 Windows 呈现策略在 Wayland 均无对应物，需 Vulkan swapchain/覆盖层实现 |
| 7 | 帧源 | `FrameSourceBase.cpp/.h`(436)、`GraphicsCapture*`(459)、`DesktopDuplication*`(250)、`GDI*`(118)、`DwmSharedSurface*`(138) | 1401 | WinRT `Windows.Graphics.Capture`、`IDXGIOutputDuplication`、GDI `BitBlt`/`HDC`、`DwmGetDxSharedSurface`（user32 私有导出）、`HWND` DPI 映射 | 重（约 4% 可留） | 抽象基类的状态机、重复帧检测算法可留；四种 Windows 捕获实现全部替换为 portal/PipeWire |
| 8 | 设备与资源 | `DeviceResources.cpp/.h`(296)、`BackendDescriptorStore.cpp/.h`(110)、`DirectXHelper.cpp/.h`(147)、`TextureHelper.cpp/.h`(335)、`DDSHelper.cpp/.h`(1066)、`DDS.h`(292) | 2246 | DXGI 工厂/适配器、`D3D11CreateDevice`、SRV/UAV、WIC（`IWICImagingFactory2`）、DDS→`ID3D11Texture2D`、`DXGI_FORMAT` | 重（约 5% 可原样，另约 9% 逻辑可留） | DDS 头解析、纹理上传/读回逻辑可留；设备、格式、图像编解码全部重写 |
| 9 | 窗口/DPI/源跟踪 | `ScalingWindow.cpp/.h`(2368)、`SrcTracker.cpp/.h`(667)、`Win32Helper.cpp/.h`(1298)、`WindowHelper.cpp/.h`(63)、`BaseWindow.h`(60)、`KeepScreenOnHelper`(39)、`ExclModeHelper`(67) | 4562 | `HWND`/WndProc、DWM、`ShellScalingApi`、`timeapi`、`SetThreadExecutionState`、`SHQueryUserNotificationState`、进程完整性、`EnumWindows` 等 | 重（约 1%） | 这是最大的一块，也是语义变化最大的一块；窗口模式缩放的自动定位、源窗口移动跟踪在 Wayland 不可实现 |
| 10 | 光标 | `CursorManager.cpp/.h`(1344)、`CursorDrawer.cpp/.h`(690) | 2034 | `HCURSOR`、`GetIconInfo`/`GetDIBits`、`ClipCursor`、`SetCursorPos`、`magnification.dll`、D3D11 光标混合 shader | 重（约 3%） | v1 建议使用 portal `cursor_mode=Embedded` 完全去掉；metadata 模式留待后续 |
| 11 | 覆盖层/ImGui | `OverlayDrawer.cpp/.h`(1502)、`OverlayHelper.cpp/.h`(418)、`ImGuiImpl.cpp/.h`(474)、`ImGuiBackend.cpp/.h`(384)、`ImGuiFontsCacheManager.cpp/.h`(237) | 3015 | `ImGuiBackend` 全部 D3D11；`ImGuiImpl` 处理 `WM_*`；字体路径为 Windows 系统字体；`UINT/WPARAM/LPARAM` | 抽（约 43% 可原样，30% 可留逻辑） | 工具栏/Profiler/窗口布局/字符串逻辑可留；渲染后端换 `imgui_impl_vulkan`，输入改 Wayland，字体改 fontconfig |
| 12 | 配置数据模型（Core 侧） | `include/ScalingOptions.h`(231)、`ScalingOptions.cpp`(149) | 380 | `HWND` 回调函数指针、`RECT`/`POINT`、Windows 捕获方式枚举 | 复/抽（约 87% 可原样） | 纯数据结构可直接复用；`showToast/showError/save` 与 `CaptureMethod` 需改为平台无关事件/枚举。UI 侧的 `Profile.h`(129)、`ScalingMode.h`(24)、`AppSettings.cpp`(1,228) 不在本行 LOC 内，见 2.8 |
| 13 | 运行时生命周期 | `include/ScalingRuntime.h`(52)、`ScalingRuntime.cpp`(240) | 292 | `HWND`、`PostThreadMessage`、`MsgWaitForMultipleObjectsEx`、WinRT `DispatcherQueue` | 抽（约 21% 可原样） | 状态机（Idle/Scaling/Waiting）可留；线程/事件循环换 Wayland + 自有队列 |
| 14 | 本地化 | `LocalizationService.cpp`(95)、`include/LocalizationService.h`(33) | 128 | WinRT `ResourceLoader`、`ResourceContext`、`bcp47mrm`、`winrt::hstring` | 重（约 8%） | UI 文本归 Flutter（ARB）；覆盖层需要独立的原生字符串表；`GetDistanceOfClosestLanguageInList` 可用 ICU/简单匹配替代 |
| 15 | 截图 | `ScreenshotFilenameTemplateHelper.cpp/.h`(380) | 380 | `HWND`（窗口标题/进程名 token）、`Win32Helper` 文件/目录、WIC 编码 | 抽（约 53% 可原样） | 模板语法解析可留；token 集合需按 Linux 语义重定义；PNG/DDS 编码换 libpng/spng/自写 DDS |
| 16 | AppX/打包应用 | `AppXReader.cpp/.h`(835) | 835 | `appmodel.h`、`AppxPackaging.h`、`propsys.h`、`wincodec.h`、`SoftwareBitmap` | 删 | 仅 Windows 打包应用（AUMID/包路径/图标）；Linux 不适用 |
| 17 | 共享基础设施 | `SmallVector.h/.cpp`(1474)、`StrHelper.h/.cpp`(369)、`Logger.h/.cpp`(237)、`ByteBuffer.h`(90)、`CommonDefines.h`(56)、`Singleton.h`(21)、`CommonSharedConstants.h`(47) | 2294 | `StrHelper` 用 `MultiByteToWideChar`、`wtypes.h`；`Logger` 有 `HRESULT`/`NTSTATUS` 接口；`CommonDefines` 用 WIL 标志宏；`CommonSharedConstants` 全是 Win32 名称 | 复/抽（约 86% 可原样） | `SmallVector`、`ByteBuffer`、`Singleton` 纯 C++；字符串转换换 `std::`/utf8 库；日志接口去掉 HRESULT/NTSTATUS 专用方法 |
| — | 合计 | | **21,497** | | | 复用 4,550 / 抽 2,553 / 重写 14,394 |

依赖强度的静态计数（`src/Magpie.Core`，不含 Shared）：`ID3D11` 201 处/32 文件、`IDXGI` 36/11、`DXGI_FORMAT` 268/21、`HWND` 143/32、`winrt::` 244/46、`wil::` 90/26；`ScalingWindow::Get()` 140 处/17 文件，`Win32Helper::` 191 处/23 文件。这说明耦合不是个别文件，而是**单例 + 平台工具类 + D3D11 类型贯穿全核心**。

头文件层面的依赖点（便于判断"换平台时哪些 include 必须消失"）：

| 头文件/技术 | 使用模块 | 位置 |
|---|---|---|
| `<Windows.h>`、`<windowsx.h>`、`<SDKDDKVer.h>` | 全核心 | `pch.h:4-6` |
| `<d3d11_4.h>`、`<dxgi1_6.h>` | 全核心 | `pch.h:12-13` |
| WIL（`wil/resource.h`、`wil/win32_helpers.h`、`wil/filesystem.h`） | 全核心 | `pch.h:27-35` |
| C++/WinRT（`winrt/base.h`、`Windows.Foundation`、`Windows.System` 等） | 全核心 | `pch.h:37-56` |
| `<d3dcompiler.h>` + `D3DCompile` | 效果编译 | `DirectXHelper.cpp:6,37` |
| `<dcomp.h>` | AdaptivePresenter、CompSwapchainPresenter | `AdaptivePresenter.h:3`、`CompSwapchainPresenter.h:3` |
| `<Presentation.h>`（`IPresentationManager`） | CompSwapchainPresenter | `CompSwapchainPresenter.h:4` |
| `<dwmapi.h>` | ScalingWindow、GraphicsCapture、CursorManager | `ScalingWindow.cpp:10`、`GraphicsCaptureFrameSource.cpp:9`、`CursorManager.cpp:8` |
| `<ShellScalingApi.h>`、`<timeapi.h>` | ScalingWindow（DPI/定时器） | `ScalingWindow.cpp:11-12` |
| `<magnification.h>` | CursorManager（光标速度） | `CursorManager.cpp:9` |
| `<wincodec.h>` / `IWICImagingFactory2` | TextureHelper、AppXReader | `TextureHelper.cpp:12`、`AppXReader.cpp:15` |
| `<Windows.Graphics.Capture.Interop.h>` | GraphicsCaptureFrameSource | `GraphicsCaptureFrameSource.h:4` |
| `<ShlObj.h>` | GraphicsCaptureFrameSource | `GraphicsCaptureFrameSource.h:3` |
| `<appmodel.h>`、`<AppxPackaging.h>`、`<propsys.h>`、`<shellapi.h>`、`<Shlwapi.h>` | AppXReader | `AppXReader.cpp:8-14` |
| `<dispatcherqueue.h>` | ScalingRuntime | `ScalingRuntime.cpp:6` |
| `<bcp47mrm.h>` | LocalizationService | `LocalizationService.cpp:4` |
| `<ShlObj.h>`（`FOLDERID_Fonts`） | OverlayDrawer | `OverlayDrawer.cpp:238-239` |
| `<parallel_hashmap/phmap.h>`、`<imgui.h>`、`<muParser.h>`、`<yas/...>`、`<spdlog/...>`、`<rapidjson/...>` | 跨模块的第三方库 | 均为可移植依赖，Linux 侧继续使用 |

## 2. 逐模块证据与依赖点

### 2.1 效果解析、代码生成、缓存

- `EffectCompiler::Compile` 的入口在 `src/Magpie.Core/EffectCompiler.cpp:1603`；读取源文件、去注释、哈希缓存分别在 `:1616`、`:1624`、`:1646-1648`。MagpieFX 版本常量为 4（`EffectCompiler.cpp:16`）。
- 解析逻辑是纯文本：指令表、参数、纹理表达式、采样器、pass 列表都在 `EffectCompiler.cpp` 的静态函数中；`EffectDesc` 是纯数据（`include/EffectDesc.h:93-110`），只有 `EffectPassDesc::cso` 是 `winrt::com_ptr<ID3DBlob>`（`EffectDesc.h:74`），这是需要替换的唯一 GPU 类型。
- 生成的 HLSL 固定使用 D3D 寄存器模型：`cbuffer __CB1 : register(b0)`、`Texture2D<...> ... : register(tN)`、`RWTexture2D<...> ... : register(uN)`、`SamplerState ... : register(sN)`（`EffectCompiler.cpp:1152-1179`、`:1474`）。这套 `register()` 语义可以被 DXC 映射到 Vulkan binding，不需要改写成 GLSL（见 4.2）。
- 所有 pass 最终都编译为 compute shader `cs_5_0`（`DirectXHelper.cpp:37`，`CompileComputeShader` 的目标写死为 `"cs_5_0"`），包括 `//!STYLE PS` 的通道——它们由生成的 compute shim 调 `PassN(pos)` 写 UAV（`EffectCompiler.cpp:1363-1470`）。这意味着 Vulkan 后端**只需要 compute pipeline**，不需要为效果实现 graphics pipeline，迁移面比想象小。
- FP16 通过宏把 `MF*` 映射为 `min16float*`（`EffectCompiler.cpp:1212-1225`）。D3DCompile 在 `cs_5_0` 下把它当 32 位存储 + 低精度提示；DXC 的默认行为也是 32 位 + `RelaxedPrecision`，只有 `-enable-16bit-types` 才生成真正的 16 位类型（[S4]）。这直接决定 FP16 效果在 Linux 上是否还有性能优势。
- 文件 IO 与 `#include` 解析依赖 `Win32Helper::ReadTextFile` 和 `ID3DInclude`（`EffectCompiler.cpp:22-54`、`:1543-1575`）。DXC 需要实现 `IDxcIncludeHandler`；这是约 50 行的适配器，不是重写。
- 缓存管理器按 `effectName + flags 低 16 位 + hash` 存取（`EffectCacheManager.h:12-14`），内存 LRU 与 YAS 序列化是平台无关的（`LruMemoryCache.h`、`MemoryCache.h`、`YasHelper.h`）。缓存内容包含 `ID3DBlob` 字节码（`EffectDesc.h:74`），Linux 侧必须换成 `std::vector<uint8_t>` 的 SPIR-V，并在键中加入后端标识、DXC 版本、目标 profile 与格式能力，否则会出现"缓存命中但管线不兼容"。

### 2.2 渲染器与呈现器

- `Renderer` 的架构是**双设备 + 双线程**：前端负责呈现、覆盖层、光标，后端负责捕获与效果；两者通过 `IDXGIKeyedMutex` 共享纹理（`Renderer.h:104-148`；`Renderer.cpp:107-120`、`:774-805`）。后端在独立线程跑 Win32 消息循环，前端通过 `PostMessage(WM_FRONTEND_RENDER)` 触发（`Renderer.cpp:830-908`）；后端每帧 `Signal` fence 并等待完成（`Renderer.cpp:1007-1061`）。
- 这个拆分的目的不是 Windows 特有，而是**把"源帧率"和"显示刷新率"解耦**：后端按捕获/效果节奏出帧，前端按显示器节奏重绘覆盖层与光标。Linux 侧应保留这个关注点分离，但实现改为单 `VkDevice` + 两个队列（或两个 `VkDevice` + dma_buf 共享），同步改为 timeline semaphore/fence。DXGI keyed mutex 在 Vulkan/Linux 没有等价物（`VK_KHR_win32_keyed_mutex` 仅适用于 Windows 句柄，[S5]），这是必须重写的部分。
- 效果链组装与目标矩形计算是可留逻辑：`_BuildEffects`（`Renderer.cpp:506-592`）、`_UpdateDestRect` 的对齐算法（`:733-772`）、`_ShouldAppendBicubic`/`_AppendBicubic`（`:610-663`）、FPS 限制（`StepTimer`）。但这些函数直接调用 `ScalingWindow::Get()` 与 `ID3D11Texture2D`，需要先解耦。
- `PresenterBase` 的签名已经是一个接口，但 `Initialize(HWND, const DeviceResources&)`、`BeginFrame(com_ptr<ID3D11Texture2D>&, com_ptr<ID3D11RenderTargetView>&, POINT&)`、`_Initialize(HWND)` 全是 D3D11/Win32（`PresenterBase.h:12-41`）。`AdaptivePresenter` 在交换链与 DirectComposition 之间切换（`AdaptivePresenter.h:7-47`），`CompSwapchainPresenter` 用 `IPresentationManager`（`CompSwapchainPresenter.h:24-36`）；两者在 Wayland 下都没有直接对应物，因为合成与呈现由合成器控制。Vulkan 侧只需要一个 `WaylandSwapchainPresenter`（或直接用全屏覆盖层的 swapchain），不需要"自适应"策略。

### 2.3 帧源

- `FrameSourceBase` 是现成的抽象基类：`Initialize(DeviceResources&, BackendDescriptorStore&)`、`Update()`、`GetOutput()`、`Name()`、`WaitType()`、纯虚 `_Initialize/_Update`（`FrameSourceBase.h:30-51`）。它已经具备 `IFrameSource` 的骨架，问题是签名绑定了 D3D11 设备和描述符缓存（`:30`、`:36`、`:64-73`）。
- 基类里有一段**可移植的算法**：重复帧检测。它用 compute shader 把当前帧与上一帧做差异统计，读回后动态决定跳过多少帧（`FrameSourceBase.cpp:248-340`；shader 为 `shaders/DuplicateFrameCS.hlsl`）。Vulkan 侧可用 storage buffer + 间接 dispatch + staged readback 重写，逻辑与阈值策略可保留。
- 四种 Windows 实现：
  - `GraphicsCaptureFrameSource`：WinRT `Windows.Graphics.Capture` + `IGraphicsCaptureItemInterop`，用 `DwmGetWindowAttribute` 裁掉边框（`GraphicsCaptureFrameSource.h:3-5`；`.cpp:9`、`:17-49`）。
  - `DesktopDuplicationFrameSource`：`IDXGIOutput1::DuplicateOutput` + `IDXGIOutputDuplication`（`.h:25-26`）。
  - `GDIFrameSource`：`IDXGISurface1::GetDC` + `BitBlt`（`GDIFrameSource.cpp:56-88`）。
  - `DwmSharedSurfaceFrameSource`：从 `user32.dll` 动态取未文档化导出 `DwmGetDxSharedSurface`（`.cpp:17-29`）。
- 这四种实现的共同前提是"有一个 `HWND`，能查询它的客户区、DPI、边框、可见性、是否挂起，并能移动/聚焦它"。Wayland 普通客户端不具备这些能力；`SrcTracker` 的整套逻辑（`SrcTracker.h:30-97`，`.cpp` 566 行）因此没有移植价值。portal 的窗口流只给出 PipeWire 流与 `source_type`，不给出窗口矩形（见 7.2）。

### 2.4 设备与资源

- `DeviceResources` 是具体类，没有接口：直接暴露 `IDXGIFactory7*`、`ID3D11Device5*`、`ID3D11DeviceContext4*`、`IDXGIAdapter4*`（`DeviceResources.h:15-24`），并负责适配器选择、WARP/FP16/tearing 探测（`.cpp:26-105`）。Linux 侧需要新的 `VulkanDevice`，按 `GraphicsCardId`（vendor/device/index）选择 `VkPhysicalDevice`；Vulkan 没有"index 稳定"的保证，应优先用 `VkPhysicalDeviceIDProperties::deviceUUID` 或 PCI 地址。
- `BackendDescriptorStore` 缓存 texture→SRV/UAV 视图（`BackendDescriptorStore.h:12-32`）。Vulkan 对应的是 descriptor set/pool 与 image view 缓存；`VkImageView` 的格式在创建时固定，不能像 D3D11 那样"同一个资源换一种视图格式"，因此缓存键必须包含格式与 usage。
- `TextureHelper` 用 WIC 解码 png/jpg/bmp/tiff（`TextureHelper.cpp:12-82`），`DDSHelper` 用 1,047 行解析 DDS 并创建 `ID3D11Texture2D`（`DDSHelper.cpp`；`DDS.h:257-290` 是纯头文件结构）。Linux 侧：DDS 头解析与块压缩格式映射可保留；WIC 换成 libpng/spng/libjpeg-turbo（或 stb_image，但要注意其格式覆盖与安全性）；创建纹理换成 `VkImage` + staging upload。
- `DirectXHelper` 是 D3D11 工具集（`D3DCompile`、`CreateTexture2D`、WARP 检测）（`DirectXHelper.h:7-34`；`.cpp:13-110`）。Vulkan 侧对应 `VulkanHelper`：格式映射、image/buffer 创建、一次性命令缓冲上传、mip 生成。
- 需要特别记录的格式差异：`EffectHelper.h:16-38` 把 20 种 `EffectIntermediateTextureFormat` 映射为 `DXGI_FORMAT`。Vulkan 的等价名称不同（`R10G10B10A2_UNORM` → `VK_FORMAT_A2B10G10R10_UNORM_PACK32`，`R11G11B10_FLOAT` → `VK_FORMAT_B10G11R11_UFLOAT_PACK32`），且**强制 storage image 支持并不覆盖全部格式**：必需格式表对部分格式带有 `{sym3}` 条件标记（依赖 `shaderStorageImageExtendedFormats`），`B10G11R11_UFLOAT_PACK32` 也没有无条件的 storage image 保证（[S6]）。运行时必须逐格式查询 `VkFormatProperties::optimalTilingFeatures`，为效果纹理选择可用格式或明确失败。

### 2.5 窗口、DPI、源跟踪

- `ScalingWindow` 是 2,158 行的 Win32 窗口管理器 + 消息泵 + 缩放编排：`Start(HWND, ScalingOptions&&)`（`ScalingWindow.h:31`）、窗口/渲染子窗口/边框辅助窗口/触控洞窗口的 `HWND` 数组（`:175-192`）、DPI 与无边框计算（`:177-181`）、`_MessageHandler`（`.cpp:412-897`）、`_StartImpl`（`.cpp:45-322`）。它同时承担了产品交互（窗口模式缩放、工具栏、焦点/置顶、3D 游戏模式检测）。
- `SrcTracker` 跟踪源窗口的 `HWND`、窗口矩形、客户区矩形、焦点、最大化、移动状态（`SrcTracker.h:30-98`），并按 `SrcTracker::_CalcSrcRect` 计算裁剪后的源矩形（`.cpp`）。这套语义依赖 `GetClientRect`、`DwmGetWindowAttribute`、`GetWindowRect`、`IsWindowVisible` 等 Win32 API。
- `Win32Helper` 是 1,039 行的平台工具箱：窗口类名/标题/进程路径、DPI、完整性级别、`AdvancedWindowHitTest`、文件 IO、`RunParallel`、DLL 函数加载、`WaitForDwmComposition`（`include/Win32Helper.h:10-241`）。它不是"平台抽象"，而是"平台实现集合"，Linux 侧不应逐函数翻译，而应按用途拆到 `IWindowSystem`、`IFileSystem`、`IPlatformInfo`。
- `BaseWindow` 是 WndProc 模板（`include/BaseWindow.h:31-53`），`KeepScreenOnHelper` 用 `SetThreadExecutionState`（`KeepScreenOnHelper.cpp:7-22`），`ExclModeHelper` 用 `__DDrawExclMode__` 互斥体模拟独占全屏（`ExclModeHelper.cpp:12-56`）。后两者在 Linux 分别对应 logind 的 `Inhibit`（[S10]）和"没有等价物"（Wayland 的 DND 由合成器/通知服务决定，不能由客户端模拟）。
- 关键结论：`ScalingWindow` 不能"移植"，只能"拆成产品编排层 + 平台窗口层"。编排层保留：缩放状态机、窗口模式/全屏模式切换、工具栏状态、源矩形→目标矩形映射、错误上报。平台层重写：创建全屏 surface、选择输出、接收 pointer/keyboard/axis 事件、处理 configure/close、查询输出拓扑与缩放。

### 2.6 光标

- `CursorManager`（1,220 行）是 Win32 光标控制的集合：`ClipCursor`、`SetCursorPos`、`GetIconInfo`/`GetDIBits`（在 `CursorDrawer`）、光标速度调整（`magnification.dll`，`.cpp:9`）、命中测试、自动隐藏、源窗口拖动时的光标锁定（`CursorManager.h:60-121`）。
- `CursorDrawer`（605 行）把 `HCURSOR` 解析为彩色/掩码/单色纹理（`CursorDrawer.cpp:377-470`），用三个 pixel shader 做预乘 alpha / 掩码 / 单色混合（`shaders/MaskedCursorPS.hlsl`、`MonochromeCursorPS.hlsl`、`SimplePS.hlsl`）。
- Wayland 核心协议不提供全局屏幕坐标，客户端**不能查询/设置全局光标位置，也不能裁剪光标**；指针锁定/相对运动需要 `zwp_pointer_constraints_v1`/`zwp_relative_pointer_v1` 且通常需要用户手势授权。portal ScreenCast 提供 `cursor_mode`：Hidden/Embedded/Metadata（[S1]）。若选 Embedded，合成器把光标画进流，`CursorManager`/`CursorDrawer` 在 v1 可以整体删除；若选 Metadata，则需要解析 PipeWire 光标元数据并在覆盖层合成，工作量另计。

### 2.7 覆盖层与 ImGui

- 覆盖层已经是"平台输入 + 渲染后端"分层：`ImGuiImpl` 负责窗口布局、鼠标位置、`WM_*` 消息（`ImGuiImpl.h:18-44`；`.cpp:293-380`），`ImGuiBackend` 负责 D3D11 管线/字体纹理/绘制（`ImGuiBackend.h:14-39`；`.cpp:222-251`）。这个分层应保留。
- `OverlayDrawer`（1,378 行）是产品逻辑：工具栏、Profiler 时间线、窗口位置约束、Fitts 定律调整、DPI 缩放、字符串查找（`OverlayDrawer.h:18-121`）。其中与平台相关的只有字体路径、`UINT/WPARAM/LPARAM` 消息、`ScalingWindow::Get()` 与 `CursorManager`。
- 字体是隐蔽的移植点：`GetSystemFontsFolder()` 用 `SHGetKnownFolderPath(FOLDERID_Fonts)`（`OverlayDrawer.cpp:234-245`），UI 字体是 `Segoe UI`，图标字体是私有 `SegoeIcons.ttf`（`:258-262`），中文/日文/韩文/泰米尔语分别加载 `msyh.ttc`/`msjh.ttc`/`YuGothM.ttc`/`malgun.ttf`/`Nirmala.ttf`（`:360-380`）。Linux 侧应改为 fontconfig 查询 + 自带图标字体；ImGui 的字体图集缓存（`ImGuiFontsCacheManager`）格式可复用，但路径与度量会变。
- 渲染后端可以直接用官方 `imgui_impl_vulkan`（ImGui 1.91.8 已包含，[S11]）；需要自写的是 Wayland 平台后端（或把 `wl_pointer`/`wl_keyboard` 事件直接喂给 ImGui IO），以及把 `ScalingWindow` 的窗口矩形/DPI 替换为 `IWindowSystem` 的输出。

### 2.8 配置、Profile、缩放模式

- `ScalingOptions` 是引擎的输入契约：效果链 `std::vector<EffectOption>`、裁剪、显卡 ID、帧率、光标、捕获方式、对齐、工具栏状态、截图目录/模板（`include/ScalingOptions.h:180-223`）。纯数据，可直接复用；需要改的是：
  - `showToast/showError/save` 是带 `HWND` 的函数指针（`:224-226`），应改为平台无关的 `IEngineHost` 回调或事件；
  - `CaptureMethod` 枚举是 Windows 捕获方式（`:6-12`），Linux 侧应改为 `PortalWindow`/`PortalMonitor`（或后端能力枚举）；
  - `Prepare()` 里有 Windows 专属约束（"GDI/DwmSharedSurface 不支持捕获标题栏"，`ScalingOptions.cpp:53-55`）。
- UI 侧的数据模型 `Profile`（`src/Magpie/Profile.h:36-127`）、`ScalingMode`/`EffectItem`（`src/Magpie/ScalingMode.h:6-23`）是纯数据，可复用为 Flutter 的 JSON 模型或原生快照模型。`AppSettings` 的 `config.json` 写入/读取是 rapidjson（`src/Magpie/AppSettings.cpp:511-633`、`:634-880`），schema 应保留以兼容旧配置（票 #12）。
- **Profile 匹配逻辑不可直接移植**：`ProfileService::GetProfileForWindow(HWND, ...)` 用 `Win32Helper::GetWindowClassName`、`GetWindowExePath`、`AppXReader` 匹配 `pathRule`/`classNameRule`（`src/Magpie/ProfileService.cpp:209-246`）。Wayland 普通客户端拿不到前台窗口的 exe/class，portal 窗口流也不返回 appId/title（见 7.2）。这需要产品级重设计：按 portal 选择结果绑定 Profile、按 restore_token 记忆、或由用户手动选择。

### 2.9 本地化、日志、截图、性能分析、AppX

- 本地化：`LocalizationService` 用 `ResourceLoader::GetForViewIndependentUse("Magpie/Resources")` 读取 `.resw`（`LocalizationService.cpp:78-87`），语言列表硬编码 19 种（`:10-30`），语言匹配用 `bcp47mrm` 的 `GetDistanceOfClosestLanguageInList`（`:47`）。Flutter 侧应使用 ARB/intl（[S9]）；原生覆盖层需要一个由同一翻译目录生成的轻量字符串表（JSON/FlatBuffers），否则会出现两套翻译源。`src/Magpie/Resources.language-*.resw` 的 21 个文件是内容资产，不是代码资产。
- 日志：`Logger` 基于 spdlog 的 rotating file sink（`src/Shared/Logger.cpp:9-30`），核心逻辑可复用；但接口暴露 `Win32Error/NTError/ComError`（`Logger.h:62-79`），Linux 侧应改为 errno/`std::error_code`/D-Bus 错误。日志目录常量是 `logs\magpie.log`（`CommonSharedConstants.h:21-25`），应改为 XDG state dir。
- 截图：模板解析在 `ScreenshotFilenameTemplateHelper.cpp`（369 行），支持 `%PN%`（进程名）、窗口标题等 token；`Renderer::_TakeScreenshotImpl` 负责选纹理、拷贝到 staging、WIC 编码（`Renderer.cpp:1146-1320`），`TextureHelper::SaveTexture` 决定 png/dds（`TextureHelper.cpp:295-313`）。Linux 侧：模板解析可留；token 集合需去掉"窗口标题/进程名"或改为"源会话名"；PNG 编码换 libpng/spng；DDS 写回逻辑可留。
- 性能分析：`EffectsProfiler` 用 `ID3D11Query` 的 disjoint + timestamp（`EffectsProfiler.h:15-41`），每帧查询每个 pass 的 GPU 时间；覆盖层的时间线 UI 在 `OverlayDrawer`。Vulkan 对应 `vkCmdWriteTimestamp2` + `vkGetQueryPoolResults`，需要 `timestampComputeAndGraphics`/`timestampPeriod`，并且时间戳校准与 D3D 不同。数据模型（每 pass 时间、FPS、时间线颜色）可留。
- AppX：`AppXReader` 依赖 `appmodel.h`、`AppxPackaging.h`、`propsys.h`、WIC（`AppXReader.cpp:1-15`），返回 `SoftwareBitmap` 图标（`include/AppXReader.h:24-28`）。Linux 删除；窗口选择由 portal 对话框承担。

## 3. 现有接口与缺口

| 现有类型 | 现状 | 是否可作为接口 | 主要泄漏 |
|---|---|---|---|
| `FrameSourceBase` | 抽象类，`Name/WaitType/_Initialize/_Update` 纯虚（`FrameSourceBase.h:42-51`） | 是，改签名即可 | `DeviceResources&`、`BackendDescriptorStore&`、`ID3D11Texture2D*`、`HWND` DPI 映射、Win11 圆角 |
| `PresenterBase` | 抽象类，`BeginFrame/EndFrame/OnResize/_Initialize` 纯虚（`PresenterBase.h:8-41`） | 是，改签名即可 | `HWND`、`com_ptr<ID3D11Texture2D>`、`com_ptr<ID3D11RenderTargetView>`、`POINT` |
| `DeviceResources` | 具体类，无虚函数（`DeviceResources.h:7-41`） | 否 | DXGI/D3D11 类型直接暴露 |
| `EffectCompiler` | 单静态方法的 struct（`include/EffectCompiler.h:19-26`） | 否，需拆成 parser/generator + compiler backend | `EffectDesc` 内含 `ID3DBlob` |
| `EffectDrawer` | 具体类，持有 D3D11 资源（`EffectDrawer.h:18-95`） | 否 | `ID3D11*`、`SIZE`、`ScalingWindow::Get()` |
| `ScalingWindow` | 单例 + Win32 窗口 + 消息泵（`ScalingWindow.h:12-208`） | 否 | `HWND`、`RECT`、WndProc、140 处 `Get()` 调用 |
| `ShortcutService`（UI 层） | 低级键盘钩子 + `RegisterHotKey`（`src/Magpie/ShortcutService.cpp:14-58`） | 否 | `WH_KEYBOARD_LL`、`HWND`、Win32 虚拟键码 |

**结论：Core 里没有 `IGraphicsDevice`、`IWindowSystem`、`IHotkeyService`，也没有效果编译器/管线的接口。**`IFrameSource`/`IPresenter` 只是"名字还没换"的抽象类。抽象工作应优先做在这三个缺口上，而不是重新发明帧源/呈现器的概念。

## 4. 建议的平台接口边界

设计原则（以下接口签名是设计草图，用于界定职责，不是最终头文件）：
- 公共头文件不出现 `HWND`、`RECT`、`POINT`、`ID3D11*`、`winrt::`、`wil::`、`DXGI_FORMAT`。
- 用值类型 `Size/Rect/Offset`、`TextureFormat`（自有枚举）、`TextureHandle`/`BufferHandle`（opaque）替代平台类型。
- 错误用 `ScalingError`/`std::expected`，不用 `HRESULT`。
- 不用单例：`Renderer`/`EffectDrawer`/`ImGuiImpl` 通过构造函数拿到 `IGraphicsDevice&`、`IWindowSystem&`，而不是 `ScalingWindow::Get()`。
- 接口按"变化原因"拆分，避免 god object。

### 4.1 `IFrameSource`（取代 `FrameSourceBase`）

```cpp
enum class FrameSourceWait { None, Event, Frame };
enum class FrameSourceState { NewFrame, Waiting, Error };

struct FrameTexture {
    TextureHandle texture;      // 后端自有句柄
    TextureFormat format;
    Size size;
    // 可选：dma_buf fd / modifier / acquire fence
};

class IFrameSource {
public:
    virtual ~IFrameSource() = default;
    virtual bool Initialize(const FrameSourceInitParams&) = 0;
    virtual bool Start() = 0;
    virtual FrameSourceState Update() = 0;
    virtual FrameSourceWait WaitType() const = 0;
    virtual FrameTexture Output() const = 0;
    virtual const char* Name() const = 0;
    virtual std::optional<Rect> ContentRect() const = 0; // 源内容在流中的裁剪
    virtual void OnCursorVisibilityChanged(bool visible, bool destroying) = 0;
};
```

适配：
- `PortalPipeWireFrameSource`（新）：portal ScreenCast → PipeWire → `SPA_DATA_DmaBuf`（首选）/`SPA_DATA_MemFd`/`SPA_DATA_MemPtr`（[S8]）→ 导入 `VkImage`（`VK_KHR_external_memory_fd` + `VK_EXT_external_memory_dma_buf`，[S5]）或 staging upload。
- 重复帧检测保留为 `IFrameSource` 的可选 mixin/策略（`DuplicateFrameDetector`），不放进接口。
- Windows 四种实现不实现该接口；它们留在冻结树里，作为 oracle。

### 4.2 `IPresenter`（取代 `PresenterBase`）

```cpp
struct PresentTarget {
    TextureHandle image;
    TextureViewHandle view;
    Offset drawOffset;
};

class IPresenter {
public:
    virtual ~IPresenter() = default;
    virtual bool Initialize(IOverlayWindow&, IGraphicsDevice&) = 0;
    virtual std::optional<PresentTarget> BeginFrame() = 0;
    virtual void EndFrame(bool waitForGpu) = 0;
    virtual bool OnResize() = 0;
    virtual void OnEndResize(bool& shouldRedraw) = 0;
    virtual bool SupportsDirectScanout() const = 0;
};
```

- Linux 实现：`WaylandSwapchainPresenter`（`VK_KHR_wayland_surface` + `VkSwapchainKHR`，[S5]）。`AdaptivePresenter` 的"DComp/交换链自适应"没有对应物；不要为了"结构对称"保留两个实现。
- `BeginFrame` 返回的 `PresentTarget` 是前端渲染目标，覆盖层与光标画到同一个 image；`EndFrame` 负责 acquire/present 与 fence。
- 若后续需要"零拷贝直出"，`SupportsDirectScanout` 暴露给上层做策略，但 v1 不需要。

### 4.3 `IGraphicsDevice`（取代 `DeviceResources` + `BackendDescriptorStore` + `DirectXHelper`）

```cpp
class IGraphicsDevice {
public:
    virtual ~IGraphicsDevice() = default;
    virtual bool Initialize(const DeviceInitParams&) = 0;

    virtual FormatCaps QueryFormat(TextureFormat) const = 0;

    virtual TextureHandle CreateTexture(const TextureDesc&) = 0;
    virtual TextureViewHandle CreateView(TextureHandle, TextureViewDesc) = 0;
    virtual BufferHandle CreateBuffer(const BufferDesc&) = 0;

    virtual std::optional<TextureHandle> ImportDmaBuf(int fd, const DmaBufDesc&) = 0;
    virtual std::optional<int> ExportDmaBuf(TextureHandle) = 0;

    virtual FenceHandle CreateFence() = 0;
    virtual void WaitFence(FenceHandle, uint64_t value) = 0;
    virtual void CollectGarbage() = 0;
};
```

- 不要在这个接口里放 `CreateComputePipeline`/`BindDescriptorSet`；这些属于 `IEffectPipeline`/`IEffectCompiler` 的实现细节，否则接口会变成"整个 Vulkan 封装"。
- `QueryFormat` 必须返回 storage image / sampled / color attachment / linear filter / 16-bit 等能力，供效果编译器选择格式（见 7.4）。
- 描述符缓存（原 `BackendDescriptorStore`）作为 `IGraphicsDevice` 的内部实现或独立的 `DescriptorCache`，不进入公共接口。

### 4.4 `IEffectCompiler` + `IEffectPipeline`（取代 `EffectCompiler` + `EffectDrawer`）

```cpp
enum class BytecodeFormat { DXBC, SPIRV };

struct EffectPassCode {
    BytecodeFormat format;
    std::vector<uint8_t> bytecode;
    uint32_t numThreads[3];
    uint32_t blockSize[2];
    std::string desc;
    uint32_t flags;
};

class IEffectCompiler {
public:
    virtual ~IEffectCompiler() = default;
    virtual bool Compile(EffectDesc& desc, EffectCompileFlags flags,
                         const ParamMap* inlineParams) = 0;
};

class IEffectPipeline {
public:
    virtual ~IEffectPipeline() = default;
    virtual bool Initialize(const EffectDesc&, const EffectOption&,
                            IGraphicsDevice&, TextureHandle* inOut) = 0;
    virtual void Draw(IEffectsProfiler&) = 0;
    virtual TextureHandle Output() const = 0;
    virtual bool ResizeTextures(const EffectDesc&, const EffectOption&,
                                IGraphicsDevice&, TextureHandle* inOut) = 0;
};
```

- **关键拆分**：MagpieFX parser + HLSL 生成器是平台无关的 `libmagpiefx`；`EffectCompiler` 只是"把生成的 HLSL 交给某个后端编译"的薄层。Windows 后端是 `D3DCompileBackend`（冻结），Linux 后端是 `DxcSpirvBackend`。
- `EffectPassDesc::cso` 改为 `EffectPassCode`；`EffectDesc` 其余字段不变（`EffectDesc.h:93-110`）。
- `EffectDrawer` 的 pass 依赖规划（`_CalcPassesToDrawForExport`，`EffectDrawer.cpp:532-620`）与输出尺寸计算（`:300-375`）保留在 `IEffectPipeline` 的公共基类里；D3D11/Vulkan 只实现资源绑定与 dispatch。
- shader dialect 的差异集中在一个适配器里：
  - D3D11：`cs_5_0` + `D3DCompile` + `min16float` 宏（现状）。
  - Vulkan：DXC `-T cs_6_0 -spirv`；为每个 UAV 生成 `[[vk::image_format("...")]]`（否则 storage image 为 Unknown 格式，需要 `shaderStorageImageWriteWithoutFormat`，[S4]）；`register(bN/tN/uN/sN)` 由 DXC 映射到 descriptor set/binding（[S4]）；常量缓冲用 `-fvk-use-dx-layout` 以保持现有 CPU 侧的紧凑打包（需要启用 `VK_EXT_scalar_block_layout`，[S4]）。
  - FP16：是否加 `-enable-16bit-types` 取决于设备是否支持 `shaderFloat16`（以及 16 位存储需求）；不加则 `min16float` 退化为 32 位 + `RelaxedPrecision`（[S4]），性能会明显低于 D3D11 上的 FP16。

### 4.5 `IWindowSystem`（取代 `ScalingWindow`/`SrcTracker`/`Win32Helper` 的窗口部分）

建议拆成三个窄接口，而不是一个 god object：

```cpp
class ISourceSession {          // portal 选择与会话生命周期
public:
    virtual bool SelectWindow(SelectOptions) = 0;  // 弹出 portal 对话框
    virtual bool Start() = 0;                      // 返回 PipeWire 流
    virtual SourceInfo Info() const = 0;           // 尺寸/来源类型/restore token
    virtual void Close() = 0;
};

class IOverlayWindow {          // 全屏覆盖层
public:
    virtual bool Create(const OverlayDesc&) = 0;   // 指定输出、全屏、无边框
    virtual bool SetFullscreen(OutputId) = 0;
    virtual Size PixelSize() const = 0;
    virtual float ScaleFactor() const = 0;
    virtual void Show() = 0;
    virtual void Hide() = 0;
    virtual void RequestRedraw() = 0;
    virtual void SetCursorVisible(bool) = 0;
    // 事件通过回调/队列交给上层：pointer, keyboard, axis, close, configure
};

class IDisplayTopology {        // 输出拓扑
public:
    virtual std::vector<OutputInfo> Outputs() const = 0;
    virtual std::optional<OutputInfo> Primary() const = 0;
};
```

- `ISourceSession` 的实现是 portal + PipeWire；`SourceInfo` 只包含 portal 实际给出的信息（source_type、流尺寸、pipewire-serial、restore token）。**不要假设能拿到 appId/title/窗口矩形**（见 7.2）。
- `IOverlayWindow` 的实现是 xdg-toplevel + `set_fullscreen(output)`（[S7]）或 layer-shell（若票 #9 决定使用；KWin 对 `zwlr_layer_shell_v1` 的支持需在 #2/#9 中验证，本票不替 #9 做决定）。`set_fullscreen` 的输出只是"偏好"，最终由合成器决定（[S7]）；覆盖层必须按"我拿到的是某个输出的全屏 surface"来设计，而不是"我能把窗口放到任意坐标"。
- 指针/键盘事件由 `wl_pointer`/`wl_keyboard` 提供；不要暴露"全局鼠标位置"或"设置光标位置"，因为 Wayland 不提供。
- 原 `SrcTracker` 的功能分解：`SourceInfo`（流尺寸/来源）+ 用户裁剪（`ScalingOptions.cropping`）+ 输出拓扑（缩放因子）。"跟随源窗口移动"在 Wayland 下删除。

### 4.6 `IHotkeyService`（取代 UI 层 `ShortcutService`）

```cpp
enum class HotkeyAction { Scale, WindowedScale, Toolbar, Screenshot };

class IHotkeyService {
public:
    virtual ~IHotkeyService() = default;
    virtual bool Initialize() = 0;
    virtual bool Bind(HotkeyAction, std::string_view preferredTrigger) = 0;
    virtual void Unbind(HotkeyAction) = 0;
    virtual void SetActivatedCallback(std::function<void(HotkeyAction)>) = 0;
};
```

- Linux 实现：`org.freedesktop.portal.GlobalShortcuts`（CreateSession → BindShortcuts → Activated 信号，[S2]）。KDE 的 portal 后端包含该接口的实现文件（`src/globalshortcuts.cpp`、`GlobalShortcutsDialog.qml`，[S3]）。
- 语义差异必须在 UI 中体现：portal 会弹窗让用户确认/配置快捷键，应用不能静默注册；用户可能拒绝或改键；`preferred_trigger` 只是建议（[S2]）。因此"快捷键设置页"要显示 portal 返回的 `trigger_description`，而不是假设自己写入的键值生效。
- Windows 实现保留在冻结树（`RegisterHotKey` + 低级钩子，`src/Magpie/ShortcutService.cpp:14-58`），不进入 Linux 构建。

### 4.7 现有类到目标接口的映射

| 现有类/文件 | 目标接口/实现 | 动作 |
|---|---|---|
| `FrameSourceBase` | `IFrameSource` | 泛化签名（去掉 `DeviceResources&`/`ID3D11Texture2D`）；状态机与重复帧策略保留 |
| `GraphicsCaptureFrameSource` | `PortalPipeWireFrameSource` | 重写（WinRT Capture → portal + PipeWire） |
| `DesktopDuplicationFrameSource`、`GDIFrameSource`、`DwmSharedSurfaceFrameSource` | 无 | 删除，不进入 Linux 构建 |
| `PresenterBase` | `IPresenter` | 泛化签名（去掉 `HWND`/D3D11 类型） |
| `AdaptivePresenter`、`CompSwapchainPresenter` | `WaylandSwapchainPresenter` | 重写；不保留"自适应"策略 |
| `DeviceResources` | `VulkanDevice : IGraphicsDevice` | 重写（设备/队列/格式能力/资源创建） |
| `BackendDescriptorStore` | `DescriptorCache`（`IGraphicsDevice` 内部） | 重写（VkImageView/VkDescriptorSet 缓存） |
| `DirectXHelper` | `VulkanHelper` | 重写（格式映射、上传、命令缓冲） |
| `TextureHelper`、`DDSHelper` | `ImageLoader`、`DdsCodec` | 部分重写：DDS 头/块格式保留；WIC 换 PNG/JPEG 解码器 |
| `EffectCompiler` | `libmagpiefx` + `IEffectCompiler`（`DxcSpirvBackend`） | 拆分：parser/generator 复用，编译后端重写 |
| `EffectDrawer` | `IEffectPipeline`（Vulkan 实现） | 重写资源绑定/dispatch；pass 依赖与尺寸计算保留 |
| `EffectsProfiler` | `VulkanEffectsProfiler` | 重写查询/读回；数据模型与时间线 UI 保留 |
| `Renderer` | `ScalerPipeline`（后端）+ `OverlayFrontend`（前端） | 重写编排与同步；效果链/对齐/FPS 逻辑保留 |
| `ScalingWindow` | `EngineRuntime` + `IOverlayWindow` | 拆分：产品编排保留，窗口几何/消息泵重写 |
| `SrcTracker` | `SourceInfo` + `ScalingOptions.cropping` | 删除/替代；不做窗口跟踪 |
| `CursorManager`、`CursorDrawer` | 无（v1 用 portal Embedded cursor） | 删除；metadata 模式另立票据 |
| `OverlayDrawer`、`ImGuiImpl` | `OverlayController` + Wayland ImGui 平台后端 | 抽：UI 逻辑保留，输入/字体/窗口替换 |
| `ImGuiBackend` | `imgui_impl_vulkan` | 替换为官方后端 |
| `LocalizationService` | Flutter ARB + 原生字符串表 | 替换 |
| `AppXReader` | 无 | 删除 |
| `ShortcutService`（UI 层） | `IHotkeyService`（portal GlobalShortcuts） | 重写 |
| `ScalingRuntime` | `EngineRuntime` | 抽：状态机保留，线程/事件循环重写 |

## 5. 可直接复用的纯逻辑与数据模型

| 资产 | 位置 | 复用方式 | 注意事项 |
|---|---|---|---|
| `SmallVector` | `src/Shared/SmallVector.h/.cpp`（1,474） | 原样 | 无平台依赖；注意 `_M_ARM64` 宏在 `YasHelper.h`，不在 SmallVector |
| `ByteBuffer`、`Singleton` | `src/Shared/ByteBuffer.h`(90)、`Singleton.h`(21) | 原样 | — |
| `LruMemoryCache`、`MemoryCache` | `src/Magpie.Core/LruMemoryCache.h`(118)、`MemoryCache.h`(101) | 原样 | 线程安全由调用方保证（现状如此） |
| `EffectDesc` 数据模型 | `include/EffectDesc.h:8-110` | 抽 | `EffectPassDesc::cso` 换 `EffectPassCode`；`EffectIntermediateTextureFormat` 枚举保留，映射到自有 `TextureFormat` |
| MagpieFX 解析/HLSL 生成 | `EffectCompiler.cpp:60-1600` | 抽 | 与文件 IO、`ID3DInclude`、`D3DCompile` 解耦；生成器加 Vulkan 方言 |
| `EffectHelper` 格式表 | `EffectHelper.h:16-38` | 抽 | `DXGI_FORMAT`/texel 类型名改为自有枚举；`srvTexelType/uavTexelType` 字符串仍可用于 HLSL |
| `ScalingOptions` 数据 | `include/ScalingOptions.h:180-223` | 原样/抽 | 回调函数指针与 `CaptureMethod` 需改 |
| `Profile`、`ScalingMode`、`EffectItem` | `src/Magpie/Profile.h:36-127`、`ScalingMode.h:6-23` | 原样（作为 schema） | `std::wstring` 建议改 UTF-8；Windows 专属字段（AppX、launchParameters）按票 #12 处理 |
| `config.json` schema | `src/Magpie/AppSettings.cpp:511-880` | 复用 schema，不复用代码 | Flutter 侧用 Dart 模型；保留旧键以支持迁移 |
| 截图模板解析 | `ScreenshotFilenameTemplateHelper.cpp` | 抽 | token 集合需重定义；`HWND` 相关 token 删除 |
| 覆盖层 UI 逻辑 | `OverlayDrawer.cpp`（除字体/输入/`ScalingWindow`） | 抽 | 工具栏、Profiler 时间线、窗口约束、字符串查找可留 |
| ImGui 字体图集缓存 | `ImGuiFontsCacheManager.cpp/.h`（237） | 抽 | 缓存格式可留；字体路径/度量换 fontconfig |
| 效果资产 | `src/Effects`（117 个 `.hlsl`，105,390 行；17 个 `.dds`） | 原样 | MagpieFX v4 是数据格式；`StubDefs.hlsli` 仅用于 IDE/静态检查 |
| 内置 shader | `src/Magpie.Core/shaders/*.hlsl`（7 个） | 抽 | `DuplicateFrameCS` 可重编译为 SPIR-V；ImGui/Cursor 的 VS/PS 改用官方 Vulkan shader 或等价 SPIR-V |
| 日志核心 | `src/Shared/Logger.cpp/.h`（237） | 抽 | spdlog sink 可留；去掉 `Win32Error/NTError/ComError` 接口 |
| 字符串工具 | `src/Shared/StrHelper.h/.cpp`（369） | 抽 | `Trim/Concat/Replace` 等可留；`MultiByteToWideChar`/`BSTR` 部分替换 |

**明确不复用**：`AppXReader`、`Cursors`、`Win32Helper`、`ScalingWindow`、`SrcTracker`、`BaseWindow`、`WindowHelper`、`KeepScreenOnHelper`、`ExclModeHelper`、`AdaptivePresenter`、`CompSwapchainPresenter`、`GraphicsCaptureFrameSource`、`DesktopDuplicationFrameSource`、`GDIFrameSource`、`DwmSharedSurfaceFrameSource`、`DDSHelper` 的 D3D11 部分、`LocalizationService`。

## 6. 复用/改造/重写比例估算

按第 1 节各模块的行数拆分（直接复用 / 保留逻辑换后端 / 重写）：

| 模块 | LOC | 复用 | 改造 | 重写 |
|---|---:|---:|---:|---:|
| 效果解析与代码生成 | 2,042 | 1,200 | 500 | 342 |
| 效果缓存 | 576 | 450 | 90 | 36 |
| 效果绘制 | 729 | 180 | 80 | 469 |
| 效果性能分析 | 369 | 120 | 60 | 189 |
| 渲染器 | 1,472 | 180 | 90 | 1,202 |
| 呈现器 | 793 | 0 | 40 | 753 |
| 帧源 | 1,401 | 60 | 120 | 1,221 |
| 设备与资源 | 2,246 | 120 | 200 | 1,926 |
| 窗口/DPI/源跟踪 | 4,562 | 60 | 150 | 4,352 |
| 光标 | 2,034 | 60 | 120 | 1,854 |
| 覆盖层/ImGui | 3,015 | 1,300 | 900 | 815 |
| 配置数据模型 | 380 | 330 | 40 | 10 |
| 运行时生命周期 | 292 | 60 | 40 | 192 |
| 本地化 | 128 | 10 | 20 | 98 |
| 截图 | 380 | 200 | 80 | 100 |
| AppX | 835 | 0 | 0 | 835 |
| 共享基础设施 | 2,294 | 1,982 | 143 | 169 |
| **合计（Core + 被引用的 Shared）** | **23,791** | **6,532（27.5%）** | **2,696（11.3%）** | **14,563（61.2%）** |

仅 `src/Magpie.Core` 的 21,497 行：复用 4,550（21.2%）、改造 2,553（11.9%）、重写 14,394（67.0%）。

解读与告警：
- LOC 比例会低估"重写"的真实成本：`Window/DPI` 的 4,352 行重写不是逐行翻译，而是按 Wayland 重新设计交互；反过来，`Presenter` 的 753 行重写可能比 `EffectCompiler` 的 342 行重写更简单（薄封装 vs 语义细节）。
- `覆盖层/ImGui` 的 43% 复用是"逻辑复用"，但输入/字体/输出适配仍是必做工作。
- 若把 `src/Magpie` 的 18,431 行 UI 也算进来，配置 UI 的 C++/WinRT + XAML 基本全部由 Flutter 重建；可保留的是数据模型、schema、Profile 匹配规则（需改写平台查询）、效果元数据展示逻辑。UI 侧没有 1:1 的 LOC 复用比例，按"功能点"评估更合适。

## 7. 关键风险（按影响排序）

### 7.1 Wayland 不提供窗口定位/枚举/全局输入，窗口模式缩放需要重新定义

`xdg_toplevel.set_fullscreen` 只接受"输出偏好"，最终是否全屏、放在哪个输出由合成器策略决定（[S7]）；客户端没有 `set_position`。因此：
- 现状 `ScalingWindow` 的"窗口模式缩放"（自动覆盖源窗口、拖动/缩放、边框辅助窗口、触控洞）无法按 Windows 语义实现。
- 现状 `ScalingRuntime` 的"跟随源窗口移动/最大化/最小化"依赖 `SrcTracker` + Win32 查询，必须删除或改为"覆盖层固定在全屏输出，源窗口由用户自行处理"。
- 现状"3D 游戏模式/模拟独占全屏"（`ExclModeHelper.cpp`）没有等价物；应明确标记为 Windows-only。
- 建议：票 #9 决定窗口模式的产品形态（普通可移动 toplevel？layer-shell 锚定？仅全屏？）。本盘点的结论是**不要把 `ScalingWindow` 的窗口几何逻辑当作可移植资产**。

### 7.2 portal 窗口流不提供源窗口身份，Profile 自动匹配不可行

`org.freedesktop.portal.ScreenCast` 的 `Start()` 返回 `streams`（node id + properties），v6 起不再推荐用 node id 定位流，推荐 `pipewire-serial`；`SelectSources` 支持 `types`（MONITOR/WINDOW/VIRTUAL）与 `cursor_mode`（Hidden/Embedded/Metadata）（[S1]）。KDE 后端在创建窗口流时只写入 `source_type=Window` 与 `pipewire-serial`，**不写入 appId/title/geometry**（`src/screencasting.cpp:160-169`，[S3]）；appId/title 只用于 restore 数据（`src/screencast.cpp:258-264`，[S3]）。
后果：
- 无法像 `ProfileService` 那样按 exe 路径/窗口类名自动选择 Profile（`src/Magpie/ProfileService.cpp:209-246`）。
- 无法知道源窗口的客户区/边框，`cropping`、`CaptureTitleBar`、"捕获标题栏"等选项需要重新定义。
- 可行路径：按 portal 选择结果绑定 Profile；用 `restore_token` 记忆同一源；或在配置 UI 中让用户为"上次选择的源"指定 Profile。票 #9/#12 需要确认这条降级路径。

### 7.3 帧传输与 Vulkan 导入的格式/同步不确定性

PipeWire 缓冲区可能是 `SPA_DATA_DmaBuf`、`SPA_DATA_MemFd` 或 `SPA_DATA_MemPtr`（[S8]）。dma_buf 路径需要：
- `VK_KHR_external_memory_fd`（`VkImportMemoryFdInfoKHR`）与 `VK_EXT_external_memory_dma_buf`（`VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT`），[S5]；
- DRM fourcc + modifier → `VkFormat`/`VkImageCreateInfo` 的映射；modifier 不是 LINEAR 时，需要 `VK_EXT_image_drm_format_modifier`（若走 dma_buf 零拷贝）；
- 同步：dma_buf 的 acquire fence 可映射到 `VK_KHR_external_semaphore_fd` 的 `SYNC_FD` 句柄；否则需要隐式同步 + 队列等待；
- 回退：MemFd/MemPtr 走 staging upload，CPU 拷贝会增加延迟与带宽，但能保证首版可用。
票 #2 应确认 KWin 实际输出的 buffer 类型/modifier；票 #11 应确认是否要求零拷贝。建议 `IFrameSource` 同时暴露 `TextureHandle` 与可选的 dma_buf 元数据，让上层按能力选择路径。

### 7.4 效果格式与 FP16：D3D11 上可用不等于 Vulkan 上可用

- 20 种中间格式（`EffectHelper.h:16-38`）中，`R11G11B10_FLOAT` 对应 `VK_FORMAT_B10G11R11_UFLOAT_PACK32`，而 Vulkan 的必需格式表对该格式没有无条件的 storage image 保证（[S6]）；其他格式虽多数有强制支持，仍应逐格式查询 `VkFormatProperties`，因为条件标记与驱动差异存在。
- DXC 对 `RWTexture2D<T>` 默认生成 Unknown image format，必须显式加 `[[vk::image_format("...")]]`，否则依赖 `shaderStorageImageWriteWithoutFormat`（以及读取时的 `shaderStorageImageReadWithoutFormat`）特性（[S4]）。
- FP16：`min16float` 默认编译为 32 位 + `RelaxedPrecision`；只有 `-enable-16bit-types` 才生成 16 位类型，且需要设备支持 `shaderFloat16`（[S4]）。Magpie 的 42 个声明 `CAPABILITY` 的内置效果全部包含 `CAPABILITY FP16`；若不启用真 16 位，Linux 版可能明显更慢。
- 建议：`IGraphicsDevice::QueryFormat` + `IEffectCompiler` 的能力协商；为每个效果生成"格式回退计划"；在 CI 中用 lavapipe/llvmpipe 与至少一种真实 GPU 跑 smoke test。

### 7.5 常量缓冲布局与绑定模型

现状 CPU 侧按 32 位字紧凑打包 `cbuffer __CB1`（`EffectDrawer.cpp:411-530`；HLSL 声明在 `EffectCompiler.cpp:1474-1500`）。Vulkan 默认的 std140/std430 布局与 D3D 的打包规则不同。两条路：
- 用 DXC `-fvk-use-dx-layout` 保持 D3D 布局，需启用 `VK_EXT_scalar_block_layout`（[S4]）；这是最小改动，推荐。
- 或者重写 CPU 打包为 std140（易错，所有效果参数都要回归）。
绑定方面，`register(bN/tN/uN/sN)` 可被 DXC 映射为 binding（[S4]），但要注意 `register(xX, spaceY)` 的 space 语义与 descriptor set 的映射；建议在生成的 HLSL 里显式加 `[[vk::binding(N, set)]]`，把映射规则固定下来，而不是依赖命令行 shift。
另：`cbuffer __CB2 : register(b1)` 只有 4 字节（`EffectCompiler.cpp:1152`），在 Vulkan 里用 UBO + 动态偏移或 push constant 均可；建议统一为 UBO，避免 push constant 的 128 字节限制。

### 7.6 双设备/Keyed Mutex 架构没有 Vulkan 等价物

`Renderer` 用两个 D3D11 设备 + NT 共享句柄 + `IDXGIKeyedMutex` 在生产者和消费者之间传递纹理（`Renderer.cpp:107-120`、`:774-805`）。Vulkan/Linux 没有 keyed mutex；`VK_KHR_win32_keyed_mutex` 只适用于 Windows 句柄（[S5]）。可选方案：
- 单 `VkDevice` + 两个队列（图形/计算或独立队列族）+ timeline semaphore；最简单，推荐 v1。
- 两个 `VkDevice` + dma_buf 导出/导入 + 外部 semaphore；只有在"必须隔离捕获与呈现的 GPU 优先级"时才需要。
无论哪种，`Renderer` 的线程模型与帧同步都要重写；`StepTimer` 的等待逻辑（`StepTimer.cpp:37-80`、`:100-120`）要改成基于 eventfd/`poll` 或 Wayland dispatch 的可中断等待。

### 7.7 全局热键的 UX 与权限

portal GlobalShortcuts 要求会话 + `BindShortcuts` 弹窗，用户可拒绝/改键；`Activated`/`Deactivated` 是信号（[S2]）。这带来三个产品约束：
- 首次使用时必须引导用户完成 portal 授权；
- 不能保证用户设置的键位就是实际绑定的键位，设置页要显示 portal 返回的 `trigger_description`；
- 某些组合键可能被合成器/桌面占用，注册会失败，UI 需要可恢复的错误路径。
KDE 后端包含该 portal 的实现（[S3]），但具体支持程度取决于 Plasma 版本；票 #6/#13 应把它列入最低版本要求。

### 7.8 字体、本地化、截图与光标的次级风险

- 字体：`Segoe UI`/`SegoeIcons.ttf`/`msyh.ttc` 等路径在 Linux 不存在（`OverlayDrawer.cpp:234-262`、`:360-380`）；需 fontconfig + 自带图标字体。ImGui 字体图集的度量会变化，覆盖层布局需要视觉回归。
- 本地化：`.resw`/`ResourceLoader`（`LocalizationService.cpp:78-87`）不能用于 Linux；Flutter 用 ARB（[S9]），原生覆盖层需要共享同一翻译目录生成的字符串表；否则两套翻译会漂移。
- 截图：WIC（`TextureHelper.cpp:12-82`）→ PNG/DDS 编码；`screenshotsDir` 的默认 `FOLDERID_Screenshots`（`Profile.h:97`）→ XDG Pictures；模板 token `%PN%`（进程名）在 Wayland 不可得（同 7.2）。
- 光标：`GetIconInfo`/`GetDIBits`/`magnification.dll`（`CursorDrawer.cpp:377-470`、`CursorManager.cpp:9`）全部 Windows-only；v1 用 portal `cursor_mode=Embedded` 删除整块，metadata 模式另立票据。
- 性能分析：D3D11 disjoint query → Vulkan timestamp query，`timestampPeriod`/可用性与校准不同；时间线 UI 可留，数据来源重写。
- 屏幕常亮：`SetThreadExecutionState`（`KeepScreenOnHelper.cpp:7-22`）→ logind `Inhibit`（[S10]）；"模拟独占全屏"（`ExclModeHelper.cpp`）删除。

## 8. 建议的抽取顺序

原则：先抽"没有 GPU/窗口也能测试"的部分，再抽"效果后端"，最后做"窗口/呈现/产品闭环"。每一阶段都应有可执行的验收，而不是"编译通过"。

### P0：建立平台无关核心库（无 GPU、无窗口）

1. 新建 `src/engine`（或 `src/core`）+ CMake；公共头文件禁止 Windows 类型。
2. 原样搬入：`SmallVector`、`ByteBuffer`、`Singleton`、`LruMemoryCache`、`MemoryCache`、`StepTimer`（去掉 Win32 等待）、`Event`（去掉 `winrt::auto_revoke_t` 重载）、`OverlayHelper` 的字形范围/颜色表、`EffectHelper` 的格式表（改为自有 `TextureFormat`）。
3. 搬入并改写：`StrHelper`（UTF-8/UTF-16 用 `std::` 或 utfcpp）、`Logger`（去掉 HRESULT/NTSTATUS）、`ScalingOptions`（回调改接口、`CaptureMethod` 改后端枚举）、`Profile`/`ScalingMode`（wstring→utf8）。
4. 把 `EffectCompiler` 拆成 `libmagpiefx`（parser + HLSL generator + `EffectDesc`）与 `IBytecodeCompiler`；先只实现"解析 + 生成源码"，不编译。
5. 验收：在 Linux 上解析全部 117 个内置效果，输出参数/纹理/通道元数据与 Windows 版一致（用 Windows 侧导出的 JSON 对照）；单元测试覆盖注释剥离、指令解析、输出尺寸表达式。

> 此阶段不需要 Vulkan、不需要 Wayland、不需要 portal。它同时为 Flutter 配置 UI 提供"效果元数据"能力（票 #3/#10）。

### P1：效果后端（DXC + SPIR-V + compute pipeline）

1. 实现 `DxcSpirvBackend`：`IDxcIncludeHandler`、`-T cs_6_0 -spirv`、`[[vk::image_format]]` 注入、`-fvk-use-dx-layout`、`-enable-16bit-types` 开关。
2. 实现 `IEffectPipeline`（Vulkan）：格式能力查询、纹理创建、descriptor set、compute pipeline、dispatch、pass 依赖规划。
3. 验收：117 个效果全部编译为 SPIR-V；在至少一种真实 GPU + lavapipe 上对每个效果跑一次 64×64 输入的 dispatch；与 Windows 版同输入同参数的输出做像素差异阈值比较（允许 FP 舍入）。
4. 产出：格式回退表、FP16 能力矩阵、DXC 版本/参数记录（供票 #4 使用）。

### P2：图形设备与呈现骨架

1. 实现 `VulkanDevice`：实例/物理设备/队列、`QueryFormat`、image/buffer/upload、timeline semaphore、descriptor cache。
2. 实现 `IPresenter` 的 `WaylandSwapchainPresenter`（先不接覆盖层，用离屏/简单 surface 验证）。
3. 验收：`VK_KHR_wayland_surface` 下创建 swapchain、清屏、present、resize；验证 present mode（FIFO/Mailbox）与帧率限制。
4. 此阶段可与 P3 并行，但 `IPresenter` 的接口要先定稿（票 #11）。

### P3：捕获（portal + PipeWire）

1. 实现 `ISourceSession`：D-Bus 调 `org.freedesktop.portal.ScreenCast`，CreateSession → SelectSources(WINDOW/MONITOR, cursor_mode) → Start → OpenPipeWireRemote；处理 restore_token（[S1]）。
2. 实现 `PortalPipeWireFrameSource`：连接 PipeWire 流，先走 MemFd/MemPtr，再实现 dma_buf 导入；实现重复帧检测（可先用 CPU 版本）。
3. 验收：选择窗口与显示器两种源；流尺寸/缩放正确；cursor_mode=Embedded 时光标出现在画面中；源关闭/恢复时状态机正确；无 dmabuf 时回退可用。
4. 产出：实际 buffer 类型/modifier/格式清单（供票 #2/#11）。

### P4：全屏覆盖层 + ImGui

1. 实现 `IOverlayWindow`：xdg-toplevel + `set_fullscreen(output)`（[S7]）；处理 configure/close/scale；pointer/keyboard/axis 事件。
2. 接入 `imgui_impl_vulkan`（[S11]）+ 自写 Wayland 平台后端；移植 `ImGuiImpl` 的窗口约束/Fitts 定律/鼠标位置逻辑；字体改 fontconfig + 自带图标字体。
3. 移植 `OverlayDrawer` 的工具栏/Profiler/字符串逻辑。
4. 验收：全屏覆盖层在目标输出上显示缩放结果；工具栏可点击/自动隐藏；Profiler 时间线数据来自 Vulkan timestamp；DPI 缩放与分数缩放不模糊。

### P5：产品闭环

1. `EngineRuntime`：启动/停止/切换窗口模式（若 #9 保留）、状态事件、截图、错误上报；用平台无关的事件队列替代 `DispatcherQueue`。
2. `IHotkeyService`：portal GlobalShortcuts；UI 显示 portal 返回的键位描述。
3. 配置：Flutter 写 `config.json`（schema 兼容）；引擎读取快照；效果元数据通过 `libmagpiefx` 的 C ABI/CLI 提供给 Flutter（票 #10 决定 FFI 还是 IPC）。
4. 日志/截图/本地化：XDG 目录、PNG/DDS 编码、原生字符串表。
5. 验收：从 Flutter 配置到引擎缩放再到覆盖层显示的端到端流程；退出/重启后配置与 restore_token 正确。

### P6：清理与可选能力

- 光标 Metadata 模式（若 #9 要求）、多显示器/分数缩放/HDR（票 #11）、性能调优、崩溃诊断。
- 删除 Linux 构建中的 Windows-only 文件；冻结树保留，不参与 Linux CI。

**关于"暂时保留 Windows 实现"**：不建议在 Linux 引擎里保留 D3D11 分支。正确做法是：
- `src/Magpie.Core` 原样冻结，作为行为 oracle（同效果、同输入、同参数的输出对照）；
- 把可移植文件抽到新库后，对 Windows 项目只做一次机械性的 include/project 引用调整，使其继续可构建（不再加功能）；
- 所有 Linux 专属实现只存在于新树，避免 `#ifdef _WIN32` 渗透到核心。

## 9. 对下游票据的输入

| 票据 | 本盘点要求它确认/决定的内容 |
|---|---|
| #2 捕获可行性 | KWin 实际输出的 buffer 类型（dma_buf/memfd/memptr）、modifier、格式、同步方式；窗口流是否只给 `source_type`（证据：是）；cursor_mode 默认值；restore_token 生命周期 |
| #3 Flutter 集成 | 效果元数据/配置 schema 的提供方式（`libmagpiefx` C ABI vs CLI vs IPC）；引擎状态/错误事件模型；`ScalingOptions` 快照的边界 |
| #4 SPIR-V 编译 | DXC 版本与参数；`[[vk::image_format]]` 注入规则；`-fvk-use-dx-layout` 与 `VK_EXT_scalar_block_layout` 的最低要求；FP16 策略；缓存键/版本 |
| #9 交互契约 | 窗口模式是否存在、覆盖层是全屏还是 layer-shell、Profile 自动匹配的降级方案、热键 portal 的 UX |
| #10 进程/通信 | 引擎与 Flutter 的进程模型；配置写入方；效果元数据通道；单实例与 restore_token 持久化 |
| #11 呈现/管线 | 单设备双队列 vs 双设备 dma_buf；present mode；直接扫描输出；帧率限制与延迟目标 |
| #12 配置兼容 | 旧 `config.json` schema 的迁移；Windows 专属字段（AppX、3D 游戏模式、触摸、独占全屏）的删除/忽略策略 |
| #13 打包/CI | Vulkan loader/headers、DXC、PipeWire、Wayland、portal 的最低版本；effects/fonts 的安装路径；oracle 构建是否保留 |

## 10. 参考来源

外部来源均为 2026-11-23 访问。

- [S1] xdg-desktop-portal, `org.freedesktop.portal.ScreenCast`（version 6）：会话流程、`SelectSources` 的 `types`/`cursor_mode`、`Start` 返回 PipeWire streams、v6 起 node id 弃用、restore_token。<https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html>
- [S2] xdg-desktop-portal, `org.freedesktop.portal.GlobalShortcuts`（version 2）：CreateSession、BindShortcuts、ListShortcuts、Activated/Deactivated。<https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html>
- [S3] KDE `xdg-desktop-portal-kde` 源码：`src/screencast.cpp`、`src/screencasting.cpp`、`src/globalshortcuts.cpp`。窗口流元数据只写 `source_type`（`screencasting.cpp` 约 160-169 行）；appId/title 仅用于 restore（`screencast.cpp` 约 258-264 行）。<https://github.com/KDE/xdg-desktop-portal-kde>
- [S4] Microsoft DirectXShaderCompiler, `docs/SPIR-V.rst`：`register()`→Vulkan binding、`[[vk::image_format]]`、`min16float` 与 `-enable-16bit-types`、`-fvk-use-dx-layout`（需 `VK_EXT_scalar_block_layout`）。<https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/SPIR-V.rst>
- [S5] Khronos Vulkan-Headers, `registry/vk.xml`：`VK_KHR_external_memory_fd`（number 75，`VkImportMemoryFdInfoKHR`/`vkGetMemoryFdKHR`）、`VK_EXT_external_memory_dma_buf`（number 126，`VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT`）、`VK_KHR_wayland_surface`（number 7）、`VK_KHR_external_semaphore_fd`（number 80）、`VK_EXT_image_drm_format_modifier`（number 159）、`VK_EXT_scalar_block_layout`（number 222）、`VK_KHR_win32_keyed_mutex`。<https://github.com/KhronosGroup/Vulkan-Headers/blob/main/registry/vk.xml>
- [S6] Khronos Vulkan-Docs, `chapters/formats.adoc`：`VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT` 定义与必需格式支持表；`B10G11R11_UFLOAT_PACK32` 行没有无条件的 storage image 标记；部分格式的 storage image 支持带有 `{sym3}` 条件（依赖 `shaderStorageImageExtendedFormats`）。<https://github.com/KhronosGroup/Vulkan-Docs/blob/main/chapters/formats.adoc>
- [S7] wayland-protocols, `stable/xdg-shell/xdg-shell.xml`：`xdg_toplevel.set_fullscreen` 的输出只是偏好，最终由合成器策略决定；客户端没有任意定位请求。<https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/xdg-shell/xdg-shell.xml>
- [S8] PipeWire, `spa/include/spa/buffer/buffer.h`：`SPA_DATA_MemPtr`、`SPA_DATA_MemFd`、`SPA_DATA_DmaBuf`。<https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/master/spa/include/spa/buffer/buffer.h>
- [S9] Flutter, "Internationalizing Flutter apps"（ARB/gen-l10n）。<https://docs.flutter.dev/ui/internationalization>
- [S10] systemd, `org.freedesktop.login1` D-Bus API，`Inhibit()`。<https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html>
- [S11] Dear ImGui v1.91.8, `backends/imgui_impl_vulkan.h`（与 `conanfile.txt` 的 `imgui/1.91.8` 对应）。<https://github.com/ocornut/imgui/blob/v1.91.8/backends/imgui_impl_vulkan.h>

本地证据（提交 `5833e431`）：
- `src/Magpie.Core/pch.h:1-62`（Windows/D3D11/WIL/C++WinRT/fmt 总头）
- `src/Magpie.Core/FrameSourceBase.h:20-93`、`FrameSourceBase.cpp:40-340`
- `src/Magpie.Core/PresenterBase.h:8-41`、`AdaptivePresenter.h:7-47`、`CompSwapchainPresenter.h:8-39`
- `src/Magpie.Core/DeviceResources.h:7-41`、`BackendDescriptorStore.h:6-33`、`DirectXHelper.cpp:13-110`、`TextureHelper.cpp:12-82,295-313`、`DDSHelper.cpp`、`DDS.h:257-290`
- `src/Magpie.Core/EffectCompiler.cpp:16,60-1600,1603-1860`、`include/EffectDesc.h:74,93-110`、`EffectHelper.h:16-38`
- `src/Magpie.Core/EffectDrawer.cpp:300-375,377-530,532-620`、`EffectDrawer.h:26-95`
- `src/Magpie.Core/Renderer.cpp:82-120,234-303,429-459,506-592,733-805,830-908,1007-1061,1146-1320`、`Renderer.h:104-148`
- `src/Magpie.Core/ScalingWindow.h:31,175-192`、`ScalingWindow.cpp:45-322,412-897`、`SrcTracker.h:30-98`、`SrcTracker.cpp`
- `src/Magpie.Core/Win32Helper.cpp`、`include/Win32Helper.h:10-241`、`include/BaseWindow.h:31-53`、`WindowHelper.cpp`、`KeepScreenOnHelper.cpp:7-22`、`ExclModeHelper.cpp:12-56`
- `src/Magpie.Core/CursorManager.cpp:1-9`、`CursorManager.h:28,60-121`、`CursorDrawer.cpp:377-470`
- `src/Magpie.Core/OverlayDrawer.cpp:234-262,360-380`、`ImGuiImpl.cpp:293-380`、`ImGuiBackend.cpp:222-251`、`ImGuiFontsCacheManager.cpp`
- `src/Magpie.Core/include/ScalingOptions.h:6-12,180-229`、`ScalingOptions.cpp:39-146`、`include/ScalingRuntime.h:6-50`、`ScalingRuntime.cpp`
- `src/Magpie.Core/LocalizationService.cpp:10-92`、`ScreenshotFilenameTemplateHelper.cpp`、`AppXReader.cpp:1-15`
- `src/Magpie/Profile.h:36-127`、`ScalingMode.h:6-23`、`AppSettings.cpp:511-880`、`ProfileService.cpp:209-246`、`ShortcutService.cpp:14-58`
- `src/Shared/SmallVector.h/.cpp`、`StrHelper.cpp:6-67`、`Logger.h:62-79`、`CommonDefines.h:14-16`、`CommonSharedConstants.h:5-45`
- `src/Effects`：117 个 `.hlsl`、105,390 行、17 个 `.dds`；`StubDefs.hlsli` 仅用于 IDE。
