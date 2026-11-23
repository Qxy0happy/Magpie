// Minimal MagpieFX-style bicubic compute shader for the Vulkan prototype.
// This is derived from the Bicubic effect's sampling shape, but uses explicit
// Vulkan bindings so SDL_GPU's SPIR-V pipeline layout can consume it.
//
// Compile:
//   dxc -T cs_6_0 -E main -spirv -fspv-target-env=vulkan1.0 -HV 2018 \
//       -Fo bicubic.spv bicubic.hlsl

[[vk::binding(0, 0)]] [[vk::combinedImageSampler]]
Texture2D<float4> inputTex;
[[vk::binding(0, 0)]] [[vk::combinedImageSampler]]
SamplerState inputSampler;
[[vk::binding(0, 1)]] [[vk::image_format("rgba8")]]
RWTexture2D<float4> outputTex;

float cubicWeight(float x) {
    float ax = abs(x);
    if (ax <= 1.0) {
        return 1.5 * ax * ax * ax - 2.5 * ax * ax + 1.0;
    }
    if (ax < 2.0) {
        return -0.5 * ax * ax * ax + 2.5 * ax * ax - 4.0 * ax + 2.0;
    }
    return 0.0;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint outW, outH;
    outputTex.GetDimensions(outW, outH);
    if (id.x >= outW || id.y >= outH) {
        return;
    }

    uint inW, inH;
    inputTex.GetDimensions(inW, inH);
    if (inW == 0 || inH == 0) {
        return;
    }

    float2 srcSize = float2(inW, inH);
    float2 dstSize = float2(outW, outH);
    float2 p = (float2(id.xy) + 0.5) * srcSize / dstSize - 0.5;
    int2 base = int2(floor(p));
    float2 f = p - floor(p);

    float4 sum = float4(0, 0, 0, 0);
    [unroll] for (int y = -1; y <= 2; ++y) {
        [unroll] for (int x = -1; x <= 2; ++x) {
            int2 s = clamp(base + int2(x, y), int2(0, 0), int2(inW - 1, inH - 1));
            float2 uv = (float2(s) + 0.5) / srcSize;
            float4 c = inputTex.SampleLevel(inputSampler, uv, 0);
            sum += c * (cubicWeight(float(x) - f.x) * cubicWeight(float(y) - f.y));
        }
    }
    outputTex[id.xy] = saturate(sum);
}
