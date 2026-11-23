#include "renderer.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>

namespace {

std::vector<Uint8> LoadFile(const std::string &path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    return {};
  }
  return std::vector<Uint8>(std::istreambuf_iterator<char>(file),
                            std::istreambuf_iterator<char>());
}

} // namespace

Renderer::~Renderer() { Shutdown(); }

bool Renderer::Init(bool fullscreen, const std::string &shader_path,
                    const std::string &dump_path, int dump_after_frames,
                    std::string &error) {
  shader_path_ = shader_path;
  dump_path_ = dump_path;
  dump_after_frames_ = dump_after_frames < 1 ? 1 : dump_after_frames;

  const SDL_WindowFlags flags =
      fullscreen ? SDL_WINDOW_FULLSCREEN : SDL_WINDOW_RESIZABLE;
  window_ = SDL_CreateWindow("Magpie Vulkan prototype", 1280, 720, flags);
  if (!window_) {
    error = std::string("SDL_CreateWindow: ") + SDL_GetError();
    return false;
  }

  device_ = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_SPIRV, true, nullptr);
  if (!device_) {
    error = std::string("SDL_CreateGPUDevice: ") + SDL_GetError();
    return false;
  }
  if (!SDL_ClaimWindowForGPUDevice(device_, window_)) {
    error = std::string("SDL_ClaimWindowForGPUDevice: ") + SDL_GetError();
    return false;
  }
  {
    int logical_w = 0, logical_h = 0, pixel_w = 0, pixel_h = 0;
    SDL_GetWindowSize(window_, &logical_w, &logical_h);
    SDL_GetWindowSizeInPixels(window_, &pixel_w, &pixel_h);
    SDL_Log("window logical=%dx%d pixels=%dx%d", logical_w, logical_h, pixel_w,
            pixel_h);
  }

  std::vector<Uint8> spirv = LoadFile(shader_path_);
  if (spirv.empty()) {
    error = "cannot read SPIR-V shader: " + shader_path_;
    return false;
  }

  SDL_GPUComputePipelineCreateInfo pipeline_info{};
  pipeline_info.code_size = spirv.size();
  pipeline_info.code = spirv.data();
  pipeline_info.entrypoint = "main";
  pipeline_info.format = SDL_GPU_SHADERFORMAT_SPIRV;
  pipeline_info.num_samplers = 1;
  pipeline_info.num_readwrite_storage_textures = 1;
  pipeline_info.threadcount_x = 8;
  pipeline_info.threadcount_y = 8;
  pipeline_info.threadcount_z = 1;
  pipeline_ = SDL_CreateGPUComputePipeline(device_, &pipeline_info);
  if (!pipeline_) {
    error = std::string("SDL_CreateGPUComputePipeline: ") + SDL_GetError();
    return false;
  }

  SDL_GPUSamplerCreateInfo sampler_info{};
  sampler_info.min_filter = SDL_GPU_FILTER_LINEAR;
  sampler_info.mag_filter = SDL_GPU_FILTER_LINEAR;
  sampler_info.mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
  sampler_info.address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  sampler_info.address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  sampler_info.address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  sampler_ = SDL_CreateGPUSampler(device_, &sampler_info);
  if (!sampler_) {
    error = std::string("SDL_CreateGPUSampler: ") + SDL_GetError();
    return false;
  }

  SDL_Log("GPU driver: %s", SDL_GetGPUDeviceDriver(device_));
  return true;
}

bool Renderer::EnsureInput(const Frame &frame, std::string &error) {
  if (input_ && input_width_ == frame.width && input_height_ == frame.height &&
      input_bgra_ == frame.bgra) {
    return true;
  }
  ReleaseInput();

  SDL_GPUTextureCreateInfo texture_info{};
  texture_info.type = SDL_GPU_TEXTURETYPE_2D;
  texture_info.format = frame.bgra ? SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM
                                   : SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
  texture_info.usage = SDL_GPU_TEXTUREUSAGE_SAMPLER;
  texture_info.width = static_cast<Uint32>(frame.width);
  texture_info.height = static_cast<Uint32>(frame.height);
  texture_info.layer_count_or_depth = 1;
  texture_info.num_levels = 1;
  input_ = SDL_CreateGPUTexture(device_, &texture_info);
  if (!input_) {
    error = std::string("SDL_CreateGPUTexture(input): ") + SDL_GetError();
    return false;
  }

  SDL_GPUTransferBufferCreateInfo transfer_info{};
  transfer_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
  transfer_info.size =
      static_cast<Uint32>(frame.width) * static_cast<Uint32>(frame.height) * 4;
  transfer_ = SDL_CreateGPUTransferBuffer(device_, &transfer_info);
  if (!transfer_) {
    error = std::string("SDL_CreateGPUTransferBuffer: ") + SDL_GetError();
    ReleaseInput();
    return false;
  }

  input_width_ = frame.width;
  input_height_ = frame.height;
  input_bgra_ = frame.bgra;
  return true;
}

