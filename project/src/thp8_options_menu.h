#pragma once

#include <cstdint>
#include <filesystem>
#include <functional>

#include <rex/input/input.h>
#include <rex/ui/imgui_dialog.h>

namespace rex::ui {
class ImGuiDrawer;
}

class THP8OptionsDialog final : public rex::ui::ImGuiDialog {
public:
    using PollInput = std::function<bool(rex::input::X_INPUT_STATE&)>;
    using Closed = std::function<void()>;

    THP8OptionsDialog(rex::ui::ImGuiDrawer* drawer,
                     std::filesystem::path config_path,
                     PollInput poll_input, Closed closed);

protected:
    void OnDraw(ImGuiIO& io) override;
    void OnClose() override;

private:
    void ChangeSelection(int direction);
    void ChangeValue(int direction);
    void Save();

    std::filesystem::path config_path_;
    PollInput poll_input_;
    Closed closed_;
    uint16_t previous_buttons_ = 0;
    bool input_armed_ = false;
    int selected_ = 0;
};

bool IsTHP8OptionsMenuOpen();
void SetTHP8OptionsMenuOpen(bool open);
uint16_t GetTHP8OptionsMenuButtons();
void SetTHP8OptionsMenuButtons(uint16_t buttons);
