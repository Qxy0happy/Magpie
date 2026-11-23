#include "portal_capture.h"

#include <SDL3/SDL.h>
#include <gio/gunixfdlist.h>
#include <spa/param/buffers.h>
#include <spa/param/video/raw.h>
#include <spa/pod/builder.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>

namespace {

struct ResponseState {
  GMainLoop *loop = nullptr;
  guint32 response = 2;
  GVariant *results = nullptr;
  bool done = false;
  bool timed_out = false;
};

void SubscribeResponseCallback(GDBusConnection * /*connection*/,
                               const gchar * /*sender_name*/,
                               const gchar * /*object_path*/,
                               const gchar * /*interface_name*/,
                               const gchar * /*signal_name*/,
                               GVariant *parameters, gpointer user_data) {
  auto *state = static_cast<ResponseState *>(user_data);
  if (state->done) {
    return;
  }
  guint32 response = 2;
  GVariant *results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  state->response = response;
  state->results = results;
  state->done = true;
  g_main_loop_quit(state->loop);
}

gboolean TimeoutCallback(gpointer user_data) {
  auto *state = static_cast<ResponseState *>(user_data);
  if (!state->done) {
    state->timed_out = true;
    state->done = true;
    g_main_loop_quit(state->loop);
  }
  return G_SOURCE_REMOVE;
}

int64_t NowNs() { return SDL_GetTicksNS(); }

} // namespace

PortalCapture::~PortalCapture() { Stop(); }

std::string PortalCapture::MakeToken(const char *prefix) {
  return std::string("magpie_") + prefix + "_" + std::to_string(::getpid()) +
         "_" + std::to_string(token_counter_++);
}

std::string PortalCapture::RequestPath(const std::string &token) const {
  const char *unique =
      connection_ ? g_dbus_connection_get_unique_name(connection_) : nullptr;
  std::string sender(unique ? unique : "");
  if (!sender.empty() && sender[0] == ':') {
    sender.erase(0, 1);
  }
  std::replace(sender.begin(), sender.end(), '.', '_');
  return "/org/freedesktop/portal/desktop/request/" + sender + "/" + token;
}

bool PortalCapture::CallPortal(const char *method, GVariant *params,
                               const std::string &request_path,
                               std::string &error, GVariant **results,
                               int timeout_sec) {
  ResponseState state;
  state.loop = g_main_loop_new(nullptr, FALSE);

  const auto subscribe = [this, &state](const std::string &path) {
    return g_dbus_connection_signal_subscribe(
        connection_, "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request", "Response", path.c_str(), nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE, SubscribeResponseCallback, &state, nullptr);
  };

  guint subscription = subscribe(request_path);
  guint returned_subscription = 0;
  guint timeout_id = g_timeout_add_seconds(static_cast<guint>(timeout_sec),
                                           TimeoutCallback, &state);

  GError *gerror = nullptr;
  GVariant *reply =
      g_dbus_proxy_call_sync(proxy_, method, params, G_DBUS_CALL_FLAGS_NONE,
                             timeout_sec * 1000, nullptr, &gerror);
  if (!reply) {
    error =
        std::string(method) + ": " + (gerror ? gerror->message : "no reply");
    if (gerror) {
      g_error_free(gerror);
    }
    g_dbus_connection_signal_unsubscribe(connection_, subscription);
    if (!state.timed_out) {
      g_source_remove(timeout_id);
    }
    g_main_loop_unref(state.loop);
    return false;
  }

  const char *returned_handle = nullptr;
  g_variant_get(reply, "(&o)", &returned_handle);
  if (returned_handle && request_path != returned_handle) {
    SDL_Log("portal handle mismatch: expected %s, got %s", request_path.c_str(),
            returned_handle);
    returned_subscription = subscribe(returned_handle);
  }
  g_variant_unref(reply);

  g_main_loop_run(state.loop);

  g_dbus_connection_signal_unsubscribe(connection_, subscription);
  if (returned_subscription) {
    g_dbus_connection_signal_unsubscribe(connection_, returned_subscription);
  }
  if (!state.timed_out) {
    g_source_remove(timeout_id);
  }
  g_main_loop_unref(state.loop);

  if (!state.done || state.response != 0) {
    error = std::string(method) + " failed or was cancelled (response=" +
            std::to_string(state.response) + ")";
    if (state.results) {
      g_variant_unref(state.results);
    }
    return false;
  }

  *results = state.results;
  return true;
}

