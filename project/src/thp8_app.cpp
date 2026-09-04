#include "thp8_app.h"
#include "thp8_main_options.h"
#include "thp8_main_menu.h"
#include "thp8_options_menu.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <string>

#include <rex/cvar.h>
#include <rex/filesystem.h>
#include <rex/logging.h>
#include <rex/ppc/context.h>
#include <rex/system/kernel_state.h>

REXCVAR_DEFINE_STRING(
    thp8_render_resolution, "original", "THP8",
    "Native guest render mode: original, 960x544, or 1280x720")
    .allowed({"original", "960x540", "960x544", "1280x720"})
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);

REXCVAR_DEFINE_BOOL(thp8_skip_intro_videos, true, "THP8",
                    "Skip the Activision, Neversoft, and intro movies")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

namespace {

#ifdef _WIN32
std::filesystem::path GetWindowsUserProfile() {
    wchar_t* value = nullptr;
    size_t value_size = 0;
    if (_wdupenv_s(&value, &value_size, L"USERPROFILE") != 0 ||
        value == nullptr) {
        return {};
    }
    const std::filesystem::path path(value);
    std::free(value);
    return path;
}
#endif

std::filesystem::path GetInstalledGamePath() {
#ifdef _WIN32
    const auto user_profile = GetWindowsUserProfile();
    return user_profile.empty()
               ? std::filesystem::path()
               : user_profile / "Games" / "ProjectRecomp";
#else
    if (const char* data_home = std::getenv("XDG_DATA_HOME");
        data_home != nullptr && *data_home != '\0') {
        return std::filesystem::path(data_home) / "projectrecomp" / "game";
    }
    if (const char* home = std::getenv("HOME");
        home != nullptr && *home != '\0') {
        return std::filesystem::path(home) / ".local" / "share" /
               "projectrecomp" / "game";
    }
#endif
    return {};
}

constexpr uint32_t kRenderDescriptorTable = 0x820178F8;
constexpr uint32_t kRenderDescriptorSize = 740;
constexpr uint32_t kSelectedRenderModeIndex = 0x827EFFE8;
constexpr uint32_t kRenderMode960x544NoFsaa = 5;
constexpr uint32_t kRenderMode1280x720NoFsaa = 11;
constexpr float kOriginalRenderWidth = 1040.0f;
constexpr float kOriginalRenderHeight = 584.0f;
constexpr float kLoadingWheelHalfSize = 96.0f;
constexpr uint32_t kMainMenuScriptChecksum = 0xFEB64820;
constexpr uint32_t kMainOptionsScriptChecksum = 0xA70D9A1D;
constexpr uint32_t kQuitToDashboardScriptChecksum = 0x83E7DF93;
constexpr uint32_t kOpenGraphicsOptionsScriptChecksum = 0xA9BA1467;
constexpr uint32_t kNullScriptChecksum = 0x0F7E902C;
constexpr size_t kMainMenuScriptSize = 1268;
constexpr size_t kMainOptionsScriptSize = 839;
constexpr std::array<uint8_t, 32> kMainMenuScriptSignature = {
    0x01, 0x43, 0xD0, 0x93, 0x2B, 0x82, 0x4C, 0x2E,
    0x00, 0x00, 0x00, 0x00, 0x55, 0x00, 0x49, 0x00,
    0x3A, 0x00, 0x20, 0x00, 0x75, 0x00, 0x69, 0x00,
    0x5F, 0x00, 0x63, 0x00, 0x72, 0x00, 0x65, 0x00,
};
constexpr std::array<uint8_t, 16> kMainMenuXboxItemSignature = {
    0x47, 0x66, 0x00, 0x43, 0x20, 0x15, 0x2B, 0x82,
    0x01, 0x16, 0xC9, 0xA1, 0x94, 0xE6, 0x03, 0x01,
};
constexpr std::array<uint8_t, 16> kMainMenuFreeSkateSignature = {
    0x16, 0xC9, 0xA1, 0x94, 0xE6, 0x03, 0x01, 0x16,
    0x38, 0x58, 0x74, 0xC4, 0x07, 0x4C, 0x16, 0x00,
};
constexpr std::array<uint8_t, 16> kMainMenuTailSignature = {
    0x47, 0x23, 0x00, 0x0E, 0x4B, 0x16, 0x18, 0xEB,
    0xFD, 0xFC, 0x07, 0x17, 0x01, 0x00, 0x00, 0x00,
};
struct NativeCommandResolution {
    uint32_t checksum;
    size_t retail_offset;
};

constexpr std::array kMainMenuNativeCommands{
    NativeCommandResolution{0x2DE8C60E, 0x001},  // Printf
    NativeCommandResolution{0xC5BC93EE, 0x043},  // ScreenElementExists
    NativeCommandResolution{0x3C15E9B6, 0x054},  // DestroyScreenElement
    NativeCommandResolution{0xBFA801DF, 0x12B},  // EnableUserMusic
    NativeCommandResolution{0x650D2C8E, 0x181},
    NativeCommandResolution{0x28122337, 0x1A3},
};

struct RenderModeOverride {
    uint32_t index;
    float width;
    float height;
};

thread_local bool g_adjust_loading_element_size = false;
thread_local bool g_adjust_loading_wheel = false;
THP8App* g_app = nullptr;

bool IsMainMenuScript(const uint8_t* script) {
    return std::equal(kMainMenuScriptSignature.begin(),
                      kMainMenuScriptSignature.end(), script) &&
           std::equal(kMainMenuXboxItemSignature.begin(),
                      kMainMenuXboxItemSignature.end(), script + 737) &&
           std::equal(kMainMenuFreeSkateSignature.begin(),
                      kMainMenuFreeSkateSignature.end(), script + 841) &&
           std::equal(kMainMenuTailSignature.begin(),
                      kMainMenuTailSignature.end(), script + 1213);
}

void InstallCustomMainMenuScript(uint8_t* script) {
    static_assert(kThp8MainMenuScript.size() <= kMainMenuScriptSize);
    auto custom_script = kThp8MainMenuScript;

    for (const auto& command : kMainMenuNativeCommands) {
        if (script[command.retail_offset] != 0x43) {
            REXLOG_ERROR("THP8 main menu command {:#010x} was not resolved",
                         command.checksum);
            return;
        }

        const uint8_t* pointer = script + command.retail_offset + 1;
        for (size_t offset = 0; offset + 5 <= custom_script.size(); ++offset) {
            uint32_t checksum;
            std::memcpy(&checksum, custom_script.data() + offset + 1,
                        sizeof(checksum));
            if (custom_script[offset] == 0x16 &&
                checksum == command.checksum) {
                custom_script[offset] = 0x43;
                std::memcpy(custom_script.data() + offset + 1, pointer,
                            sizeof(uint32_t));
            }
        }
    }

    std::fill_n(script, kMainMenuScriptSize, uint8_t{});
    std::copy(custom_script.begin(), custom_script.end(), script);
}

uint32_t FindNativeCommand(uint8_t* base, uint32_t checksum) {
    const uint32_t table = REX_LOAD_U32(0x8274A4B4);
    if (!table) {
        return 0;
    }

    uint32_t entry =
        REX_LOAD_U32(table + ((checksum & 0x7FFF) * sizeof(uint32_t)));
    while (entry) {
        if (REX_LOAD_U32(entry + 4) == checksum) {
            return REX_LOAD_U8(entry + 2) == 8
                       ? REX_LOAD_U32(entry + 12)
                       : 0;
        }
        entry = REX_LOAD_U32(entry + 16);
    }
    return 0;
}

bool ResolveNativeCommands(uint8_t* base, std::span<uint8_t> script) {
    constexpr std::array<uint32_t, 4> kCommands{
        0x3B4631DF,  // IsPS3
        0x3E7727FA,  // IsXenon
        0x64946516,  // CheckForSignIn
        0x8E55AF45,  // GetGlobalFlag
    };
    for (const uint32_t checksum : kCommands) {
        const uint32_t function = FindNativeCommand(base, checksum);
        if (!function) {
            continue;
        }
        for (size_t offset = 0; offset + 5 <= script.size(); ++offset) {
            uint32_t candidate;
            std::memcpy(&candidate, script.data() + offset + 1,
                        sizeof(candidate));
            if (script[offset] == 0x16 && candidate == checksum) {
                script[offset] = 0x43;
                std::memcpy(script.data() + offset + 1, &function,
                            sizeof(function));
            }
        }
    }
    return true;
}

void InstallCustomMainOptionsScript(uint8_t* base, uint8_t* script) {
    static_assert(kThp8MainOptionsScript.size() <= kMainOptionsScriptSize);
    auto custom_script = kThp8MainOptionsScript;
    ResolveNativeCommands(base, custom_script);
    std::fill_n(script, kMainOptionsScriptSize, uint8_t{});
    std::copy(custom_script.begin(), custom_script.end(), script);
}

std::optional<RenderModeOverride> GetRenderModeOverride() {
    const std::string resolution = REXCVAR_GET(thp8_render_resolution);
    if (resolution == "960x540" || resolution == "960x544") {
        return RenderModeOverride{kRenderMode960x544NoFsaa, 960.0f, 544.0f};
    }
    if (resolution == "1280x720") {
        return RenderModeOverride{kRenderMode1280x720NoFsaa, 1280.0f, 720.0f};
    }
    return std::nullopt;
}

void AdjustLoadingScreenPosition(PPCContext& ctx, bool loading_wheel) {
    const auto mode = GetRenderModeOverride();
    if (!mode) {
        return;
    }

    ctx.f1.f64 = static_cast<float>(ctx.f1.f64) *
                 mode->width / kOriginalRenderWidth;
    ctx.f2.f64 = static_cast<float>(ctx.f2.f64) *
                 mode->height / kOriginalRenderHeight;
    if (loading_wheel) {
        ctx.f1.f64 +=
            kLoadingWheelHalfSize *
            (mode->width / kOriginalRenderWidth - 1.0f);
        ctx.f2.f64 +=
            kLoadingWheelHalfSize *
            (mode->height / kOriginalRenderHeight - 1.0f);
    }
}

void AdjustLoadingElementSize(PPCContext& ctx, uint8_t* base) {
    if (!g_adjust_loading_element_size) {
        return;
    }

    const auto mode = GetRenderModeOverride();
    if (!mode) {
        return;
    }

    const float width = static_cast<float>(ctx.f1.f64);
    const float height = static_cast<float>(ctx.f2.f64);
    const float scaled_width = width * mode->width / kOriginalRenderWidth;
    const float scaled_height = height * mode->height / kOriginalRenderHeight;
    if (g_adjust_loading_wheel) {
        const uint32_t position = ctx.r4.u32;
        const float x = std::bit_cast<float>(REX_LOAD_U32(position));
        const float y = std::bit_cast<float>(REX_LOAD_U32(position + 4));
        REX_STORE_U32(
            position,
            std::bit_cast<uint32_t>(x - (scaled_width - width) * 0.5f));
        REX_STORE_U32(
            position + 4,
            std::bit_cast<uint32_t>(y - (scaled_height - height) * 0.5f));
    }
    ctx.f1.f64 = scaled_width;
    ctx.f2.f64 = scaled_height;
}

}  // namespace

