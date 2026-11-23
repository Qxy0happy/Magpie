#pragma once

#include <gio/gio.h>
#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>

#include <condition_variable>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "frame.h"

// xdg-desktop-portal ScreenCast + PipeWire capture.
//
// Flow: CreateSession -> SelectSources(WINDOW) -> Start -> OpenPipeWireRemote
// -> pw_context_connect_fd -> pw_stream. Frames are copied out of the PipeWire
// buffer as tightly-packed BGRA/RGBA and handed to the render thread.
class PortalCapture {
public:
  PortalCapture() = default;
  ~PortalCapture();

  void SetMonitor(bool monitor) { monitor_ = monitor; }
  bool Start(std::string &error);
  bool Read(Frame &frame, int timeout_ms);
  void Stop();

private:
  bool CreateSession(std::string &error);
  bool SelectSources(std::string &error);
  bool StartSession(std::string &error);
  bool OpenPipeWireRemote(std::string &error);
  bool StartPipeWire(int fd, const std::string &target, std::string &error);

  bool CallPortal(const char *method, GVariant *params,
                  const std::string &request_path, std::string &error,
                  GVariant **results, int timeout_sec);
  std::string MakeToken(const char *prefix);
  std::string RequestPath(const std::string &token) const;

  static void OnResponse(GDBusConnection *connection, const gchar *sender_name,
                         const gchar *object_path, const gchar *interface_name,
                         const gchar *signal_name, GVariant *parameters,
                         gpointer user_data);
  static gboolean OnTimeout(gpointer user_data);
  static void OnStreamParam(void *userdata, uint32_t id,
                            const struct spa_pod *param);
  static void OnStreamProcess(void *userdata);

  void HandleParam(const struct spa_pod *param);
  void HandleProcess();

  GDBusConnection *connection_ = nullptr;
  GDBusProxy *proxy_ = nullptr;
  std::string session_handle_;
  std::string target_;
  int pw_fd_ = -1;
  bool monitor_ = false;

  struct pw_main_loop *pw_loop_ = nullptr;
  struct pw_context *pw_context_ = nullptr;
  struct pw_core *pw_core_ = nullptr;
  struct pw_stream *pw_stream_ = nullptr;
  spa_hook stream_listener_{};
  std::thread pw_thread_;
  bool pw_initialized_ = false;

  std::mutex state_mutex_;
  int width_ = 0;
  int height_ = 0;
  spa_video_format format_ = SPA_VIDEO_FORMAT_UNKNOWN;

  std::mutex frame_mutex_;
  std::condition_variable frame_cv_;
  std::optional<Frame> latest_frame_;

  int token_counter_ = 0;
};
