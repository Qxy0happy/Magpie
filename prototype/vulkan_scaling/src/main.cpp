#include <SDL3/SDL.h>

#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "portal_capture.h"
#include "renderer.h"
#include "synthetic_source.h"

namespace {

struct Options {
  bool portal = false;
  bool windowed = false;
  int seconds = 0;
  bool monitor = false;
  std::string shader_path;
  std::string dump_path;
  int dump_frame = 1;
  std::string log_path;
};

void PrintUsage(const char *argv0) {
  std::printf(
      "usage: %s [options]\n"
      "  --source synthetic|portal   frame source (default: portal)\n"
      "  --windowed                  use a window instead of fullscreen\n"
      "  --seconds N                 stop after N seconds (0 = until "
      "ESC/close)\n"
      "  --shader PATH               SPIR-V shader path (default: bicubic.spv "
      "next to executable)\n"
      "  --dump PATH                 write a scaled frame as a PPM\n"
      "  --dump-frame N              dump frame N (default: 1)\n"
      "  --monitor                   capture a monitor instead of a window\n"
      "  --log PATH                  write stdout/stderr to a file\n",
      argv0);
}

bool ParseOptions(int argc, char **argv, Options &options) {
  for (int i = 1; i < argc; ++i) {
    const char *arg = argv[i];
    if (std::strcmp(arg, "--source") == 0 && i + 1 < argc) {
      const char *value = argv[++i];
      if (std::strcmp(value, "portal") == 0) {
        options.portal = true;
      } else if (std::strcmp(value, "synthetic") == 0) {
        options.portal = false;
      } else {
        std::fprintf(stderr, "unknown source: %s\n", value);
        return false;
      }
    } else if (std::strcmp(arg, "--windowed") == 0) {
      options.windowed = true;
    } else if (std::strcmp(arg, "--seconds") == 0 && i + 1 < argc) {
      options.seconds = std::atoi(argv[++i]);
    } else if (std::strcmp(arg, "--shader") == 0 && i + 1 < argc) {
      options.shader_path = argv[++i];
    } else if (std::strcmp(arg, "--dump") == 0 && i + 1 < argc) {
      options.dump_path = argv[++i];
    } else if (std::strcmp(arg, "--dump-frame") == 0 && i + 1 < argc) {
      options.dump_frame = std::atoi(argv[++i]);
    } else if (std::strcmp(arg, "--monitor") == 0) {
      options.monitor = true;
    } else if (std::strcmp(arg, "--log") == 0 && i + 1 < argc) {
      options.log_path = argv[++i];
    } else if (std::strcmp(arg, "--help") == 0 || std::strcmp(arg, "-h") == 0) {
      PrintUsage(argv[0]);
      std::exit(0);
    } else {
      std::fprintf(stderr, "unknown option: %s\n", arg);
      return false;
    }
  }
  return true;
}

} // namespace

int main(int argc, char **argv) {
  Options options;
  if (!ParseOptions(argc, argv, options)) {
    PrintUsage(argv[0]);
    return 2;
  }

  if (!options.log_path.empty()) {
    if (std::freopen(options.log_path.c_str(), "w", stdout)) {
      dup2(fileno(stdout), fileno(stderr));
      std::setvbuf(stdout, nullptr, _IONBF, 0);
      std::setvbuf(stderr, nullptr, _IONBF, 0);
    }
  }

  SDL_SetHint(SDL_HINT_APP_NAME, "Magpie Vulkan prototype");
  SDL_SetHint(SDL_HINT_APP_ID, "io.github.qxy0happy.MagpiePrototype");
  if (std::getenv("WAYLAND_DISPLAY") && !std::getenv("SDL_VIDEODRIVER")) {
    SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "wayland");
  }
  if (!SDL_Init(SDL_INIT_VIDEO)) {
    std::fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
    return 1;
  }
  SDL_Log("video driver=%s", SDL_GetCurrentVideoDriver());

  if (options.shader_path.empty()) {
    const char *base = SDL_GetBasePath();
    options.shader_path = std::string(base ? base : "") + "bicubic.spv";
  }

  std::string error;
  Renderer renderer;
  if (!renderer.Init(!options.windowed, options.shader_path, options.dump_path,
                     options.dump_frame, error)) {
    std::fprintf(stderr, "renderer init: %s\n", error.c_str());
    SDL_Quit();
    return 1;
  }

  SyntheticSource synthetic_source;
  PortalCapture portal_capture;
  portal_capture.SetMonitor(options.monitor);
  if (options.portal) {
    std::printf("starting xdg-desktop-portal ScreenCast; select a %s...\n",
                options.monitor ? "monitor" : "window");
    if (!portal_capture.Start(error)) {
      std::fprintf(stderr, "portal capture: %s\n", error.c_str());
      renderer.Shutdown();
      SDL_Quit();
      return 1;
    }
  }

  std::printf("source=%s gpu=%s\n", options.portal ? "portal" : "synthetic",
              renderer.Driver());
  std::printf("Press ESC to stop.\n");

  bool running = true;
  const Uint64 start_ns = SDL_GetTicksNS();
  Uint64 report_ns = start_ns;
  Uint64 frames = 0;
  double latency_sum_ms = 0.0;
  Uint64 latency_count = 0;

  while (running) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT) {
        running = false;
      } else if (event.type == SDL_EVENT_KEY_DOWN &&
                 event.key.key == SDLK_ESCAPE) {
        running = false;
      }
    }

    Frame frame;
    const bool got_frame = options.portal ? portal_capture.Read(frame, 100)
                                          : synthetic_source.Read(frame, 100);
    if (got_frame) {
      const Uint64 submit_start_ns = SDL_GetTicksNS();
      if (!renderer.Draw(frame, error)) {
        std::fprintf(stderr, "render: %s\n", error.c_str());
        break;
      }
      const Uint64 submit_end_ns = SDL_GetTicksNS();
      if (frame.capture_ns > 0) {
        latency_sum_ms +=
            static_cast<double>(submit_end_ns - frame.capture_ns) / 1e6;
        ++latency_count;
      }
      ++frames;
    }

    const Uint64 now_ns = SDL_GetTicksNS();
    if (now_ns - report_ns >= 1000000000ULL) {
      const double elapsed_s = static_cast<double>(now_ns - start_ns) / 1e9;
      const double fps = elapsed_s > 0 ? frames / elapsed_s : 0;
      const double latency = latency_count ? latency_sum_ms / latency_count : 0;
      std::printf("t=%.1fs frames=%llu fps=%.1f avg_capture_to_submit=%.2fms\n",
                  elapsed_s, static_cast<unsigned long long>(frames), fps,
                  latency);
      report_ns = now_ns;
    }

    if (options.seconds > 0 &&
        now_ns - start_ns >=
            static_cast<Uint64>(options.seconds) * 1000000000ULL) {
      running = false;
    }
  }

  const double elapsed_s =
      static_cast<double>(SDL_GetTicksNS() - start_ns) / 1e9;
  const double fps = elapsed_s > 0 ? frames / elapsed_s : 0;
  const double latency = latency_count ? latency_sum_ms / latency_count : 0;
  std::printf("summary: frames=%llu elapsed=%.2fs fps=%.1f "
              "avg_capture_to_submit=%.2fms\n",
              static_cast<unsigned long long>(frames), elapsed_s, fps, latency);

  portal_capture.Stop();
  renderer.Shutdown();
  SDL_Quit();
  return 0;
}
