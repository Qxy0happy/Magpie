# Ticket #4：MagpieFX/HLSL 到 Vulkan SPIR-V 的编译与特性支持矩阵

- 任务：判定能否保留 MagpieFX 源格式，用 DXC 编译为 SPIR-V，并给出支持矩阵、内置效果兼容性抽样与推荐方案。
- 日期：2026-11-23（所有网络来源均为当日访问）
- 结论性质：决策级结论，附可复现的实测命令与结果。
- 相关代码（本地仓库，未修改）：`src/Magpie.Core/EffectCompiler.cpp`、`src/Magpie.Core/EffectDrawer.cpp`、`src/Magpie.Core/EffectCacheManager.cpp`、`src/Magpie.Core/include/EffectDesc.h`、`src/Magpie.Core/EffectHelper.h`、`docs/MagpieFX.md`、`src/Effects/**`

---

## 0. 结论摘要

**可行，而且不需要改动任何效果源文件。** MagpieFX 的 HLSL 计算着色器（SM5 风格源码）由 DXC 1.9 的 SPIR-V 后端编译，抽样 22 个内置效果的全部 56 个 pass 在 FP32 与 FP16 两种宏配置下 **56/56 编译成功并通过 `spirv-val`**。

需要改的只有 Magpie 自己的代码生成器与运行时，共三类：

| # | 问题 | 证据 | 修法（已实测） |
|---|------|------|----------------|
| A | `register(t0/u0/s0/b0)` 的寄存器类型被 DXC 忽略，全部落到 `set 0, binding 0`，同一 pass 内冲突 | `spirv-dis`：`%INPUT/%OUTPUT/%sam/%__CB1` 均为 `Binding 0` | codegen 写 `register(t0, space1)` 等，得到 4 个 descriptor set；或用 `-fvk-{b,t,u,s}-shift`；或用 `[[vk::binding(n,set)]]` |
| B | HLSL 的 `unorm`/`snorm` 修饰符在 SPIR-V 后端被**静默丢弃**（`RWTexture2D<unorm float4>` → `Rgba32f`） | `OpTypeImage %float 2D 2 0 0 2 Rgba32f` | codegen 对 UNORM/SNORM UAV 追加 `[[vk::image_format("rgba16")]]` 等，且 texel 类型写 32 位 `float4` |
| C | DXC 1.9 默认 HLSL 语言版本已进入 202x，`Jinc.hlsl` 的向量三元表达式被拒绝；`fxc(cs_5_0)` 接受 | `error: condition for short-circuiting ternary operator must be scalar` | 编译参数固定 `-HV 2018`（实测 2016/2018 通过，2021/默认失败） |

**FP16 无法真正保留**：`min16float` 在 SPIR-V 后端映射为 32 位 `OpTypeFloat 32` + `RelaxedPrecision`（`CAPABILITY FP16` 只影响纹理格式推断），而 `-enable-16bit-types` 下图像采样类型必须 ≥32 位（DXC 明确报错）。因此 FP16 效果在 Vulkan 上退化为 FP32 运算，功能等价、性能收益丢失（见 §6.3）。

**推荐方案**：运行时链接 `libdxcompiler.so`（31.8 MB，仅依赖 libz/libm/libstdc++），沿用现有"源码哈希 → 磁盘缓存"机制（把 `ID3DBlob` 换成 SPIR-V 字节向量）；内置效果首次加载一次性编译并缓存，不采用"预编译 SPIR-V 分发"（会破坏用户可编辑效果的能力），也不采用 HLSL→WGSL/GLSL 转译（无收益且更不可靠，§7.3）。

---

## 1. 验证环境

### 1.1 主机与 GPU（实测）

| 项 | 值 |
|----|----|
| Vulkan instance/loader | 1.4.363 |
| GPU 0 | AMD Radeon 780M Graphics (RADV PHOENIX)，Mesa 26.3.1-arch3.5，apiVersion 1.4.363 |
| GPU 1 | NVIDIA GeForce RTX 4060 Laptop GPU，驱动 620.73.04，apiVersion 1.4.357 |

两块 GPU 均为 Vulkan 1.3+，均为 Plasma/KWin 上现实可行的目标硬件（iGPU + dGPU 双显卡笔记本）。

### 1.2 工具链

系统内**没有** `dxc`（`which dxc` 为空；`pacman -Q` 中无 directx-shader-compiler 相关包），因此未安装任何系统包，改用 DXC 官方便携 release 解压到 `/tmp` 做验证；这一步是 §2 全部实测结论的来源。

| 工具 | 版本 | 位置 |
|------|------|------|
| dxc / libdxcompiler.so | `1.9(5512-01b62ad4)(1.9.2609.5)` | `/tmp/dxc/bin/dxc`（来自 `linux_dxc_2026_09_28.x86_x64.tar.gz`，release v1.9.2609） |
| glslangValidator | 11:16.6.0（`glslang` 1:1.4.363.0-1.1） | `/usr/bin` |
| glslc (shaderc) | 2026.4 | `/usr/bin` |
| spirv-val / spirv-dis / spirv-opt | 1.4.363.0 | `/usr/bin` |
| vulkaninfo | 1.4.363 | `/usr/bin` |

来源：[DXC release v1.9.2609](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.9.2609)（访问 2026-11-23）。

### 1.3 方法

`EffectCompiler.cpp` 的产物是"拼接出来的 HLSL 文本 + `D3DCompile(..., "cs_5_0")`"。为了得到可信的编译结论，我按 `CompilePasses()` / `CreatePassCode()` 的生成规则重写了一个等价的 HLSL 生成器（`/tmp/vkq/gen.py`，约 300 行），逐 pass 生成与 Magpie 当前输出结构一致的源码（cbuffer `__CB1`、`Texture2D<MF4>` SRV、`RWTexture2D<MF4>` UAV、`SamplerState`、`MP_*`/`MF*` 宏、`Rmp8x8`/`GetInputSize` 等内置函数、MulAdd 重载、PS-style 与 block-style 两种入口包装），再用 DXC 编译并 `spirv-val` 校验。

生成器的正确性以两点自证：(1) 对 `Bicubic.hlsl` 的生成结果与仓库中的 `docs/MagpieFX.md` 语义及 `EffectCompiler.cpp` 模板逐项对照；(2) 支持与不支持的分界（`-HV`、绑定冲突、`unorm`）与手工构造的最小用例完全一致（§3、§4）。

复现命令（以 Anime4K 为例）：

```bash
python3 /tmp/vkq/gen.py src/Effects/Anime4K/Anime4K_Restore_M.hlsl out --vk --fp16
/tmp/dxc/bin/dxc -T cs_6_0 -E __M -spirv -fspv-target-env=vulkan1.3 \
    -fvk-use-dx-layout -HV 2018 -I src/Effects -Fo out/Anime4K_Restore_M.p2.spv out/Anime4K_Restore_M.p2.hlsl
spirv-val --target-env vulkan1.3 out/Anime4K_Restore_M.p2.spv
```

---

## 2. DXC SPIR-V 后端支持矩阵