void THP8App::OnConfigurePaths(rex::PathConfig& paths) {
    if (!paths.game_data_root.empty()) {
        return;
    }

    const std::filesystem::path executable_dir =
        rex::filesystem::GetExecutableFolder();
    const std::array candidates{
        executable_dir / "game",
        executable_dir / "game_data",
        GetInstalledGamePath(),
        executable_dir,
        executable_dir / ".." / ".." / ".." / ".." / "private" /
            "unpatched-game-full",
    };
    for (const auto& candidate : candidates) {
        if (!candidate.empty() &&
            std::filesystem::is_regular_file(candidate / "default.xex")) {
            paths.game_data_root = std::filesystem::weakly_canonical(candidate);
            return;
        }
    }
}

void THP8App::OnPostSetup() {
    g_app = this;
}

void THP8App::OnShutdown() {
    SetTHP8OptionsMenuOpen(false);
    delete options_dialog_;
    options_dialog_ = nullptr;
    g_app = nullptr;
}

bool THP8App::OpenOptionsMenu() {
    if (!g_app || IsTHP8OptionsMenuOpen()) {
        return IsTHP8OptionsMenuOpen();
    }
    SetTHP8OptionsMenuOpen(true);
    if (!g_app->app_context().CallInUIThread(
            [] { g_app->OpenOptionsMenuOnUIThread(); })) {
        SetTHP8OptionsMenuOpen(false);
        return false;
    }
    return true;
}

