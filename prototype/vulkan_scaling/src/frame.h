#pragma once

#include <cstdint>
#include <vector>

// One tightly-packed BGRA/RGBA frame produced by the synthetic source or by
// the portal/PipeWire capture path. pixels is always width * height * 4 bytes.
struct Frame {
  std::vector<uint8_t> pixels;
  int width = 0;
  int height = 0;
  bool bgra = true;
  // Wall-clock time when the frame was copied out of PipeWire (or generated).
  int64_t capture_ns = 0;
};