实测基线：`-T cs_6_0 … cs_6_9` 全部被接受（说明 profile 层面的门禁不存在）；真实差异在特性映射上，逐项如下。"验证"列全部是本机实测，不是文档推断。

### 2.1 结构特性

| 特性 | DXC `-spirv` 行为 | 验证 | MagpieFX 是否需要 | 迁移影响 |
|------|-------------------|------|------------------|----------|
| 计算着色器入口 | `OpEntryPoint GLCompute` + `OpExecutionMode LocalSize`，`[numthreads(64,1,1)]` → `LocalSize 64 1 1` | Bicubic 复刻源码：`OpExecutionMode %__M LocalSize 64 1 1` | 是（全部 pass） | 无 |
| 多通道（PASS 1..N） | 每个 pass 编译为独立模块，运行时顺序 dispatch | 22 个效果共 56 个模块，全部 `spirv-val` 通过 | 是 | 无（`EffectDrawer::Draw` 的循环结构可保留） |
| 多渲染目标（一个 pass 多个 OUT） | 每个 `RWTexture2D` 独立 `OpVariable`/绑定，与 attachment 无关 | FSRCNNX pass1（`OUT featureMap1, featureMap2`）编译通过 | 是（29 个效果文件、160 个 pass 使用多 OUT） | 无 |
| `groupshared` | → `Workgroup` 存储类静态数组 | Ani4Kv2 p2/p7 = 12,800 B；FSRCNNX p1 = 4,032 B；**全库最大 18,496 B**（NIS p1） | 是（Ani4Kv2、FSRCNNX、NIS） | 无：48 KiB（NVIDIA）/64 KiB（AMD）> 18.5 KiB |
| 原子操作 | `InterlockedAdd` → `OpAtomicIAdd`，共享内存用 `Workgroup` 作用域 + `OpControlBarrier` | 最小用例：`OpAtomicIAdd … %uint_2 %uint_0`、`OpControlBarrier` | 当前 0 处使用（全库 grep `Interlocked` = 0） | 无风险 |
| 线程组规模 | `NUM_THREADS 64` / `32,8` / `256` / `8,8` 均通过；两块 GPU `maxComputeWorkGroupInvocations=1024` | 56/56 编译通过 | 是（最大 256） | 无 |
| PS-style 包装（`STYLE PS`） | 64 线程、`Rmp8x8` swizzle、`Load`+`SampleLevel` 混用均正常 | Bicubic / FSR_RCAS / Lanczos / Jinc / SGSR / CRT 等 | 是 | 无 |
| `SamplerState`（分离采样器） | → 独立 `OpTypeSampler` 描述符（**非** combined image sampler） | Bicubic 模块内 `%sam` 与 `%INPUT` 是两个变量 | 是 | 描述符布局需要 `SAMPLED_IMAGE` + `SAMPLER` 两种类型 |
| cbuffer / `ConstantBuffer` | → `Uniform` 存储类 + `Block` 装饰（即 `UNIFORM_BUFFER`） | `OpTypePointer Uniform %type___CB1`、`OpDecoration Block` | 是（`__CB1`、`__CB2`） | 见 §5 |
| push constant | `[[vk::push_constant]] ConstantBuffer<T>` → `PushConstant` 存储类 | 最小用例 `OpVariable … PushConstant`，`Offset 0/4/8` | 可选优化 | 两块 GPU `maxPushConstantsSize = 256` |
| `[[vk::image_format("…")]]` | 支持 20+ 种 token；**未知 token 被静默忽略并回落到 `Unknown`**（不报错） | `rgba16`→`Rgba16`、`rgba16snorm`→`Rgba16Snorm`、`rgb10a2`→`Rgb10A2`、`r11g11b10f`→`R11fG11fB10f`、`rgba16unorm`→`Unknown`（无效 token） | 需要（§4） | 必须用**规范里的 token 名**，拼错不会报错 |
| `-fspv-debug` / `-Zi -Od` | 可用：`OpLine`/`OpString` 输出 | `-Od -Zi -fspv-debug=line` 生成含 `OpLine` 的模块 | 对应 `MP_DEBUG`/Debug 构建 | 需要单独一条 debug 编译路径 |
| `-fspv-target-env` | `vulkan1.0→SPIR-V 1.0`、`1.1→1.3`、`1.2→1.5`、`1.3→1.6` | 四档实测 | 决定最低 Vulkan 版本 | 见 §2.4 |

线程组与块大小的实际分布（全库 `src/Effects/**/*.hlsl` 指令统计，用于判断风险面）：

| 指令 | 出现次数 | 备注 |
|------|----------|------|
| `NUM_THREADS 64` | 252 | 主流：PS-style 与 `BLOCK_SIZE 8/16` 搭配 |
| `BLOCK_SIZE 8` | 161 | 8×8 块 + 64 线程（PS-style 四点/每线程 1 像素两种） |
| `BLOCK_SIZE 16` | 94 | 16×16 块 + 64 线程（每线程 4 像素） |
| `NUM_THREADS 32, 8` | 52 | NNEDI3 / FSRCNNX 类（`BLOCK_SIZE 32,16` / `64,8`） |
| `BLOCK_SIZE 96,24` / `64,16` / `48` / `40` | 6+12+1+1 | 非 2 的幂 → 走 `gid.xy * uint2(bw,bh)` 分支，实测通过 |
| `NUM_THREADS 256` / `128` / `8,8` | 2 / 2 / 7 | 全部 ≤1024 上限 |

→ 结论：MagpieFX 的块/线程配置全部落在 Vulkan 的强制下限内（每工作组 ≤1024 线程、组内共享内存 ≤48 KiB），无需为线程组模型做任何改写；`8x8 线程组 + 8/16 像素块`这一主流组合在 SPIR-V 里就是 `LocalSize 64 1 1` + `gl_WorkGroupID` 位移，语义一一对应。

来源：[SPIR-V.rst（HLSL→SPIR-V 特性映射手册）](https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/SPIR-V.rst)（访问 2026-11-23）——类型映射表、纹理类型表、`vk::image_format` 对照表、wave intrinsic 表、`-fvk-*` 选项表均出自此文档；实际操作以本机 DXC 1.9 实测为准（文档中 `-fspv-target-env` 只列到 vulkan1.1，已落后于实现）。

### 2.2 数值类型与 FP16（关键）

| HLSL 写法 | DXC 默认 | `-enable-16bit-types` | 结论 |
|-----------|----------|------------------------|------|
| `half` / `min16float` / `MF` | `OpTypeFloat 32` + `RelaxedPrecision` | `OpTypeFloat 16`（`Float16`） | Magpie 的 `MF*` 宏正是 `min16float*` |
| `float16_t` 用于 `RWStructuredBuffer`/`groupshared` | — | 通过：`Float16` + `StorageBuffer16BitAccess` + `SPV_KHR_16bit_storage` | 可在 buffer 中用真 16 位 |
| `float16_t`/`min16float4` 用于 `Texture2D`/`RWTexture2D` | 通过（32 位 float + 格式按类型名推断） | **报错**：`The sampled type for textures cannot be a floating point type smaller than 32-bits when targeting a Vulkan environment.` | **图像边界不可能有真 16 位采样类型** |
| `RWTexture2D<min16float4>`（无属性） | 推断格式 `Rgba16f` | — | 这正是 Magpie `R16G16B16A16_FLOAT` 中间纹理想要的 |
| `[[vk::image_format("rgba16f")]] RWTexture2D<min16float4>` | **报错** `The image format and the sampled type are not compatible.` | — | 属性路径比推断路径更严格；FP16 模式下不要对 float 格式写显式属性 |
| `RWTexture2D<unorm float4>` | 编译通过但格式为 `Rgba32f`（`unorm` 被丢弃） | — | 必须显式指定 `rgba16` 等（§4） |

