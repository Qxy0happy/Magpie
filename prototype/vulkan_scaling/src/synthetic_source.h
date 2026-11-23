#pragma once

#include <SDL3/SDL.h>
#include <cmath>
#include <cstdint>

#include "frame.h"

// Synthetic moving test pattern. Used to verify the compute/present path
// without opening a portal dialog.
class SyntheticSource {
public:
  SyntheticSource(int width = 640, int height = 360)
      : width_(width), height_(height), start_ns_(SDL_GetTicksNS()) {}

  bool Read(Frame &frame, int /*timeout_ms*/) {
    const int64_t now = SDL_GetTicksNS();
    const double t = static_cast<double>(now - start_ns_) / 1e9;

    frame.width = width_;
    frame.height = height_;
    frame.bgra = true;
    frame.capture_ns = now;
    frame.pixels.resize(static_cast<size_t>(width_) * height_ * 4);

    const int bar = static_cast<int>((t * 180.0)) % width_;
    for (int y = 0; y < height_; ++y) {
      for (int x = 0; x < width_; ++x) {
        uint8_t *p =
            frame.pixels.data() + (static_cast<size_t>(y) * width_ + x) * 4;
        const int checker = ((x / 48) + (y / 48)) & 1;
        p[0] = static_cast<uint8_t>((x * 255) / width_);  // B
        p[1] = static_cast<uint8_t>((y * 255) / height_); // G
        p[2] = static_cast<uint8_t>(
            (std::sin(x * 0.04 + t * 2.0) + 1.0) * 90.0 + checker * 40); // R
        p[3] = 255;
        if (std::abs(x - bar) < 6) {
          p[0] = 240;
          p[1] = 240;
          p[2] = 240;
        }
      }
    }
    return true;
  }

private:
  int width_;
  int height_;
  int64_t start_ns_;
};