bool PortalCapture::CreateSession(std::string &error) {
  const std::string token = MakeToken("create");
  const std::string session_token = "magpie_session_" +
                                    std::to_string(::getpid()) + "_" +
                                    std::to_string(token_counter_++);

  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(session_token.c_str()));
  GVariant *params = g_variant_new("(a{sv})", &options);

  GVariant *results = nullptr;
  if (!CallPortal("CreateSession", params, RequestPath(token), error, &results,
                  10)) {
    return false;
  }

  const char *session = nullptr;
  if (!g_variant_lookup(results, "session_handle", "&s", &session) ||
      !session) {
    error = "CreateSession response has no session_handle";
    g_variant_unref(results);
    return false;
  }
  session_handle_ = session;
  g_variant_unref(results);
  SDL_Log("portal session: %s", session_handle_.c_str());
  return true;
}

bool PortalCapture::SelectSources(std::string &error) {
  const std::string token = MakeToken("select");
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  // MONITOR=1, WINDOW=2. The prototype captures a single window unless
  // --monitor is given for a pipeline smoke test.
  g_variant_builder_add(&options, "{sv}", "types",
                        g_variant_new_uint32(monitor_ ? 1 : 2));
  g_variant_builder_add(&options, "{sv}", "multiple",
                        g_variant_new_boolean(FALSE));
  // Embedded cursor keeps the cursor in the stream.
  g_variant_builder_add(&options, "{sv}", "cursor_mode",
                        g_variant_new_uint32(2));
  g_variant_builder_add(&options, "{sv}", "persist_mode",
                        g_variant_new_uint32(0));
  GVariant *params =
      g_variant_new("(oa{sv})", session_handle_.c_str(), &options);

  GVariant *results = nullptr;
  if (!CallPortal("SelectSources", params, RequestPath(token), error, &results,
                  10)) {
    return false;
  }
  g_variant_unref(results);
  return true;
}

bool PortalCapture::StartSession(std::string &error) {
  const std::string token = MakeToken("start");
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  GVariant *params =
      g_variant_new("(osa{sv})", session_handle_.c_str(), "", &options);

  GVariant *results = nullptr;
  if (!CallPortal("Start", params, RequestPath(token), error, &results, 120)) {
    return false;
  }

  GVariant *streams =
      g_variant_lookup_value(results, "streams", G_VARIANT_TYPE("a(ua{sv})"));
  if (!streams || g_variant_n_children(streams) == 0) {
    error = "Start response has no streams";
    if (streams) {
      g_variant_unref(streams);
    }
    g_variant_unref(results);
    return false;
  }

  GVariant *stream = g_variant_get_child_value(streams, 0);
  guint32 node_id = 0;
  GVariant *properties = nullptr;
  g_variant_get(stream, "(u@a{sv})", &node_id, &properties);
  guint64 serial = 0;
  if (g_variant_lookup(properties, "pipewire-serial", "t", &serial)) {
    target_ = std::to_string(serial);
  } else {
    target_ = std::to_string(node_id);
  }
  SDL_Log("portal stream node=%u target=%s", node_id, target_.c_str());

  g_variant_unref(properties);
  g_variant_unref(stream);
  g_variant_unref(streams);
  g_variant_unref(results);
  return true;
}

bool PortalCapture::OpenPipeWireRemote(std::string &error) {
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  GVariant *params =
      g_variant_new("(oa{sv})", session_handle_.c_str(), &options);

  GError *gerror = nullptr;
  GUnixFDList *fd_list = nullptr;
  GVariant *reply = g_dbus_proxy_call_with_unix_fd_list_sync(
      proxy_, "OpenPipeWireRemote", params, G_DBUS_CALL_FLAGS_NONE, 10000,
      nullptr, &fd_list, nullptr, &gerror);
  if (!reply) {
    error = std::string("OpenPipeWireRemote: ") +
            (gerror ? gerror->message : "no reply");
    if (gerror) {
      g_error_free(gerror);
    }
    if (fd_list) {
      g_object_unref(fd_list);
    }
    return false;
  }

  gint32 fd_index = -1;
  g_variant_get(reply, "(h)", &fd_index);
  int fd = g_unix_fd_list_get(fd_list, fd_index, &gerror);
  if (fd < 0) {
    error = std::string("g_unix_fd_list_get: ") +
            (gerror ? gerror->message : "no fd");
    if (gerror) {
      g_error_free(gerror);
    }
    g_variant_unref(reply);
    g_object_unref(fd_list);
    return false;
  }

  g_variant_unref(reply);
  g_object_unref(fd_list);
  pw_fd_ = fd;
  return true;
}