实测命令与结果（`/tmp/vkq/shaders/fp16.hlsl`、`f16combo.hlsl`）：

```
# 默认（无 -enable-16bit-types）
%type_2d_image_0 = OpTypeImage %float 2D 2 0 0 2 Rgba16f      ; RWTexture2D<min16float4>
OpDecorate %Out RelaxedPrecision

# 加 -enable-16bit-types
error: The sampled type for textures cannot be a floating point type smaller than 32-bits …
```

→ **迁移结论**：`CAPABILITY FP16` 保留为"格式提示"（选中 `R16G16B16A16_FLOAT` 中间纹理、`min16float4` 声明），但算术会退化为 FP32。真实 FP16 只在"中间 buffer/groupshared"上部分可得，需要把 `MF*` 映射为 `float16_t` 并在图像读写处转换，收益未知（见 §9 未决问题）。

### 2.3 波前内建与派生量（当前未使用，但需登记）

| 内建 | SPIR-V | 实测 |
|------|--------|------|
| `WaveActiveSum/Product/Min/Max`、`WaveActiveCountBits` | `OpGroupNonUniformIAdd/FAdd… Reduce` | 通过 |
| `WavePrefixSum` | `OpGroupNonUniformIAdd … ExclusiveScan` | 通过（语义正确） |
| `WaveReadLaneAt` / `WaveReadLaneFirst` | `OpGroupNonUniformBroadcast/BroadcastFirst` | 通过 |
| `WaveActiveAllTrue/AnyTrue/Ballot` | `OpGroupNonUniformAll/Any/Ballot` | 通过 |
| `QuadReadAcrossX/Y/Diagonal`、`QuadReadLaneAt` | `OpGroupNonUniformQuadSwap/QuadBroadcast` | 通过，但**附带** `OpCapability ComputeDerivativeGroupLinearKHR` + `OpExtension "SPV_KHR_compute_shader_derivatives"` |
| 目标环境 | wave 操作要求 `-fspv-target-env>=vulkan1.1` | `vulkan1.0` 下直接报错 `Vulkan 1.1 is required for Wave Operation but not permitted to use` |

- `VK_KHR_compute_shader_derivatives` 在两块测试 GPU 上均存在（`vulkaninfo`：`VK_KHR_compute_shader_derivatives : extension revision 1`），因此 Quad 操作的第一道门槛通过；但它不是 Vulkan 1.3 核心，属于额外设备扩展。
- Magpie 内置效果**当前零处使用** wave/quad/derivative 内建（全库 grep：`Wave*` 0 处、`Interlocked*` 0 处、`ddx/ddy` 0 处）。因此可以先把这些特性标记为"支持但不承诺"，不阻塞迁移。

来源：[SPIR-V.rst § "Shader Model 6.0+ Wave Intrinsics"](https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/SPIR-V.rst)；[VK_KHR_compute_shader_derivatives](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/appendices/VK_KHR_compute_shader_derivatives.adoc)（访问 2026-11-23）。

### 2.4 目标环境与最低 Vulkan 版本

| `-fspv-target-env` | 产出 SPIR-V | 最低 Vulkan | 备注 |
|--------------------|-------------|-------------|------|
| `vulkan1.0` | 1.0 | 1.0 | wave/quad 不可用 |
| `vulkan1.1` | 1.3 | 1.1 | wave 可用 |
| `vulkan1.2` | 1.5 | 1.2 | |
| `vulkan1.3` | **1.6** | 1.3 | 推荐（引擎本身用 Vulkan 1.3 特性，如 `VK_EXT_descriptor_buffer` 可选） |

### 2.5 DXC 明确不支持的 HLSL 特性（与 MagpieFX 的交集）

来自 [SPIR-V.rst § "Unsupported HLSL Features"](https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/SPIR-V.rst)（访问 2026-11-23），并核对本地效果源码：

| 不支持项 | MagpieFX 是否使用 | 影响 |
|----------|------------------|------|
| `tex2D`/`tex1D` 等已废弃 intrinsic | 否 | 无 |
| `abort()`、`GetRenderTargetSampleCount/Position` | 否 | 无 |
| `.GatherCmpGreen/Blue/Alpha()` | 否（只用 `.Gather()`，260 处，全部通过） | 无 |
| 结构化缓冲 `Load*` 的 `status` 出参 | 否 | 无 |
| 独立矩阵上的 `row_major/column_major` | 否（MulAdd 用 `_m00_m01` swizzle，属于矩阵成员访问，正常） | 无 |
| cbuffer 成员初始化器 | 否 | 无 |
| **HLSL 202x 语义变化**（向量三元、`[unroll(N)]` 语义） | **是**：`Jinc.hlsl` 的 `(x == float4(0,0,0,0)) ? … : …` | 用 `-HV 2018` 解决（实测），见 §3.4 |

---

## 3. 资源绑定与描述符布局

### 3.1 现状（D3D11）与 DXC 的默认映射

`EffectCompiler::CreatePassCode()` 生成的声明是：

```hlsl
cbuffer __CB1 : register(b0) { … };
Texture2D<MF4>   INPUT  : register(t0);
RWTexture2D<MF4> OUTPUT : register(u0);
SamplerState     sam    : register(s0);
```

DXC 默认把 `register(xN)` 映射为 `binding N`，**忽略寄存器类型**（文档原话："Note that register type `x` is ignored, so this may cause overlap"）。实测（`Anime4K_Restore_M.p4`，去掉所有 `[[vk::…]]`）：

```
%__CB1 Binding 0   ← b0
%tex3  Binding 0   ← t0
%sam   Binding 0   ← s0
%tex4  Binding 1   ← u0
```

同一 descriptor set 内重复 binding 01 在 Vulkan 上是非法布局（`VkDescriptorSetLayout` 不允许重复 binding），因此现方案**必须**做改动。注意这不是"某个效果写错了"，而是 100% 的 pass 都会冲突。

### 3.2 三种可选修法（全部实测）