bool Renderer::EnsureOutput(uint32_t width, uint32_t height,
                            std::string &error) {
  if (output_ && output_width_ == width && output_height_ == height) {
    return true;
  }
  ReleaseOutput();

  SDL_GPUTextureCreateInfo texture_info{};
  texture_info.type = SDL_GPU_TEXTURETYPE_2D;
  texture_info.format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
  texture_info.usage =
      SDL_GPU_TEXTUREUSAGE_SAMPLER | SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE;
  texture_info.width = width;
  texture_info.height = height;
  texture_info.layer_count_or_depth = 1;
  texture_info.num_levels = 1;
  output_ = SDL_CreateGPUTexture(device_, &texture_info);
  if (!output_) {
    error = std::string("SDL_CreateGPUTexture(output): ") + SDL_GetError();
    return false;
  }

  output_width_ = width;
  output_height_ = height;
  return true;
}

bool Renderer::Draw(const Frame &frame, std::string &error) {
  if (frame.width <= 0 || frame.height <= 0 ||
      frame.pixels.size() <
          static_cast<size_t>(frame.width) * frame.height * 4) {
    error = "invalid frame";
    return false;
  }
  if (!EnsureInput(frame, error)) {
    return false;
  }

  int window_width = 0;
  int window_height = 0;
  if (!SDL_GetWindowSizeInPixels(window_, &window_width, &window_height) ||
      window_width <= 0 || window_height <= 0) {
    error = std::string("SDL_GetWindowSizeInPixels: ") + SDL_GetError();
    return false;
  }
  if (!EnsureOutput(static_cast<uint32_t>(window_width),
                    static_cast<uint32_t>(window_height), error)) {
    return false;
  }
  static bool logged = false;
  if (!logged) {
    SDL_Log("draw: window_pixels=%dx%d output=%ux%u input=%dx%d", window_width,
            window_height, output_width_, output_height_, frame.width,
            frame.height);
    logged = true;
  }

  void *mapped = SDL_MapGPUTransferBuffer(device_, transfer_, false);
  if (!mapped) {
    error = std::string("SDL_MapGPUTransferBuffer: ") + SDL_GetError();
    return false;
  }
  std::memcpy(mapped, frame.pixels.data(),
              static_cast<size_t>(frame.width) * frame.height * 4);
  SDL_UnmapGPUTransferBuffer(device_, transfer_);

  SDL_GPUCommandBuffer *command = SDL_AcquireGPUCommandBuffer(device_);
  if (!command) {
    error = std::string("SDL_AcquireGPUCommandBuffer: ") + SDL_GetError();
    return false;
  }

  SDL_GPUTextureTransferInfo transfer_info{};
  transfer_info.transfer_buffer = transfer_;
  transfer_info.offset = 0;
  transfer_info.pixels_per_row = static_cast<Uint32>(frame.width);
  transfer_info.rows_per_layer = static_cast<Uint32>(frame.height);

  SDL_GPUTextureRegion input_region{};
  input_region.texture = input_;
  input_region.w = static_cast<Uint32>(frame.width);
  input_region.h = static_cast<Uint32>(frame.height);
  input_region.d = 1;

  SDL_GPUCopyPass *copy_pass = SDL_BeginGPUCopyPass(command);
  SDL_UploadToGPUTexture(copy_pass, &transfer_info, &input_region, false);
  SDL_EndGPUCopyPass(copy_pass);

  SDL_GPUStorageTextureReadWriteBinding storage_binding{};
  storage_binding.texture = output_;
  storage_binding.mip_level = 0;
  storage_binding.layer = 0;
  storage_binding.cycle = false;

  SDL_GPUComputePass *compute_pass =
      SDL_BeginGPUComputePass(command, &storage_binding, 1, nullptr, 0);
  SDL_BindGPUComputePipeline(compute_pass, pipeline_);
  SDL_GPUTextureSamplerBinding sampler_binding{};
  sampler_binding.texture = input_;
  sampler_binding.sampler = sampler_;
  SDL_BindGPUComputeSamplers(compute_pass, 0, &sampler_binding, 1);
  SDL_DispatchGPUCompute(compute_pass, (output_width_ + 7) / 8,
                         (output_height_ + 7) / 8, 1);
  SDL_EndGPUComputePass(compute_pass);

  ++frames_seen_;
  SDL_GPUTransferBuffer *dump_buffer = nullptr;
  if (!dump_path_.empty() && !dumped_ && frames_seen_ >= dump_after_frames_) {
    SDL_GPUTransferBufferCreateInfo dump_info{};
    dump_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD;
    dump_info.size = output_width_ * output_height_ * 4;
    dump_buffer = SDL_CreateGPUTransferBuffer(device_, &dump_info);
    if (dump_buffer) {
      SDL_GPUTextureRegion source_region{};
      source_region.texture = output_;
      source_region.w = output_width_;
      source_region.h = output_height_;
      source_region.d = 1;
      SDL_GPUTextureTransferInfo destination{};
      destination.transfer_buffer = dump_buffer;
      destination.pixels_per_row = output_width_;
      destination.rows_per_layer = output_height_;
      SDL_GPUCopyPass *download_pass = SDL_BeginGPUCopyPass(command);
      SDL_DownloadFromGPUTexture(download_pass, &source_region, &destination);
      SDL_EndGPUCopyPass(download_pass);
    }
  }

  SDL_GPUTexture *swapchain = nullptr;
  Uint32 swapchain_width = 0;
  Uint32 swapchain_height = 0;
  if (!SDL_WaitAndAcquireGPUSwapchainTexture(
          command, window_, &swapchain, &swapchain_width, &swapchain_height)) {
    error =
        std::string("SDL_WaitAndAcquireGPUSwapchainTexture: ") + SDL_GetError();
    SDL_CancelGPUCommandBuffer(command);
    return false;
  }
  static bool logged_swapchain = false;
  if (!logged_swapchain) {
    SDL_Log("swapchain=%ux%u", swapchain_width, swapchain_height);
    logged_swapchain = true;
  }

  if (swapchain) {
    SDL_GPUBlitInfo blit_info{};
    blit_info.source.texture = output_;
    blit_info.source.w = output_width_;
    blit_info.source.h = output_height_;
    blit_info.destination.texture = swapchain;
    blit_info.destination.w = swapchain_width;
    blit_info.destination.h = swapchain_height;
    blit_info.load_op = SDL_GPU_LOADOP_CLEAR;
    blit_info.clear_color = SDL_FColor{0.01f, 0.01f, 0.02f, 1.0f};
    blit_info.filter = SDL_GPU_FILTER_LINEAR;
    SDL_BlitGPUTexture(command, &blit_info);
  }

  if (!SDL_SubmitGPUCommandBuffer(command)) {
    error = std::string("SDL_SubmitGPUCommandBuffer: ") + SDL_GetError();
    return false;
  }

  if (dump_buffer) {
    SDL_WaitForGPUIdle(device_);
    void *data = SDL_MapGPUTransferBuffer(device_, dump_buffer, false);
    if (data) {
      FILE *file = std::fopen(dump_path_.c_str(), "wb");
      if (file) {
        std::fprintf(file, "P6\n%u %u\n255\n", output_width_, output_height_);
        const auto *pixels = static_cast<const Uint8 *>(data);
        for (uint32_t y = 0; y < output_height_; ++y) {
          for (uint32_t x = 0; x < output_width_; ++x) {
            const Uint8 *p =
                pixels + (static_cast<size_t>(y) * output_width_ + x) * 4;
            std::fputc(p[0], file);
            std::fputc(p[1], file);
            std::fputc(p[2], file);
          }
        }
        std::fclose(file);
        SDL_Log("dumped %s (%ux%u)", dump_path_.c_str(), output_width_,
                output_height_);
      }
      SDL_UnmapGPUTransferBuffer(device_, dump_buffer);
    }
    SDL_ReleaseGPUTransferBuffer(device_, dump_buffer);
    dumped_ = true;
  }
  return true;
}

