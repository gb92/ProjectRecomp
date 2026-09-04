#include "thp8_options_menu.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <format>
#include <string>
#include <string_view>

#include <imgui.h>
#include <rex/cvar.h>

namespace {

std::atomic_bool g_options_menu_open = false;
std::atomic_uint16_t g_options_menu_buttons = 0;

constexpr std::array<std::string_view, 5> kOutputResolutions{
    "", "1280x720", "1920x1080", "2560x1440", "3840x2160"};
constexpr std::array<std::string_view, 3> kNativeResolutions{
    "original", "960x544", "1280x720"};
constexpr std::array<int, 7> kAnisotropicValues{-1, 0, 1, 2, 3, 4, 5};
constexpr std::array<std::string_view, 7> kAnisotropicLabels{
    "GAME DEFAULT", "OFF", "1X", "2X", "4X", "8X", "16X"};
constexpr std::array<std::string_view, 6> kLabels{
    "OUTPUT RESOLUTION", "THP8 RENDER RESOLUTION", "INTERNAL SCALE",
    "ANISOTROPIC FILTERING", "FULLSCREEN", "VSYNC"};

template <typename T, size_t Size>
size_t FindValue(const std::array<T, Size>& values, const T& value) {
    const auto it = std::find(values.begin(), values.end(), value);
    return it == values.end() ? 0 : static_cast<size_t>(it - values.begin());
}

template <typename T, size_t Size>
T StepValue(const std::array<T, Size>& values, const T& current, int direction) {
    const size_t index = FindValue(values, current);
    const size_t next =
        (index + Size + (direction < 0 ? Size - 1 : 1)) % Size;
    return values[next];
}

std::string BoolLabel(bool value) {
    return value ? "ON" : "OFF";
}

std::string CurrentValue(int row) {
    switch (row) {
    case 0: {
        const std::string value =
            rex::cvar::Query<std::string>("resolution");
        return value.empty() ? "DESKTOP" : value;
    }
    case 1:
        return rex::cvar::Query<std::string>("thp8_render_resolution");
    case 2:
        return std::format("{}X",
                           rex::cvar::Query<int32_t>("resolution_scale"));
    case 3: {
        const int value =
            rex::cvar::Query<int32_t>("anisotropic_override");
        const size_t index = FindValue(kAnisotropicValues, value);
        return std::string(kAnisotropicLabels[index]);
    }
    case 4:
        return BoolLabel(rex::cvar::Query<bool>("fullscreen"));
    case 5:
        return BoolLabel(rex::cvar::Query<bool>("vsync"));
    default:
        return {};
    }
}

}  // namespace

THP8OptionsDialog::THP8OptionsDialog(
        rex::ui::ImGuiDrawer* drawer, std::filesystem::path config_path,
        PollInput poll_input, Closed closed)
    : ImGuiDialog(drawer),
      config_path_(std::move(config_path)),
      poll_input_(std::move(poll_input)),
      closed_(std::move(closed)) {}

void THP8OptionsDialog::ChangeSelection(int direction) {
    selected_ = (selected_ + static_cast<int>(kLabels.size()) + direction) %
                static_cast<int>(kLabels.size());
}

void THP8OptionsDialog::ChangeValue(int direction) {
    switch (selected_) {
    case 0: {
        const std::string current =
            rex::cvar::Query<std::string>("resolution");
        rex::cvar::SetFlagByName(
            "resolution",
            std::string(StepValue(kOutputResolutions, std::string_view(current),
                                  direction)));
        break;
    }
    case 1: {
        const std::string current =
            rex::cvar::Query<std::string>("thp8_render_resolution");
        rex::cvar::SetFlagByName(
            "thp8_render_resolution",
            std::string(StepValue(kNativeResolutions,
                                  std::string_view(current), direction)));
        break;
    }
    case 2: {
        int value = rex::cvar::Query<int32_t>("resolution_scale");
        value += direction < 0 ? -1 : 1;
        if (value < 1) value = 4;
        if (value > 4) value = 1;
        rex::cvar::SetFlagByName("resolution_scale",
                                 std::to_string(value));
        break;
    }
    case 3: {
        const int current =
            rex::cvar::Query<int32_t>("anisotropic_override");
        rex::cvar::SetFlagByName(
            "anisotropic_override",
            std::to_string(StepValue(kAnisotropicValues, current, direction)));
        break;
    }
    case 4:
        rex::cvar::SetFlagByName(
            "fullscreen",
            rex::cvar::Query<bool>("fullscreen") ? "false" : "true");
        break;
    case 5:
        rex::cvar::SetFlagByName(
            "vsync", rex::cvar::Query<bool>("vsync") ? "false" : "true");
        break;
    }
    Save();
}