| 方案 | codegen 改动 | 实测结果 | 评价 |
|------|--------------|----------|------|
| A. `register(t0, space1)` / `u→space2` / `s→space3` / `b→space0` | 只在声明里加 `, spaceN` 字符串 | `%In DescriptorSet 1 Binding 0`、`%Out DescriptorSet 2 Binding 0`、`%smp DescriptorSet 3 Binding 0`、`%CB DescriptorSet 0 Binding 0` | **推荐**：4 个 set 与资源种类一一对应，布局由 MagpieFX 声明静态决定，无需反射；每个 pass 只需为"本 pass 实际用到的 set"建布局 |
| B. `-fvk-t-shift 1000 0 -fvk-u-shift 2000 0 -fvk-s-shift 3000 0` | 零（只改命令行） | `Binding 0 / 1000 / 2000 / 3000`，同一 set 0 | 备选：作为"不改生成文本"的兜底；缺点是同 set 内编号稀疏、可读性差 |
| C. `[[vk::binding(n, set)]]` 逐资源 | 需要在每个声明前插属性 | `%INPUT Binding 0`、`%OUTPUT Binding 1`、`%sam Binding 2` | 可用，但把布局知识分散到属性里，不如 A 集中 |

补充：`-fvk-shift` 的语义是"同时指定 descriptor set 与 binding 偏移"（`-fvk-t-shift N M` → set `M`、binding `X+N`），因此方案 B 实际也能通过 4 个不同 `M` 达到与 A 等价的效果。

### 3.3 反射：不需要

`grep -rn "D3DReflect|ShaderReflection" src/` 在 Magpie 中**零命中**。`EffectDrawer::_UpdatePassResources()` 直接用 `passDesc.inputs[i]` / `passDesc.outputs[i]` 的索引绑定 SRV/UAV，采样器按 `desc.samplers` 顺序绑定。也就是说描述符布局完全由 MagpieFX 声明在编译期决定 —— 这正是 Vulkan 里想要的形态：`EffectPassDesc::inputs/outputs` 已经够用来生成 `VkDescriptorSetLayout`。

→ `-fspv-reflect` 只是可选的额外校验手段（实测会写入 `UserSemantic` 装饰），不必作为运行时依赖。

### 3.4 语言版本门禁（必须固定）

| 效果 | 默认（1.9） | `-HV 2018` | 说明 |
|------|-------------|------------|------|
| `Jinc.hlsl`（向量三元） | 失败 | 通过 | `error: condition for short-circuiting ternary operator must be scalar, for non-scalar types use 'select'` |
| 其余 21 个抽样效果 | 通过 | 通过 | — |

→ 迁移时必须显式传 `-HV 2018`，否则用户提供的旧效果（按 fxc/cs_5_0 语义书写）会在升级 DXC 后随机失效。这是**版本固定策略**的一部分，不是一次性修复。

---

## 4. 纹理格式映射与存储图像可用性

### 4.1 DXGI → VkFormat → `vk::image_format` token（本地 `EffectHelper::FORMAT_DESCS` 全集 + 实测 token）

| MagpieFX `FORMAT` | DXGI | VkFormat | SRV texel | UAV texel | 需写的 `[[vk::image_format]]` | STORAGE_IMAGE（AMD 780M） | STORAGE_IMAGE（RTX 4060） |
|---|---|---|---|---|---|---|---|
| `R32G32B32A32_FLOAT` | R32G32B32A32_FLOAT | `R32G32B32A32_SFLOAT` | float4 | float4 | `rgba32f` | yes | yes |
| `R16G16B16A16_FLOAT` | R16G16B16A16_FLOAT | `R16G16B16A16_SFLOAT` | MF4 | MF4 | 无（`min16float4` 自动推断 `Rgba16f`）/`rgba16f`（FP32 模式） | yes | yes |
| `R16G16B16A16_UNORM` | … | `R16G16B16A16_UNORM` | MF4 | **float4** | `rgba16` | yes | yes |
| `R16G16B16A16_SNORM` | … | `R16G16B16A16_SNORM` | MF4 | **float4** | `rgba16snorm` | yes | yes |
| `R32G32_FLOAT` | … | `R32G32_SFLOAT` | float2 | float2 | `rg32f` | yes | yes |
| `R10G10B10A2_UNORM` | … | `A2B10G10R10_UNORM_PACK32` | MF4 | **float4** | `rgb10a2` | yes | yes |
| `R11G11B10_FLOAT` | … | `B10G11R11_UFLOAT_PACK32` | MF3 | MF3 | `r11g11b10f` | yes | yes |
| `R8G8B8A8_UNORM` | … | `R8G8B8A8_UNORM` | MF4 | **float4** | `rgba8` | yes | yes |
| `R8G8B8A8_SNORM` | … | `R8G8B8A8_SNORM` | MF4 | **float4** | `rgba8snorm` | yes | yes |
| `R16G16_FLOAT` | … | `R16G16_SFLOAT` | MF2 | MF2 | `rg16f` | yes | yes |
| `R16G16_UNORM` / `_SNORM` | … | `R16G16_UNORM`/`_SNORM` | MF2 | **float2** | `rg16` / `rg16snorm` | yes | yes |
| `R32_FLOAT` | … | `R32_SFLOAT` | float | float | `r32f` | yes | yes |
| `R8G8_UNORM` / `_SNORM` | … | `R8G8_UNORM`/`_SNORM` | MF2 | **float2** | `rg8` / `rg8snorm` | yes | yes |
| `R16_FLOAT` | … | `R16_SFLOAT` | MF | MF | `r16f` | yes | yes |
| `R16_UNORM` / `_SNORM` | … | `R16_UNORM`/`_SNORM` | MF | **float** | `r16` / `r16snorm` | yes | yes |
| `R8_UNORM` / `_SNORM` | … | `R8_UNORM`/`_SNORM` | MF | **float** | `r8` / `r8snorm` | yes | yes |

要点：

1. **UNORM/SNORM UAV 的语义可以完整保留**：Vulkan 的 UNORM/SNORM 图像视图在写入时自动做定点转换，等价于 D3D 的 `unorm float4` UAV。做法是 texel 类型写 32 位 `float4`（不能用 `min16float4`，见 §2.2）+ `[[vk::image_format("rgba16")]]`。实测：`[[vk::image_format("rgba16")]] RWTexture2D<float4>` 与 `min16float4` 算术共存无冲突。
2. `unorm`/`snorm` 修饰符本身对 SPIR-V 后端**无效**（静默丢弃），因此不能依赖它。
3. token 拼错会被静默忽略并回落到 `Unknown`（`rgba16unorm` → `Unknown`），必须在 codegen 里用常量表、并可选地加一条 `spirv-val` 冒烟检查。
4. `Unknown` 格式的存储图像读写需要 `shaderStorageImageWriteWithoutFormat` / `ReadWithoutFormat` 特性（两块 GPU 均为 `true`），但既然我们能指定具体格式，就不应该落到 `Unknown`。

### 4.2 规范层面的可用性边界

Vulkan 规范只对部分格式**无条件**强制要求 `STORAGE_IMAGE` 支持：

- `R32G32B32A32_SFLOAT`、`R16G16B16A16_SFLOAT`、`R8G8B8A8_UNORM`、`A2B10G10R10_UNORM_PACK32`、`R32_SFLOAT`：无条件（表中为强制标记）。
- `R16G16B16A16_UNORM`、`R16G16_UNORM`、`R16_UNORM` 等 16 位 UNORM/SNORM：**仅在设备支持 `shaderStorageImageExtendedFormats` 特性时才强制**（表中标注 `{sym3}`，表注原文："Format features marked with … must be supported for `optimalTilingFeatures` if the `VkPhysicalDevice` supports the `shaderStorageImageExtendedFormats` feature"）。
- 线性过滤（`SAMPLED_IMAGE_FILTER_LINEAR`）对 `R16G16B16A16_SFLOAT` 是强制的，因此 FP16 中间纹理的 LINEAR 采样无风险。