void Renderer::ReleaseInput() {
  if (transfer_) {
    SDL_ReleaseGPUTransferBuffer(device_, transfer_);
    transfer_ = nullptr;
  }
  if (input_) {
    SDL_ReleaseGPUTexture(device_, input_);
    input_ = nullptr;
  }
  input_width_ = 0;
  input_height_ = 0;
}

void Renderer::ReleaseOutput() {
  if (output_) {
    SDL_ReleaseGPUTexture(device_, output_);
    output_ = nullptr;
  }
  output_width_ = 0;
  output_height_ = 0;
}

void Renderer::Shutdown() {
  if (device_) {
    SDL_WaitForGPUIdle(device_);
  }
  ReleaseInput();
  ReleaseOutput();
  if (sampler_) {
    SDL_ReleaseGPUSampler(device_, sampler_);
    sampler_ = nullptr;
  }
  if (pipeline_) {
    SDL_ReleaseGPUComputePipeline(device_, pipeline_);
    pipeline_ = nullptr;
  }
  if (window_ && device_) {
    SDL_ReleaseWindowFromGPUDevice(device_, window_);
  }
  if (device_) {
    SDL_DestroyGPUDevice(device_);
    device_ = nullptr;
  }
  if (window_) {
    SDL_DestroyWindow(window_);
    window_ = nullptr;
  }
}

const char *Renderer::Driver() const {
  return device_ ? SDL_GetGPUDeviceDriver(device_) : "";
}