void THP8App::OpenOptionsMenuOnUIThread() {
    if (options_dialog_) {
        return;
    }
    if (!imgui_drawer()) {
        SetTHP8OptionsMenuOpen(false);
        return;
    }
    options_dialog_ = new THP8OptionsDialog(
        imgui_drawer(), rex::filesystem::GetExecutableFolder() / "thp8.toml",
        [](rex::input::X_INPUT_STATE& state) {
            state.gamepad.buttons = GetTHP8OptionsMenuButtons();
            return true;
        },
        [this] {
            options_dialog_ = nullptr;
            SetTHP8OptionsMenuOpen(false);
        });
}

extern "C" REX_FUNC(__imp__sub_8235F2A8);
extern "C" REX_FUNC(__imp__sub_82303FA0);
extern "C" REX_FUNC(__imp__sub_82303FB8);
extern "C" REX_FUNC(__imp__sub_82310958);
extern "C" REX_FUNC(__imp__sub_823327E8);
extern "C" REX_FUNC(__imp__sub_823329A8);
extern "C" REX_FUNC(__imp__sub_82297400);
extern "C" REX_FUNC(__imp__sub_822110D0);
extern "C" REX_FUNC(__imp__sub_823ABCE8);
extern "C" REX_FUNC(sub_822126A0);