bool PortalCapture::StartPipeWire(int fd, const std::string &target,
                                  std::string &error) {
  pw_init(nullptr, nullptr);
  pw_initialized_ = true;

  pw_loop_ = pw_main_loop_new(nullptr);
  if (!pw_loop_) {
    error = "pw_main_loop_new failed";
    return false;
  }
  pw_context_ = pw_context_new(pw_main_loop_get_loop(pw_loop_), nullptr, 0);
  if (!pw_context_) {
    error = "pw_context_new failed";
    return false;
  }
  pw_core_ = pw_context_connect_fd(pw_context_, fd, nullptr, 0);
  if (!pw_core_) {
    error = "pw_context_connect_fd failed";
    return false;
  }

  pw_properties *properties =
      pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY,
                        "Capture", PW_KEY_MEDIA_ROLE, "Screen",
                        PW_KEY_TARGET_OBJECT, target.c_str(), nullptr);
  pw_stream_ = pw_stream_new(pw_core_, "magpie-vulkan-capture", properties);
  if (!pw_stream_) {
    error = "pw_stream_new failed";
    return false;
  }

  static const struct pw_stream_events kStreamEvents = {
      .version = PW_VERSION_STREAM_EVENTS,
      .param_changed = &PortalCapture::OnStreamParam,
      .process = &PortalCapture::OnStreamProcess,
  };
  pw_stream_add_listener(pw_stream_, &stream_listener_, &kStreamEvents, this);

  uint8_t buffer[4096];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
  const spa_pod *params[2];
  spa_pod_frame frame;

  spa_rectangle min_size = SPA_RECTANGLE(1, 1);
  spa_rectangle default_size = SPA_RECTANGLE(1, 1);
  spa_rectangle max_size = SPA_RECTANGLE(8192, 8192);

  spa_pod_builder_push_object(&builder, &frame, SPA_TYPE_OBJECT_Format,
                              SPA_PARAM_EnumFormat);
  spa_pod_builder_add(
      &builder, SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
      SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
      SPA_FORMAT_VIDEO_format,
      SPA_POD_CHOICE_ENUM_Id(5, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRA,
                             SPA_VIDEO_FORMAT_RGBx, SPA_VIDEO_FORMAT_RGBA,
                             SPA_VIDEO_FORMAT_RGB),
      SPA_FORMAT_VIDEO_size,
      SPA_POD_CHOICE_RANGE_Rectangle(&min_size, &default_size, &max_size), 0);
  params[0] =
      static_cast<const spa_pod *>(spa_pod_builder_pop(&builder, &frame));

  spa_pod_builder_push_object(&builder, &frame, SPA_TYPE_OBJECT_ParamBuffers,
                              SPA_PARAM_Buffers);
  spa_pod_builder_add(
      &builder, SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(2, 2, 8),
      SPA_PARAM_BUFFERS_blocks, SPA_POD_Int(1), SPA_PARAM_BUFFERS_dataType,
      SPA_POD_CHOICE_FLAGS_Int((1 << SPA_DATA_MemFd) | (1 << SPA_DATA_MemPtr)),
      0);
  params[1] =
      static_cast<const spa_pod *>(spa_pod_builder_pop(&builder, &frame));

  if (pw_stream_connect(
          pw_stream_, PW_DIRECTION_INPUT, PW_ID_ANY,
          static_cast<pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT |
                                       PW_STREAM_FLAG_MAP_BUFFERS |
                                       PW_STREAM_FLAG_RT_PROCESS),
          params, 2) < 0) {
    error = "pw_stream_connect failed";
    return false;
  }

  pw_thread_ = std::thread([this] { pw_main_loop_run(pw_loop_); });
  SDL_Log("pipewire capture started, target=%s", target.c_str());
  return true;
}

bool PortalCapture::Start(std::string &error) {
  GError *gerror = nullptr;
  connection_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &gerror);
  if (!connection_) {
    error = std::string("g_bus_get_sync: ") +
            (gerror ? gerror->message : "no connection");
    if (gerror) {
      g_error_free(gerror);
    }
    return false;
  }

  proxy_ = g_dbus_proxy_new_sync(
      connection_, G_DBUS_PROXY_FLAGS_NONE, nullptr,
      "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.ScreenCast", nullptr, &gerror);
  if (!proxy_) {
    error = std::string("ScreenCast proxy: ") +
            (gerror ? gerror->message : "no proxy");
    if (gerror) {
      g_error_free(gerror);
    }
    Stop();
    return false;
  }

  if (!CreateSession(error) || !SelectSources(error) || !StartSession(error) ||
      !OpenPipeWireRemote(error) || !StartPipeWire(pw_fd_, target_, error)) {
    Stop();
    return false;
  }
  return true;
}

