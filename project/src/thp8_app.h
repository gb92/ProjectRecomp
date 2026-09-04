#pragma once

#include <rex/input/input.h>
#include <rex/rex_app.h>
#include <string_view>
#include <memory>

class THP8OptionsDialog;

/// Tony Hawk's Project 8 - ReXGlue Application
class THP8App : public rex::ReXApp {
public:
    using rex::ReXApp::ReXApp;

    static std::unique_ptr<rex::ui::WindowedApp> Create(
            rex::ui::WindowedAppContext& ctx) {
        return std::unique_ptr<THP8App>(
            new THP8App(ctx, "thp8", PPCImageConfig,
                        "[game_directory]"));
    }

    static bool OpenOptionsMenu();

protected:
    void OnPreSetup(rex::RuntimeConfig& config) override {
        config.gpu_plugin = "xenos";
    }

    void OnConfigurePaths(rex::PathConfig& paths) override;
    void OnLoadXexImage(std::string& xex_image) override {
        // The SDK will look for game:\default.xex by default.
        // THP8's XEX is also named default.xex so no override needed.
        (void)xex_image;
    }

    void OnPostSetup() override;
    void OnShutdown() override;
    void OnPreLaunchModule() override {}

private:
    void OpenOptionsMenuOnUIThread();

    THP8OptionsDialog* options_dialog_ = nullptr;
};