extern "C" REX_FUNC(sub_8235F2A8) {
    REX_FUNC_PROLOGUE();
    const uint32_t output = ctx.r3.u32;
    __imp__sub_8235F2A8(ctx, base);

    const std::string resolution = REXCVAR_GET(thp8_render_resolution);
    if (resolution == "original") {
        return;
    }

    const auto mode = GetRenderModeOverride();
    if (!mode) {
        REXLOG_ERROR("Unsupported THP8 render resolution: {}", resolution);
        return;
    }

    const uint32_t descriptor =
        kRenderDescriptorTable + mode->index * kRenderDescriptorSize;
    REX_STORE_U32(output, REX_LOAD_U32(descriptor + 4));
    REX_STORE_U32(output + 4, REX_LOAD_U32(descriptor + 8));
    REX_STORE_U32(output + 16, REX_LOAD_U32(descriptor + 12));
    REX_STORE_U32(kSelectedRenderModeIndex, mode->index);
    REXLOG_INFO("Selected THP8 native render mode {}", resolution);
}

extern "C" REX_FUNC(sub_82303FA0) {
    REX_FUNC_PROLOGUE();
    AdjustLoadingScreenPosition(ctx, true);
    __imp__sub_82303FA0(ctx, base);
}

extern "C" REX_FUNC(sub_82303FB8) {
    REX_FUNC_PROLOGUE();
    AdjustLoadingScreenPosition(ctx, false);
    __imp__sub_82303FB8(ctx, base);
}

extern "C" REX_FUNC(sub_82310958) {
    REX_FUNC_PROLOGUE();
    AdjustLoadingElementSize(ctx, base);
    __imp__sub_82310958(ctx, base);
}

extern "C" REX_FUNC(sub_823327E8) {
    REX_FUNC_PROLOGUE();
    g_adjust_loading_element_size = true;
    g_adjust_loading_wheel = true;
    __imp__sub_823327E8(ctx, base);
    g_adjust_loading_wheel = false;
    g_adjust_loading_element_size = false;
}

extern "C" REX_FUNC(sub_823329A8) {
    REX_FUNC_PROLOGUE();
    g_adjust_loading_element_size = true;
    __imp__sub_823329A8(ctx, base);
    g_adjust_loading_element_size = false;
}

extern "C" REX_FUNC(sub_82297400) {
    REX_FUNC_PROLOGUE();

    if (REXCVAR_GET(thp8_skip_intro_videos)) {
        constexpr uint32_t kMovieParameter = 0xE2A10D90;
        PPCContext query = ctx;
        const uint32_t result_address = ctx.r1.u32 - 16;
        REX_STORE_U32(result_address, 0);
        query.r4.u64 = kMovieParameter;
        query.r5.u64 = result_address;
        query.r6.u64 = 0;
        sub_822126A0(query, base);
        if (query.r3.u32) {
            const uint32_t movie_address = REX_LOAD_U32(result_address);
            const char* movie =
                reinterpret_cast<const char*>(base + movie_address);
            std::string movie_name(movie);
            std::transform(
                movie_name.begin(), movie_name.end(), movie_name.begin(),
                [](unsigned char value) { return std::tolower(value); });
            if (movie_name == "atvi" || movie_name == "intro" ||
                movie_name.find("ns_logo") != std::string::npos ||
                movie_name.find("neversoft") != std::string::npos) {
                ctx.r3.u64 = 1;
                return;
            }
        }
    }

    __imp__sub_82297400(ctx, base);
}

extern "C" REX_FUNC(sub_822110D0) {
    REX_FUNC_PROLOGUE();
    const uint32_t checksum = ctx.r4.u32;
    if (checksum == kOpenGraphicsOptionsScriptChecksum) {
        THP8App::OpenOptionsMenu();
        ctx.r4.u64 = kNullScriptChecksum;
    }
    __imp__sub_822110D0(ctx, base);

    if (checksum == kMainMenuScriptChecksum && ctx.r3.u32) {
        uint8_t* script = base + ctx.r3.u32;
        if (IsMainMenuScript(script)) {
            InstallCustomMainMenuScript(script);
            REXLOG_INFO("Installed THP8 custom main menu during QB lookup");
        }
    } else if (checksum == kMainOptionsScriptChecksum && ctx.r3.u32) {
        InstallCustomMainOptionsScript(base, base + ctx.r3.u32);
        REXLOG_INFO("Installed THP8 custom OPTIONS menu during QB lookup");
    } else if (checksum == kQuitToDashboardScriptChecksum) {
        rex::system::kernel_state()->TerminateTitle();
    }
}

extern "C" REX_FUNC(sub_823ABCE8) {
    REX_FUNC_PROLOGUE();
    const uint32_t state_address = ctx.r4.u32;
    __imp__sub_823ABCE8(ctx, base);
    if (IsTHP8OptionsMenuOpen() && ctx.r3.u32 == 0 && state_address) {
        SetTHP8OptionsMenuButtons(REX_LOAD_U16(state_address + 4));
        std::fill_n(base + state_address + 4, 12, uint8_t{});
    }
}