void PortalCapture::HandleParam(const struct spa_pod *param) {
  if (!param) {
    return;
  }
  struct spa_video_info_raw info;
  if (spa_format_video_raw_parse(param, &info) < 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(state_mutex_);
  width_ = info.size.width;
  height_ = info.size.height;
  format_ = info.format;
  SDL_Log("pipewire format: %dx%d spa_format=%d", width_, height_,
          static_cast<int>(format_));
}

void PortalCapture::HandleProcess() {
  struct pw_buffer *pw_buffer = pw_stream_dequeue_buffer(pw_stream_);
  if (!pw_buffer) {
    return;
  }
  spa_buffer *buffer = pw_buffer->buffer;
  spa_data *data = &buffer->datas[0];
  if (data->data && data->chunk) {
    int width = 0;
    int height = 0;
    spa_video_format format = SPA_VIDEO_FORMAT_UNKNOWN;
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      width = width_;
      height = height_;
      format = format_;
    }
    if (width > 0 && height > 0) {
      const int stride =
          data->chunk->stride > 0 ? data->chunk->stride : width * 4;
      const auto *src =
          static_cast<const uint8_t *>(data->data) + data->chunk->offset;
      Frame frame;
      frame.width = width;
      frame.height = height;
      frame.bgra =
          format == SPA_VIDEO_FORMAT_BGRx || format == SPA_VIDEO_FORMAT_BGRA;
      frame.capture_ns = NowNs();
      frame.pixels.resize(static_cast<size_t>(width) * height * 4);
      for (int y = 0; y < height; ++y) {
        std::memcpy(frame.pixels.data() + static_cast<size_t>(y) * width * 4,
                    src + static_cast<size_t>(y) * stride,
                    static_cast<size_t>(width) * 4);
      }
      {
        std::lock_guard<std::mutex> lock(frame_mutex_);
        latest_frame_ = std::move(frame);
      }
      frame_cv_.notify_one();
    } else {
      static bool warned = false;
      if (!warned) {
        SDL_Log(
            "pipewire buffer has no CPU mapping (dmabuf?); waiting for MemFd");
        warned = true;
      }
    }
  }
  pw_stream_queue_buffer(pw_stream_, pw_buffer);
}

void PortalCapture::OnStreamParam(void *userdata, uint32_t id,
                                  const struct spa_pod *param) {
  if (id == SPA_PARAM_Format) {
    static_cast<PortalCapture *>(userdata)->HandleParam(param);
  }
}

void PortalCapture::OnStreamProcess(void *userdata) {
  static_cast<PortalCapture *>(userdata)->HandleProcess();
}

bool PortalCapture::Read(Frame &frame, int timeout_ms) {
  std::unique_lock<std::mutex> lock(frame_mutex_);
  if (!frame_cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                          [this] { return latest_frame_.has_value(); })) {
    return false;
  }
  frame = std::move(*latest_frame_);
  latest_frame_.reset();
  return true;
}

void PortalCapture::Stop() {
  if (pw_loop_) {
    pw_main_loop_quit(pw_loop_);
  }
  if (pw_thread_.joinable()) {
    pw_thread_.join();
  }
  if (pw_stream_) {
    pw_stream_disconnect(pw_stream_);
    pw_stream_destroy(pw_stream_);
    pw_stream_ = nullptr;
  }
  if (pw_context_) {
    pw_context_destroy(pw_context_);
    pw_context_ = nullptr;
  }
  if (pw_loop_) {
    pw_main_loop_destroy(pw_loop_);
    pw_loop_ = nullptr;
  }
  if (pw_initialized_) {
    pw_deinit();
    pw_initialized_ = false;
  }

  if (connection_ && !session_handle_.empty()) {
    GVariant *reply = g_dbus_connection_call_sync(
        connection_, "org.freedesktop.portal.Desktop", session_handle_.c_str(),
        "org.freedesktop.portal.Session", "Close", nullptr, nullptr,
        G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
    if (reply) {
      g_variant_unref(reply);
    }
  }

  if (proxy_) {
    g_object_unref(proxy_);
    proxy_ = nullptr;
  }
  if (connection_) {
    g_object_unref(connection_);
    connection_ = nullptr;
  }
  session_handle_.clear();
  target_.clear();
  pw_fd_ = -1;
}
