#pragma once

#include <SDL3/SDL.h>
#include <cstdint>
#include <string>

#include "frame.h"

// SDL3 GPU renderer. On Linux SDL3 uses the Vulkan backend; the compute
// shader is compiled from HLSL to SPIR-V by DXC. The window is a normal
// fullscreen xdg_toplevel, not a layer-shell surface: layer-shell integration
// is a separate risk tracked by the map.
class Renderer {
public:
  ~Renderer();

  bool Init(bool fullscreen, const std::string &shader_path,
            const std::string &dump_path, int dump_after_frames,
            std::string &error);
  bool Draw(const Frame &frame, std::string &error);
  void Shutdown();

  const char *Driver() const;

private:
  bool EnsureInput(const Frame &frame, std::string &error);
  bool EnsureOutput(uint32_t width, uint32_t height, std::string &error);
  void ReleaseInput();
  void ReleaseOutput();

  SDL_Window *window_ = nullptr;
  SDL_GPUDevice *device_ = nullptr;
  SDL_GPUComputePipeline *pipeline_ = nullptr;
  SDL_GPUSampler *sampler_ = nullptr;
  SDL_GPUTexture *input_ = nullptr;
  SDL_GPUTexture *output_ = nullptr;
  SDL_GPUTransferBuffer *transfer_ = nullptr;

  int input_width_ = 0;
  int input_height_ = 0;
  bool input_bgra_ = true;
  uint32_t output_width_ = 0;
  uint32_t output_height_ = 0;
  std::string shader_path_;
  std::string dump_path_;
  int dump_after_frames_ = 1;
  int frames_seen_ = 0;
  bool dumped_ = false;
};
