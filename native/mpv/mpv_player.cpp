// ScreenPlayer macOS libmpv backend. Software render API keeps the texture
// independent of Godot's Metal/OpenGL device. All Godot calls run on main thread.
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <mpv/client.h>
#include <mpv/render.h>
#include <algorithm>
#include <cmath>

using namespace godot;

class MPVPlayer : public Node {
    GDCLASS(MPVPlayer, Node)
    mpv_handle *handle = nullptr;
    mpv_render_context *renderer = nullptr;
    Ref<ImageTexture> texture;
    PackedByteArray pixels;
    int width = 0, height = 0;
    bool active = false;
    void property(const char *name, const String &value) {
        if (handle) check(mpv_set_property_string(handle, name, value.utf8().get_data()));
    }
    void check(int result) {
        if (result < 0) UtilityFunctions::push_warning(String("libmpv: ") + mpv_error_string(result));
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("initialize"), &MPVPlayer::initialize);
        ClassDB::bind_method(D_METHOD("load_file", "path", "headers", "yt_dlp"), &MPVPlayer::load_file);
        ClassDB::bind_method(D_METHOD("play"), &MPVPlayer::play);
        ClassDB::bind_method(D_METHOD("pause"), &MPVPlayer::pause);
        ClassDB::bind_method(D_METHOD("stop"), &MPVPlayer::stop);
        ClassDB::bind_method(D_METHOD("set_time_pos", "seconds"), &MPVPlayer::set_time_pos);
        ClassDB::bind_method(D_METHOD("seek_content_pos", "seconds"), &MPVPlayer::seek_content_pos);
        ClassDB::bind_method(D_METHOD("set_volume", "volume"), &MPVPlayer::set_volume);
        ClassDB::bind_method(D_METHOD("set_repeat_file", "repeat"), &MPVPlayer::set_repeat_file);
        ClassDB::bind_method(D_METHOD("set_playback_speed", "speed"), &MPVPlayer::set_playback_speed);
        ClassDB::bind_method(D_METHOD("get_duration"), &MPVPlayer::get_duration);
        ClassDB::bind_method(D_METHOD("get_volume"), &MPVPlayer::get_volume);
        ClassDB::bind_method(D_METHOD("get_texture"), &MPVPlayer::get_texture);
        ClassDB::bind_method(D_METHOD("get_width"), &MPVPlayer::get_width);
        ClassDB::bind_method(D_METHOD("get_height"), &MPVPlayer::get_height);
        ADD_SIGNAL(MethodInfo("texture_updated", PropertyInfo(Variant::OBJECT, "texture", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D")));
        ADD_SIGNAL(MethodInfo("time_changed", PropertyInfo(Variant::FLOAT, "time_pos")));
        ADD_SIGNAL(MethodInfo("playback_ended"));
    }
public:
    ~MPVPlayer() override {
        if (renderer) mpv_render_context_free(renderer);
        if (handle) mpv_terminate_destroy(handle);
    }
    bool initialize() {
        if (handle) return renderer != nullptr;
        handle = mpv_create();
        if (!handle) return false;
        mpv_set_option_string(handle, "config", "no");
        mpv_set_option_string(handle, "terminal", "no");
        mpv_set_option_string(handle, "vo", "libmpv");
        mpv_set_option_string(handle, "hwdec", "auto-copy");
        mpv_set_option_string(handle, "keep-open", "yes");
        mpv_set_option_string(handle, "idle", "yes");
        mpv_set_option_string(handle, "input-default-bindings", "no");
        mpv_set_option_string(handle, "input-vo-keyboard", "no");
        int result = mpv_initialize(handle);
        if (result >= 0) {
            mpv_render_param params[] = {
                {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_SW)},
                {MPV_RENDER_PARAM_INVALID, nullptr}
            };
            result = mpv_render_context_create(&renderer, handle, params);
        }
        if (result < 0) {
            check(result);
            mpv_terminate_destroy(handle);
            handle = nullptr;
            return false;
        }
        mpv_observe_property(handle, 1, "time-pos", MPV_FORMAT_DOUBLE);
        mpv_observe_property(handle, 2, "eof-reached", MPV_FORMAT_FLAG);
        set_process(true);
        return true;
    }
    void load_file(String path, String headers, String yt_dlp) {
        if (!handle) return;
        // Stop and drain queued events so the previous file cannot update a new slot.
        stop();
        property("http-header-fields", headers);
        if (!yt_dlp.is_empty()) property("script-opts", "ytdl_hook-ytdl_path=" + yt_dlp);
        CharString file = path.utf8();
        const char *cmd[] = {"loadfile", file.get_data(), "replace", nullptr};
        active = mpv_command(handle, cmd) >= 0;
        if (!active) UtilityFunctions::push_warning("libmpv: failed to load " + path);
    }
    void play() { property("pause", "no"); }
    void pause() { property("pause", "yes"); }
    void stop() {
        if (!handle) return;
        active = false;
        const char *cmd[] = {"stop", nullptr};
        check(mpv_command(handle, cmd));
        while (mpv_wait_event(handle, 0)->event_id != MPV_EVENT_NONE) {}
    }
    void set_time_pos(double seconds) {
        if (!handle || !std::isfinite(seconds)) return;
        const CharString value = String::num_real(std::max(0.0, seconds)).utf8();
        const char *cmd[] = {"seek", value.get_data(), "absolute+exact", nullptr};
        check(mpv_command(handle, cmd));
    }
    void seek_content_pos(String seconds) { set_time_pos(seconds.to_float()); }
    void set_volume(String value) { property("volume", value); }
    void set_repeat_file(String value) { property("loop-file", value); }
    void set_playback_speed(String value) { property("speed", value); }
    double get_duration() const {
        double value = 0;
        if (handle) mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &value);
        return value;
    }
    Ref<ImageTexture> get_texture() const { return texture; }
    double get_volume() const {
        double value = 0;
        if (handle) mpv_get_property(handle, "volume", MPV_FORMAT_DOUBLE, &value);
        return value;
    }
    int get_width() const { return width; }
    int get_height() const { return height; }
    void _process(double) override {
        if (!handle || !renderer) return;
        for (int i = 0; i < 128; ++i) {
            mpv_event *event = mpv_wait_event(handle, 0);
            if (event->event_id == MPV_EVENT_NONE) break;
            if (!active || event->event_id != MPV_EVENT_PROPERTY_CHANGE) continue;
            auto *p = static_cast<mpv_event_property *>(event->data);
            if (!p->data) continue;
            if (event->reply_userdata == 1 && p->format == MPV_FORMAT_DOUBLE)
                emit_signal("time_changed", *static_cast<double *>(p->data));
            if (event->reply_userdata == 2 && p->format == MPV_FORMAT_FLAG && *static_cast<int *>(p->data))
                emit_signal("playback_ended");
        }
        uint64_t flags = mpv_render_context_update(renderer);
        if (!active || !(flags & MPV_RENDER_UPDATE_FRAME)) return;
        int64_t w = 0, h = 0;
        mpv_get_property(handle, "dwidth", MPV_FORMAT_INT64, &w);
        mpv_get_property(handle, "dheight", MPV_FORMAT_INT64, &h);
        if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return;
        // Use display dimensions to preserve pixel aspect ratio and source detail.
        int size[] = {int(w), int(h)};
        bool changed = width != size[0] || height != size[1];
        width = size[0]; height = size[1];
        pixels.resize(int64_t(width) * height * 4);
        size_t stride = size_t(width) * 4;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_SW_SIZE, size},
            {MPV_RENDER_PARAM_SW_FORMAT, const_cast<char *>("rgb0")},
            {MPV_RENDER_PARAM_SW_STRIDE, &stride},
            {MPV_RENDER_PARAM_SW_POINTER, pixels.ptrw()},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };
        int result = mpv_render_context_render(renderer, params);
        if (result < 0) { check(result); return; }
        uint8_t *rgba = pixels.ptrw();
        for (int64_t i = 3; i < pixels.size(); i += 4) rgba[i] = 255;
        Ref<Image> image = Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, pixels);
        if (texture.is_null()) texture = ImageTexture::create_from_image(image);
        else if (changed) texture->set_image(image);
        else texture->update(image);
        emit_signal("texture_updated", texture);
    }
};

static void initialize_module(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<MPVPlayer>();
}
static void uninitialize_module(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT godot_mpv_library_init(
    GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_module);
    init.register_terminator(uninitialize_module);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