来源：[Vulkan-Docs `chapters/formats.adoc`（Formats 章，含各 Mandatory Format Support 表）](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/chapters/formats.adoc)，[Vulkan 规范 Formats 章](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#formats)（访问 2026-11-23）。

→ 工程含义：运行时应在初始化时用 `vkGetPhysicalDeviceFormatProperties` 检查所有会用到的中间格式的 `STORAGE_IMAGE` 位（代码里已有 `FORMAT_DESCS` 表，加一列即可）；不支持时回退到 `R16G16B16A16_SFLOAT`（语义近似，非精确 UNORM 量化）。

### 4.3 实测脚本

```bash
gcc -O1 -o /tmp/vkq/q2 /tmp/vkq/q2.c -lvulkan && /tmp/vkq/q2
```

输出（节选，两块 GPU 全 20 种格式 `STORAGE=yes / SAMPLED=yes / TRANSFER_DST=yes`）：

```
=== AMD Radeon 780M Graphics (RADV PHOENIX) ===
R16G16B16A16_SFLOAT            yes       yes       yes
R16G16B16A16_UNORM             yes       yes       yes
...
=== NVIDIA GeForce RTX 4060 Laptop GPU ===
（同上，全部 yes）
```

---

## 5. 常量缓冲区、推常量与布局

### 5.1 `__CB1` 的结构与实测大小

`CompilePasses()` 生成的 cbuffer 固定前缀为 5 个 8 字节成员（`uint2 __inputSize/__outputSize`、`float2 __inputPt/__outputPt/__scale` = 40 B），加上每个 PARAMETER（4 B）、以及每个非末位 PS-style pass 的 8 B。实测最大值：

| 效果 | 参数数 | `__CB1` 大小 |
|------|--------|--------------|
| CRT_Geom | 15 | 40 + 60 = **100 B** |
| Deband | 4 | 56 B |
| FSRCNNX / Anime4K / Ani4Kv2 / ACNet | 0 | 40 B |

两块 GPU `maxPushConstantsSize = 256`，规范下限 128 → 全部可放进 push constant。但仍**推荐 UBO**：`EffectDrawer::_UpdateConstants()` 已经按 D3D11 cbuffer 布局写结构体，直接映射到 `VkBuffer` + `vkCmdUpdateBuffer`/映射内存即可零改动复用；push constant 需要额外一条"参数上限检查 + 回退 UBO"的分支，收益（一次 128 B 拷贝）不值得。

### 5.2 布局：必须 `-fvk-use-dx-layout`

DXC 默认使用"relaxed/近似 std140"布局，对 Magpie 现有 cbuffer（只有标量与 2/4 分量向量）与 DX 布局一致，但对**数组与 float3** 不一致。实测（`/tmp/vkq/shaders/layout.hlsl`）：

```
struct Foo { float3 a; float b; float arr[3]; float2 v2; };
默认：            Foo.0=0  Foo.1=12  Foo.2=16  Foo.3=64   ← arr[3] 步长 16（std140）
-fvk-use-dx-layout：Foo.0=0  Foo.1=12  Foo.2=16  Foo.3=52   ← arr[3] 步长 4（HLSL 打包）
```

→ 必须传 `-fvk-use-dx-layout`，否则一旦用户效果在 COMMON 块或参数里用数组/float3（`$Globals` 或自定义 cbuffer），CPU 写入的偏移就会与 shader 读取错位——这是一种**静默错图**类 bug，比编译失败更难排查。

---

## 6. 内置效果兼容性抽样

### 6.1 抽样结果（22 个效果 / 56 个 pass，FP32 与 FP16 两种配置）

全部命令：`dxc -T cs_6_0 -E __M -spirv -fspv-target-env=vulkan1.3 -fvk-use-dx-layout -HV 2018`，随后 `spirv-val --target-env vulkan1.3`。

| 效果 | pass | 关键特性 | 分类 | SPIR-V 总量 | 编译耗时 | 单 pass 最大 |
|------|------|----------|------|-------------|----------|--------------|
| Bicubic | 1 | PS-style、`Load`+`SampleLevel`、2 参数 | **直接编译** | 44.7 KB | 56 ms | 56 ms |
| CAS | 1 | `CAPABILITY FP16` | **直接编译** | 8.2 KB | 22 ms | 22 ms |
| CAS_Scaling | 1 | 无采样器、32 线程 | **直接编译** | 29.3 KB | 41 ms | 41 ms |
| FSR_EASU | 1 | FP16、大量 `min`/`max`/`mad` | **直接编译** | 56.7 KB | 88 ms | 88 ms |
| FSR_RCAS | 1 | FP16、金色比例序列循环 | **直接编译** | 15.2 KB | 25 ms | 25 ms |
| Anime4K_Restore_M | 7 | `USE MulAdd`、FP16、`R16G16B16A16_FLOAT` 中间纹理 ×6 | **直接编译** | 145.5 KB | 213 ms | 36 ms |
| NNEDI3_nns16_win8x4 | 2 | 3 纹理、3 采样器、`//!COMMON #include`、`32,8` 线程 | **直接编译** | 89.3 KB | 120 ms | 67 ms |
| CRT_Geom | 1 | 15 参数、`frac`/`pow`/分支 | **直接编译** | 31.5 KB | 52 ms | 52 ms |
| Lanczos | 1 | 权重循环 | **直接编译** | 37.5 KB | 54 ms | 54 ms |
| SGSR | 1 | 2 参数 | **直接编译** | 34.6 KB | 46 ms | 46 ms |
| NIS | 1 | 4 纹理（DDS LUT）、18.5 KB groupshared | **直接编译** | 30.0 KB | 83 ms | 83 ms |
| NVSharpen | 1 | 逐像素卷积 | **直接编译** | 12.6 KB | 29 ms | 29 ms |
| FSRCNNX | 6 | groupshared、MRT（pass1 双输出） | **直接编译** | 146.4 KB | 210 ms | 43 ms |
| ACNet | 9 | `MulAdd`、FP16、`//!COMMON` | **直接编译** | 233.5 KB | 673 ms | 97 ms |
| Jinc | 1 | **向量三元表达式**（HLSL 2018 语义） | **需小改**：编译参数 `-HV 2018`（源文件无需改） | 9.8 KB | 21 ms | 21 ms |
| Deband | 1 | 参数化循环、2 采样器 | **直接编译** | 15.4 KB | 23 ms | 23 ms |
| FXAA_High / FXAA_Ultra | 1+1 | `//!COMMON` include（`FXAA.hlsli`） | **直接编译** | 11.5 KB ×2 | 24 ms | 24 ms |
| SMAA_High | 3 | 6 纹理（2 个 DDS LUT）、3 pass 链 | **直接编译** | 82.1 KB | 134 ms | 87 ms |
| Ani4Kv2_ArtCNN | 7 | `MulAdd`、26 个纹理声明、12.8 KB groupshared、`8,8` 线程 | **直接编译**（但编译慢，见 §8） | **2.28 MB** | **8.46 s** | **1.71 s** |
| RAVU_R3 | 2 | DDS LUT（`R16_FLOAT`/`RGBA16F`）、`//!COMMON` | **直接编译** | 39.5 KB | 56 ms | 35 ms |
| CuNNy-4x16-NVL | 6 | `MulAdd`、10 纹理、FP16 | **直接编译** | 449.6 KB | 818 ms | 175 ms |

统计：

| 配置 | pass 数 | 编译通过 | `spirv-val` 通过 | 总耗时 | 平均 | 最大 |
|------|---------|----------|------------------|--------|------|------|
| FP32（`MF=float`） | 56 | 56 | 56 | 11.3 s | 201 ms | 1,711 ms |
| FP16（`MF=min16float`） | 56 | 56 | 56 | 9.4 s | 168 ms | 1,353 ms |
| FP32，**不做任何 codegen 调整**（原样 `register`、无 `vk::` 属性） | 56 | 56 | 56 | 7.5 s | 134 ms | — |

第三行很重要：**效果源码与当前生成文本在 DXC 下"能编译"**，问题只在于绑定冲突（§3.1）与 `unorm` 语义（§4.1），二者都在 Magpie 自己的代码生成器里修，不涉及 `.hlsl` 文件。

### 6.2 分类结论

- **可直接编译（效果源零改动）**：**22/22 抽样效果、56/56 pass**。前提是编译器侧做到 §3.2-A + §4.1 + `-HV 2018` + `-fvk-use-dx-layout`。
- **需小改（仅编译器侧，不涉及 `.hlsl`）**：`Jinc`（向量三元需要 `-HV 2018`，否则报错）；`Bicubic`/`FSR_RCAS`/`FSR_EASU` 等在 FP16 下依赖"float 格式靠类型推断、UNORM 格式走显式属性"的代码生成规则（§2.2、§4.1）——写错规则的症状是报错或格式不匹配，不会静默错图。
- **需重写**：**0 个**。
- 如果把"固定 `-HV 2018`"算进"需小改"，则唯一落在这类的是 `Jinc`；其余 21 个效果在 DXC 默认设置下也通过。这一点决定了迁移计划里"语言版本固定"是一条**必做项**而不是可选项。
- 未抽样的 95 个效果文件（Anime4K 变体、CuNNy 变体、RAVU 变体、SMAA 变体、k7、xBRZ、Pixel Art、HybridCRT 等）与已抽样者在指令集与内建使用上同构（全库 grep 已确认无 wave/atomic/derivative 使用），风险低；建议在实现阶段用同一套生成器对全部 117 个效果做一次 CI 冒烟（编译 + `spirv-val`），实测吞吐约 20 个效果 / 3–15 s，全量约 1–2 min。

### 6.3 FP16 的性能含义（必须写清）

D3D11 路径上 `CAPABILITY FP16` 让 `MF4 = min16float4`，在 D3D11 驱动（尤其 AMD）上可能拿到 2× 的 ALU 吞吐；SPIR-V 路径上 `min16float` → 32 位 + `RelaxedPrecision`，**该收益消失**（RelaxedPrecision 不是 fp16 运算的授权，驱动可忽略）。实测可验证的旁证：FP16 模块大小与 FP32 相近（Anime4K 145.5 KB vs 175.3 KB），且 `OpTypeFloat 16` 一次都没出现。

对本仓效果的影响排序：Anime4K / ACNet / CuNNy / FSRCNNX / Ani4Kv2（卷积密集）受影响最大，Bicubic/CRT/FXAA/SMAA（标量或少量运算）几乎无感。这一点必须在迁移计划里作为**已知性能回退**登记，并在目标硬件上量化。

---

## 7. 运行时 DXC vs 预编译 SPIR-V vs 转译

### 7.1 以库形式链接 DXC（实测）

```cpp
IDxcUtils* utils; DxcCreateInstance(CLSID_DxcUtils, IID_PPV_ARGS(&utils));
IDxcCompiler3* comp; DxcCreateInstance(CLSID_DxcCompiler, IID_PPV_ARGS(&comp));
DxcBuffer buf{src.data(), src.size(), DXC_CP_UTF8};
const wchar_t* args[] = { L"-T", L"cs_6_0", L"-E", L"__M", L"-spirv",
                          L"-fspv-target-env=vulkan1.3", L"-fvk-use-dx-layout", L"-HV", L"2018" };
comp->Compile(&buf, args, _countof(args), nullptr, IID_PPV_ARGS(&res));
res->GetOutput(DXC_OUT_OBJECT, IID_PPV_ARGS(&spv), nullptr);
```

实测（`g++ -I/tmp/dxc/include -L/tmp/dxc/lib -ldxcompiler`，运行期 `libdxcompiler.so`）：

| 指标 | 值 |
|------|----|
| 产出 | 44,876 B SPIR-V（Bicubic） |
| 首次编译 | 38.1 ms |
| 50 次平均 | **35.65 ms**（`-O3` 默认） |
| 库体积 | `libdxcompiler.so` 31,792,000 B（31.8 MB，静态链接 LLVM） |
| 依赖 | `libz, libm, libstdc++, libgcc_s, libc` —— 无 X11/GL/系统组件依赖，可直接随包分发 |
| 线程安全 | `DxcCreateInstance` 本身线程安全，但**它创建的对象不是**："objects created by `DxcCreateInstance` aren't thread-safe. Compiler objects should be created and then used on the same thread." → 若要按 pass 并行编译（§7.4），必须**每线程一个 `IDxcCompiler3`/`IDxcUtils`** |
| 许可证 | LLVM Release License（`LICENSE-LLVM.txt`）+ MS 许可（`LICENSE-MS.txt`），release 包内自带 |

### 7.2 三种方案对比

| 方案 | 首次延迟 | 分发包体积 | 用户可编辑效果 | 主要风险 |
|------|----------|------------|----------------|----------|
| **运行时 DXC（推荐）** | 单 pass 20 ms–1.7 s；整效果 20 ms–8.5 s（Ani4Kv2） | +31.8 MB | ✅ 保持 | 编译延迟尖峰、DXC 版本行为漂移 |
| 预编译 SPIR-V | 0 | 内置效果 SPIR-V 合计约 3.6 MB（抽样 22 个效果实测总计 3.64 MB，含 Ani4Kv2 的 2.28 MB） | ❌ 丧失（`effects/` 是用户可编辑目录） | 用户效果无法编译，必须两套路径 |
| 混合：内置预编译 + 用户效果走 DXC | 内置 0，用户同左 | +31.8 MB + ~5 MB | ✅ | 两套代码路径、缓存键要区分 |
| glslang HLSL 前端 | 快（无 DXIL 层） | 无新增（系统库） | ✅ | 语义缺陷（下 §7.3） |
| HLSL→WGSL/GLSL 转译 | — | — | — | 无成熟开源路径，且目标引擎是 Vulkan 原生，无收益 |

**推荐**：运行时 DXC（库形式）+ 现有磁盘缓存。理由是"用户可编辑效果"是 MagpieFX 的核心产品特性（`docs/MagpieFX.md` 面向用户文档化的格式），预编译会直接砍掉它；而 31.8 MB 对桌面应用可接受，编译一次即缓存。

### 7.3 为什么不用 glslang 的 HLSL 前端（实测）

glslang 16.6 的 `-D`（HLSL）模式**能**编译全套 MagpieFX 源码（连重建的 Bicubic 与 Anime4K pass 都通过 `spirv-val`），看起来是零成本替代，但有三个实质缺陷：

1. **语义错误**：`WavePrefixSum` 被降到 `OpGroupNonUniformIAdd … InclusiveScan`（应为 `ExclusiveScan`；DXC 正确给出 `ExclusiveScan`）。这属于"能编译但算错"，最危险的一类。
2. **格式推断缺失**：`min16float4` 被当作 `float4`，`RWTexture2D<min16float4>` 输出 `Rgba32f`，而我们为 `R16G16B16A16_FLOAT` 中间纹理创建的 `VkImageView` 是 `R16G16B16A16_SFLOAT` → 管线创建即失败。且不支持 `[[vk::…]]` 属性族，没有任何补救手段。
3. **默认产出 SPIR-V 1.0**（`OpSource HLSL 500`、`--target-env` 默认不是 vulkan1.3），subgroup 指令需要 1.3 → 需要额外参数，且没有 `-fvk-*` 绑定重映射。

→ glslang 只能作为"应急后备/差分测试工具"，不能作为主后端。

### 7.4 缓存设计（可复用现状）

现状（`EffectCompiler.cpp:1634-1650`、`EffectCacheManager`）：

- 缓存键 = **移除注释后的效果源文本** + `InlineParams` 的 `名字=值*10000` 序列化；`flags` 的低 16 位（`InlineParams`/`NoFP16`）参与文件名而不是哈希；`rapidhash` 生成 64 位哈希；文件名 `{effectName}_{flags:04x}_{hash:016x}`。
- 缓存内容 = `yas` 二进制序列化的 `EffectDesc`，其中 `passes[i].cso` 是 `ID3DBlob`（自定义序列化器，写入 `bufferSize` + 字节）。

迁移只需两处：

1. `EffectDesc::EffectPassDesc::cso` 改为 `std::vector<uint8_t> spirv`（顺带让 `EffectCacheManager` 的 `ID3DBlob` 序列化器消失，`D3DCreateBlob` 依赖也去掉）。
2. `EFFECT_CACHE_VERSION` 15 → 16（旧 DXBC 缓存自然失效）。

额外建议：把 **DXC 版本号**并入缓存键（或文件名），否则升级 DXC 后旧 SPIR-V 仍会命中，掩盖行为变化。这是现有机制没有的（D3DCompile 随系统更新，Magpie 也没处理，但 DXC 会以"我们自己的二进制"形式随包升级，问题更突出）。

延迟特征决定实现形态：缓存未命中时最长 8.5 s（Ani4Kv2 7 个 pass）。因此：

- 编译必须放在后台线程（现状即如此），期间显示"正在编译效果"；
- 可按 pass 粒度并行（每 pass 独立、无依赖），4 线程即可把 8.5 s 压到 ~2.5 s；
- 首次使用某个效果有可感知的等待，需要 UI 提示（对应 `EffectsProfiler` 已有的 pass 计时用途）。

---

## 8. 代码复用评估（`EffectCompiler` / `EffectDrawer` / `EffectCacheManager`）

| 组件 | 复用度 | 说明 |
|------|--------|------|
| MagpieFX 指令解析（`ResolveHeader/Parameter/Texture/Sampler/Common/Pass`） | **100%** | 纯文本解析，零 D3D 依赖；`GetNextExpr`/`mu::Parser` 尺寸表达式同样保留 |
| HLSL 文本生成（`CompilePasses`、`CreatePassCode`、`MulAdd`、`Rmp8x8`、PS-style 包装） | **~95%** | 需要新增：`space` 后缀（§3.2-A）、UNORM/SNORM UAV 的 `vk::image_format`（§4.1）；其余文本逐字节可保留 |
| `EffectHelper::FORMAT_DESCS` | 复用 + 加列 | 增加 `VkFormat` 与 image-format token 两列；`srvTexelType/uavTexelType` 的 `unorm` 前缀在 Vulkan 路径下不写 |
| `DirectXHelper::CompileComputeShader` | **替换** | `D3DCompile(cs_5_0)` → `IDxcCompiler3::Compile`；签名/错误处理（`Logger::ComError` 打印 stderr）可原样保留 |
| `EffectDesc` / `EffectPassDesc` | 复用 + 改字段 | `cso: ID3DBlob` → `spirv: vector<uint8_t>`；`inputs/outputs/numThreads/blockSize/flags/desc` 全部保留 |
| `EffectCacheManager` | **90%** | 见 §7.4；`GetHash`/文件名规则/内存缓存/清理逻辑全保留 |
| `EffectDrawer` | **重写** | D3D11 专属：`CreateTexture2D`/`CreateComputeShader`/`CreateShaderResourceView`/`CreateUnorderedAccessView`/`Dispatch`。但**结构**（`_textures`、`_srvs/_uavs/dispatches`、`_UpdatePassResources`、`_UpdateConstants`）可一对一映射到 Vulkan 对象（`VkImage`/`VkImageView`/`VkDescriptorSet`/`VkPipeline`/`vkCmdDispatch`） |
| 反射相关 | **无** | 无 `D3DReflect` 使用，无需替代 |

`EffectDrawer` 的关键约束（实现时不能丢）：

- 中间纹理同时需要 `SAMPLED_IMAGE`（下一 pass 的 SRV）与 `STORAGE_IMAGE`（本 pass 的 UAV）→ 每个中间纹理一张 `VkImage` + 两种用途视图/描述符；`R8G8B8A8_UNORM` 输出纹理同理。
- 采样器按 `FILTER/ADDRESS` 指令组合缓存 `VkSampler`（Linear/Point × Clamp/Wrap，4 种组合即够）。
- `_UpdateConstants` 每 pass 写一次 cbuffer（100 B 上限），应使用持久映射的 `VkBuffer` 或 `vkCmdUpdateBuffer`，避免每帧分配。

---

## 9. 风险与未决问题

1. **FP16 性能回退幅度未知。** 需要在目标硬件（本机 780M 与 4060）上实测 Anime4K/ACNet/CuNNy 的帧时间差。此前在 D3D11 上"FP16 更快"的结论不能自动迁移。可选的补救：把 `MF*` 映射为 `float16_t` + `-enable-16bit-types`，在 groupshared/中间 buffer 内做 16 位运算，图像读写处显式转换；这会改动 `MulAdd` 重载与部分效果假设，属于独立研究项。
2. **Quad/wave 扩展依赖。** `QuadRead*` 会引入 `SPV_KHR_compute_shader_derivatives`。两块测试 GPU 都支持，但若把最低配置定为"Vulkan 1.3 核心 + 无该扩展"，则应禁止用户效果使用 Quad 内建（或检测扩展后降级）。当前内置效果不使用，暂不阻塞。
3. **DXC 版本固定策略。** 实测已出现两类"随版本改变行为"：默认 HLSL 语言版本（向量三元）、`vk::image_format` 与 `min16float` 的兼容性检查。建议：锁定 DXC 版本、随包分发、缓存键含版本号、CI 中对全部 117 个效果做编译冒烟。
4. **`shaderStorageImageExtendedFormats` 依赖。** 16 位 UNORM/SNORM 的 STORAGE_IMAGE 支持依赖该特性；需要在设备初始化时检查并准备回退（§4.2）。规范未强制，因此"在开发者机器上能跑"不等于"在所有目标机器上能跑"。
5. **`unorm` 语义的等价性证明。** 我基于"D3D `unorm float4` UAV 写入 = 定点量化"与"Vulkan UNORM 图像视图写入 = 定点量化"推断二者等价，尚未做像素级对比回归。建议实现阶段加一个 golden-image 测试（写入 0.0/0.5/1.0/超界值，读回比对）。
6. **`-O3` vs `-Od` 的调试路径。** `MP_DEBUG` 目前只体现为"不优化 + 调试信息"，SPIR-V 侧需要 `-Od -Zi -fspv-debug=line`（已实测可用），但 RenderDoc/`spirv-dis` 的源码关联体验与 PIX 不同，需要单独验证。
7. **未抽样效果**（95 个文件）尚未逐个编译；结构同构，但 `HybridCRT.props`、`Pixel Art`、`xBRZ`、`k7` 等可能使用未覆盖的指令组合，应以 CI 全量扫描代替抽样。

---

## 10. 附：最小验证示例（可直接复现）

`/tmp/vkq/shaders/bicubic_mpfx.hlsl` 是按 `EffectCompiler.cpp` 生成的 Bicubic pass 1 复刻源码（cbuffer `__CB1`、`Texture2D<MF4>`/`RWTexture2D<MF4>`、`SamplerState`、`Rmp8x8`/`GetInputSize` 等内置、PS-style 8×8 四点包装）。编译与检查：

```bash
$ /tmp/dxc/bin/dxc -T cs_6_0 -E __M -spirv -fspv-target-env=vulkan1.3 \
      -DMF=float -DMF2=float2 -DMF3=float3 -DMF4=float4 \
      -Fo bicubic.spv bicubic_mpfx.hlsl
$ echo $?          # 0
$ ls -l bicubic.spv
-rw-r--r-- 1 user user 44876 bicubic.spv
$ spirv-val --target-env vulkan1.3 bicubic.spv && echo OK
OK
$ spirv-dis bicubic.spv | head -12
; SPIR-V
; Version: 1.6
               OpCapability Shader
               OpEntryPoint GLCompute %__M "__M" %gl_LocalInvocationID %gl_WorkGroupID %__CB1 %INPUT %OUTPUT %sam
               OpExecutionMode %__M LocalSize 64 1 1
               OpSource HLSL 600
```

绑定/格式的关键片段（见 §3.1、§4.1）：

```
# 默认（不可用）
OpDecorate %__CB1 Binding 0     # b0
OpDecorate %INPUT Binding 0     # t0  ← 冲突
OpDecorate %OUTPUT Binding 0    # u0  ← 冲突
OpDecorate %sam Binding 0       # s0  ← 冲突

# 加 -fvk-t-shift 1000 0 -fvk-u-shift 2000 0 -fvk-s-shift 3000 0
OpDecorate %INPUT  Binding 1000
OpDecorate %OUTPUT Binding 2000
OpDecorate %sam    Binding 3000

# 或 codegen 写 register(t0, space1) / (u0, space2) / (s0, space3)
OpDecorate %In  DescriptorSet 1 Binding 0
OpDecorate %Out DescriptorSet 2 Binding 0
OpDecorate %smp DescriptorSet 3 Binding 0
```

辅助脚本（可丢弃，仅用于本报告的测量）：`/tmp/vkq/gen.py`（MagpieFX→HLSL 生成器）、`/tmp/vkq/run.py`（批量编译 + 计时 + 校验）、`/tmp/vkq/q2.c`（格式特性查询）、`/tmp/vkq/dxclib.cpp`（进程内 DXC 链接与计时）。

---

## 11. 来源清单（全部 2026-11-23 访问）

1. Microsoft DirectXShaderCompiler，`docs/SPIR-V.rst`（HLSL→SPIR-V 特性映射手册：类型映射、纹理/图像格式表、`vk::image_format` 对照表、wave intrinsic 表、`-fvk-*` 选项、Unsupported HLSL Features）—— <https://github.com/microsoft/DirectXShaderCompiler/blob/main/docs/SPIR-V.rst>
2. DXC release v1.9.2609（`linux_dxc_2026_09_28.x86_x64.tar.gz`；`ReleaseNotes.md`；`LICENSE-LLVM.txt`）—— <https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.9.2609>
3. DXC wiki：SPIR-V CodeGen —— <https://github.com/microsoft/DirectXShaderCompiler/wiki/SPIR%E2%80%90V-CodeGen>
4. DXC wiki：16-Bit Scalar Types —— <https://github.com/microsoft/DirectXShaderCompiler/wiki/16-Bit-Scalar-Types>
5. Khronos SPIR-V 规范（Image Format 枚举、capability/extension 规定）—— <https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html>
6. Vulkan-Docs `chapters/formats.adoc`（Mandatory Format Support 各表与 `{sym3}` 表注）—— <https://github.com/KhronosGroup/Vulkan-Docs/blob/main/chapters/formats.adoc>
7. Vulkan 规范 Formats 章 —— <https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#formats>
8. `VK_KHR_compute_shader_derivatives` 扩展规范 —— <https://github.com/KhronosGroup/Vulkan-Docs/blob/main/appendices/VK_KHR_compute_shader_derivatives.adoc>
9. 本地仓库（Magpie）：`src/Magpie.Core/EffectCompiler.cpp`（1855 行，`CompilePasses`/`CreatePassCode`/`Resolve*`）、`src/Magpie.Core/DirectXHelper.cpp`（`D3DCompile` 调用点，`cs_5_0`、`D3DCOMPILE_ENABLE_STRICTNESS`、`OPTIMIZATION_LEVEL3`）、`src/Magpie.Core/EffectDrawer.cpp`（D3D11 纹理/着色器/描述符绑定）、`src/Magpie.Core/EffectCacheManager.cpp`（`EFFECT_CACHE_VERSION=15`、`yas` 序列化 `ID3DBlob`、`rapidhash` 缓存键）、`src/Magpie.Core/include/EffectDesc.h`、`src/Magpie.Core/EffectHelper.h`（`FORMAT_DESCS` 20 项）、`docs/MagpieFX.md`
10. 本机实测输出：`vulkaninfo`（设备/限值/扩展）、`q2.c`（格式特性）、`dxc`/`spirv-val`/`spirv-dis`（编译与反汇编）、`dxclib.cpp`（库链接与 50 次编译计时）
