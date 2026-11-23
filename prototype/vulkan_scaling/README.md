# 最小 Vulkan 缩放链路原型

> **PROTOTYPE — throwaway.** 这是 `prototype/vulkan-scaling` 分支上的可丢弃代码，
> 用于验证“portal 捕获 → Vulkan 计算缩放 → 全屏呈现”的最小链路。不要合并到
> `dev`。

对应票据：[最小 Vulkan 缩放链路原型](https://github.com/Qxy0happy/Magpie/issues/7)。

## 它验证什么

- `xdg-desktop-portal` ScreenCast 的 CreateSession → SelectSources →
  Start → OpenPipeWireRemote 流程。
- PipeWire 流以 MemFd/MemPtr 形式进入 CPU，再上传到 GPU。
- HLSL 经 DXC 编译为 SPIR-V；Compute shader 做 bicubic 缩放。
- SDL3 GPU 的 Vulkan 后端呈现；记录采集到 CPU 提交的延迟与帧率。
- `--dump` 把缩放结果写成 PPM，用于证明 compute 输出，不受合成器/截图影响。

## 构建

依赖：

- SDL3（`pkg-config sdl3`）
- libpipewire-0.3
- gio-2.0 / gio-unix-2.0
- Vulkan 驱动（AMD RADV / Intel ANV / NVIDIA 均可）
- DXC（默认 `/tmp/dxc/bin/dxc`；也可以用 `-DDXC_EXECUTABLE=...` 指定）

```bash
cd prototype/vulkan_scaling
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DDXC_EXECUTABLE=/tmp/dxc/bin/dxc
cmake --build build
```

如果 DXC 不在 `/tmp`，先安装 `directx-shader-compiler` 或从 DXC release 解压，
再把路径传给 CMake。构建会把 `bicubic.spv` 复制到可执行文件旁边。

## 运行

合成源（不弹 portal；用于验证 GPU/呈现/延迟）：

```bash
cd build
SDL_VIDEODRIVER=wayland ./magpie_vulkan_prototype \
  --source synthetic --windowed --seconds 5 \
  --dump /tmp/magpie-vk-frame.ppm
```

Portal 窗口捕获（会弹出 KDE 窗口选择器；**选一个持续重绘的窗口**）：

```bash
cd build
SDL_VIDEODRIVER=wayland ./magpie_vulkan_prototype \
  --source portal --windowed --log /tmp/magpie-window.log
```

Portal 显示器捕获（用于链路冒烟；选屏幕）：

```bash
cd build
SDL_VIDEODRIVER=wayland ./magpie_vulkan_prototype \
  --source portal --monitor --windowed --seconds 10 \
  --log /tmp/magpie-monitor.log \
  --dump /tmp/magpie-monitor.ppm --dump-frame 120
```

选项：

- `--source synthetic|portal`：帧源，默认 portal。
- `--monitor`：捕获整个显示器而不是单个窗口。
- `--windowed`：窗口模式；默认全屏。
- `--seconds N`：N 秒后自动退出（0 = 直到 ESC/关闭）。
- `--log PATH`：把 stdout/stderr 写到文件，便于 HITL 测试。
- `--dump PATH` / `--dump-frame N`：把第 N 帧写成 PPM；默认第 1 帧。portal
  选窗/选屏刚结束时第一帧可能是黑的或包含选择器，建议 N=120。

## 已验证（KWin 6.8.3 / Wayland / Radeon 780M / RADV）

- DXC 把 `shaders/bicubic.hlsl` 编译为 SPIR-V 1.0，`spirv-val` 通过。
- SDL3 GPU 报告 `driver=vulkan`；compute + blit 呈现可用。
- 合成源 640×360 → 1280×720：约 **155–159 fps**，采集到提交约 **6.3–6.5 ms**。
- Portal 显示器捕获 1920×1080：约 **57 fps**，采集到提交约 **2.38 ms**（281 帧）。
- Portal 显示器捕获 3840×2160：约 **45.9 fps**，采集到提交约 **25.58 ms**（64 帧，测试超时提前结束）。
- `--dump` 输出可证明 compute 结果是单一连续的缩放画面；Spectacle 截图出现的
  左右分区是 SDL3 Wayland 呈现/截图路径的异常，不是 compute 输出。

### 窗口捕获的关键发现

KWin 的窗口 screencast 是 **damage-driven**：只有源窗口重绘时才发帧。第一次
选择静态 Brave 页面时，PipeWire 流已连接（`kwin-screencast-brave-browser`，
3840×2160 BGRA），但 `pw-top` 的 RATE/QUANT 为 0，应用收不到帧，窗口保持空白。
这是产品层必须处理的失败模式：覆盖层应显示“等待源窗口更新”，而不是假装在
缩放一个持续更新的画面。选择正在播放视频/游戏/滚动的窗口即可产生帧。

## 已知限制 / 下一步

- **不是 raw Vulkan WSI**：SDL3 GPU 在 Linux 使用 Vulkan 后端，但呈现层是普通
  `xdg_toplevel`，没有 `wlr-layer-shell` overlay。真正的置顶/覆盖层仍需按 KWin
  研究报告的 layer-shell + `VK_KHR_wayland_surface` 路径验证。
- **没有 dmabuf**：当前请求 MemFd/MemPtr 并 CPU 上传，避开了 dmabuf 导入与
  同步这一最高风险项。下一步应验证 `SPA_DATA_DmaBuf` + `VK_EXT_external_memory_dma_buf`
  + implicit sync。
- **GPU 时间未测**：只记录采集到 CPU 提交的延迟；SDL3 GPU 不暴露 compute
  timestamp。raw Vulkan + timestamp query 才能给出 GPU 时间。
- **截图/合成异常**：Spectacle 截图出现分区；`--dump` 正常。需在 raw Vulkan
  或 layer-shell 路径上复验；也可能是当前 KWin/HDR/scale 组合的合成器问题。
- **portal 应用名**：没有安装 `.desktop` 时，KDE 选择器可能把调用者显示为
  “Term”。不影响选择窗口。
- **8-bit SDR**：与 KWin 6.8 的窗口流一致；没有 HDR/10-bit。
- 没有音频、光标 metadata、多显示器选择、热键、托盘或产品级 UI。

## 文件

- `src/portal_capture.*`：ScreenCast portal + PipeWire，输出 `Frame`。
- `src/renderer.*`：SDL3 GPU（Vulkan 后端）上传、compute、blit、可选 dump。
- `src/synthetic_source.h`：合成测试源。
- `shaders/bicubic.hlsl`：DXC 编译的 bicubic compute shader。
- `src/frame.h`：捕获/渲染共享的帧模型。