void THP8OptionsDialog::Save() {
    rex::cvar::SaveConfig(config_path_);
}

void THP8OptionsDialog::OnDraw(ImGuiIO& io) {
    ImGui::SetCurrentContext(imgui_drawer()->GetContext());
    uint16_t buttons = 0;
    rex::input::X_INPUT_STATE state{};
    if (poll_input_ && poll_input_(state)) {
        buttons = state.gamepad.buttons;
    }
    if (!input_armed_ && buttons == 0) {
        input_armed_ = true;
    }
    const uint16_t pressed =
        input_armed_ ? buttons & ~previous_buttons_ : uint16_t{};
    previous_buttons_ = buttons;

    const bool up = (pressed & rex::input::X_INPUT_GAMEPAD_DPAD_UP) ||
                    ImGui::IsKeyPressed(ImGuiKey_UpArrow);
    const bool down = (pressed & rex::input::X_INPUT_GAMEPAD_DPAD_DOWN) ||
                      ImGui::IsKeyPressed(ImGuiKey_DownArrow);
    const bool left = (pressed & rex::input::X_INPUT_GAMEPAD_DPAD_LEFT) ||
                      ImGui::IsKeyPressed(ImGuiKey_LeftArrow);
    const bool right = (pressed & rex::input::X_INPUT_GAMEPAD_DPAD_RIGHT) ||
                       ImGui::IsKeyPressed(ImGuiKey_RightArrow);
    const bool choose = (pressed & rex::input::X_INPUT_GAMEPAD_A) ||
                        ImGui::IsKeyPressed(ImGuiKey_Enter);
    const bool back = (pressed & rex::input::X_INPUT_GAMEPAD_B) ||
                      ImGui::IsKeyPressed(ImGuiKey_Escape);

    if (up) ChangeSelection(-1);
    if (down) ChangeSelection(1);
    if (left) ChangeValue(-1);
    if (right || choose) ChangeValue(1);
    if (back) {
        Save();
        Close();
        return;
    }

    const ImVec2 size = io.DisplaySize;
    const float scale = std::clamp(size.y / 720.0f, 0.75f, 1.5f);
    const ImVec2 panel_size(std::min(size.x * 0.72f, 880.0f * scale),
                            500.0f * scale);
    ImGui::SetNextWindowPos(
        ImVec2((size.x - panel_size.x) * 0.5f,
               (size.y - panel_size.y) * 0.5f),
        ImGuiCond_Always);
    ImGui::SetNextWindowSize(panel_size, ImGuiCond_Always);
    ImGui::SetNextWindowBgAlpha(0.96f);
    constexpr ImGuiWindowFlags kWindowFlags =
        ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings |
        ImGuiWindowFlags_NoNav;
    ImGui::Begin("GRAPHICS OPTIONS", nullptr, kWindowFlags);
    ImGui::SetWindowFontScale(scale);

    for (int row = 0; row < static_cast<int>(kLabels.size()); ++row) {
        const std::string label =
            std::format("{}     <  {}  >", kLabels[row], CurrentValue(row));
        ImGui::PushStyleColor(
            ImGuiCol_Button,
            row == selected_ ? ImVec4(0.68f, 0.045f, 0.06f, 0.95f)
                            : ImVec4(0.12f, 0.13f, 0.16f, 0.9f));
        ImGui::PushID(row);
        if (ImGui::Button(label.c_str(), ImVec2(-1.0f, 48.0f * scale))) {
            selected_ = row;
            ChangeValue(1);
        } else if (ImGui::IsItemHovered()) {
            selected_ = row;
        }
        ImGui::PopID();
        ImGui::PopStyleColor();
    }
    ImGui::TextDisabled(
        "D-PAD  NAVIGATE / CHANGE     A  SELECT     B  BACK");
    ImGui::TextDisabled(
        "OUTPUT RESOLUTION, RENDER RESOLUTION, AND SCALE REQUIRE A RESTART");
    ImGui::End();
}

void THP8OptionsDialog::OnClose() {
    if (closed_) closed_();
}

bool IsTHP8OptionsMenuOpen() {
    return g_options_menu_open.load(std::memory_order_acquire);
}

void SetTHP8OptionsMenuOpen(bool open) {
    g_options_menu_open.store(open, std::memory_order_release);
    if (!open) {
        g_options_menu_buttons.store(0, std::memory_order_release);
    }
}

uint16_t GetTHP8OptionsMenuButtons() {
    return g_options_menu_buttons.load(std::memory_order_acquire);
}

void SetTHP8OptionsMenuButtons(uint16_t buttons) {
    g_options_menu_buttons.store(buttons, std::memory_order_release);
}
