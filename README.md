# Tony Hawk's Project 8 - Xbox 360 Static Recompilation

A project to statically recompile the original, unpatched Xbox 360 release of
Tony Hawk's Project 8 for PC using the [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk).
Title updates are intentionally unsupported so one executable layout remains
the source of truth for generated code and runtime fixes.

> [!IMPORTANT]
> **This repository and its releases do not contain Tony Hawk's Project 8 or
> any required game assets.** You must supply files from your own legally
> acquired Xbox 360 copy. Do not request, share, or link to copyrighted game
> files in issues, discussions, pull requests, or other project channels.

## Project Status

| Phase | Status | Details |
|-------|--------|---------|
| Windows toolchain | Done | Windows 10/11, Clang 18+, Ninja, Direct3D 12 |
| Linux toolchain | In progress | x86-64, Clang 18+, Ninja, Vulkan |
| ReXGlue integration | Done | v0.10.0 submodule |
| Base-XEX code generation | Done | Recovered function ranges and jump tables generate cleanly |
| Runtime | In progress | Boots, enters Career, and reaches gameplay |
| Frame pacing | In progress | 60 FPS mode works; intermittent CPU-side Vulkan replay bursts remain |

### Current Milestone

The base version (`0.0.0.1`) boots through ReXGlue, enters Career mode, and
reaches gameplay on Linux.

### Known Issues

- Intermittent frame-time bursts occur while deferred Vulkan commands are replayed on the CPU.
- The experimental 60 FPS mode still needs broader gameplay and timing validation.

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Windows 10/11 x86-64 | Primary | Direct3D 12; currently the most thoroughly tested target |
| Linux x86-64 | Experimental | Vulkan; reaches gameplay, but needs broader hardware and distribution testing |
| Linux ARM64 | Unsupported | ReXGlue has ARM64 support, but this project still applies x86-64-specific build flags |
| macOS | Unsupported | No maintained or tested graphics/build path currently exists |

x86-64 builds target the `x86-64-v2` instruction set. Graphics support depends
on a current driver capable of running ReXGlue's Direct3D 12 or Vulkan backend.
These requirements may change as broader compatibility testing is completed.

## Quick Start

### Prerequisites

- **Python ≥ 3.8**
- For development: **CMake ≥ 3.25**, **Clang ≥ 18**, **Ninja**, **Git**
- Your own original Xbox 360 copy of Tony Hawk's Project 8

Only the unmodified base executable revision `0.0.0.1` is supported. Title
updates, modified executables, and files from other platforms are not
compatible.

### Import Your Game

Extract your legally acquired Xbox 360 disc to a directory, then run:

```bash
python scripts/import_game.py "path/to/extracted/disc"
```

The importer validates `default.xex` against the supported base revision before
copying any files. It rejects title updates and installs the extracted game
atomically under `%USERPROFILE%\Games\ProjectRecomp` on Windows or
`${XDG_DATA_HOME:-~/.local/share}/projectrecomp/game` on Linux. Existing imports
are never replaced unless `--force` is supplied, and even then the tool refuses
to replace directories it did not create. Use `--dry-run` to validate without
copying or `--destination` for a portable/custom location.

Developers may instead keep the base `default.xex` at `private/default.xex` and
the extracted disc at `private/unpatched-game-full`.

Windows release installers include this import step directly in the setup
wizard and do not require Python. The installer validates the selected disc
folder before installing the game-free runtime to `Program Files\ProjectRecomp`.
It stores game data separately, defaulting to
`%USERPROFILE%\Games\ProjectRecomp`, and lets the user choose another drive.

To build the Windows installer after configuring the project, install
[Inno Setup 7](https://jrsoftware.org/isinfo.php) and run:

```powershell
scripts\build_windows_installer.ps1
```

### Build on Linux

```bash
# Initialize and build ReXGlue v0.10.0.
git submodule update --init --recursive tools/rexglue-sdk
cmake --preset linux-amd64 -S tools/rexglue-sdk
cmake --build tools/rexglue-sdk/out/build/linux-amd64 \
  --config Release --target install -j8

# Generate PPC sources from the unpatched base XEX.
tools/rexglue-sdk/out/install/linux-amd64/bin/rexglue \
  codegen config/THP8_rexglue.toml

# Configure and build.
# Project-specific ReXGlue compatibility patches are applied automatically.
cmake -S project -B project/build -G Ninja \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build project/build -j8
```

Use the `linux-arm64` preset and install path on ARM64.

### Graphics Profiles and Resolutions

The cross-platform launcher provides internal-resolution profiles while keeping
the guest's original 720p video mode:

```bash
# Original rendering with the ReXGlue default 4x anisotropic filtering.
scripts/run_thp8.py --profile original

# 2x internal rendering (1440p-class) and 16x anisotropic filtering.
scripts/run_thp8.py --profile 1440p

# 3x internal rendering (4K-class) and 16x anisotropic filtering.
scripts/run_thp8.py --profile 4k
```

Use `--output-resolution` independently when the guest and startup window
should observe a custom resolution. Window size can also be controlled without
changing the guest video mode:

```bash
scripts/run_thp8.py --profile 4k --output-resolution 3840x2160
scripts/run_thp8.py --profile 1440p --windowed --window-size 2560x1080
```

Pass `--cache-root` to reuse an existing save/cache directory. Additional
ReXGlue options may follow `--`.

THP8 normally misses every other 60 Hz guest vblank and renders at 30 FPS.
The launcher can experimentally expose a 120 Hz guest video mode, shortening
that wait and allowing approximately 60 rendered frames per second:

```bash
scripts/run_thp8.py --profile 1440p --fps 60
```

The default remains `--fps 30`. The 60 FPS mode still needs gameplay validation
for physics, animation, input, audio, and scripted-event timing.

On Linux, an opt-in smooth-VSync mode keeps ReXGlue's guest VSync worker
runnable between ticks. This can reduce scheduler wakeup jitter without
changing guest timing:

```bash
scripts/run_thp8.py --profile 1440p --smooth-vsync
```

This mode remains off by default because it trades additional scheduler
activity for steadier frame pacing.

### Frame-Pacing Harness

Install `python-evdev`, then record a complete startup-to-gameplay controller
trace:

```bash
scripts/frame-harness/record_input.py /dev/input/event15 \
  project/build/frame-harness/controller-trace.json --duration 150
```

Replay the trace through ReXGlue's internal SDL input driver and capture one
CSV row per guest swap:

```bash
scripts/frame-harness/replay_input.py \
  project/build/frame-harness/controller-trace.json \
  --perf-csv project/build/frame-harness/frame-pacing.csv -- \
  ./project/build/thp8 \
  --game_data_root private/unpatched-game-full \
  --cache_root project/build/cache
```

Replay does not require `uinput`; live SDL controller state is bypassed while
`REXGLUE_INPUT_REPLAY` is active.

## Directory Structure

```
thp8-recomp/
├── config/
│   └── THP8_rexglue.toml            # ReXGlue manifest and function ranges
├── docs/
│   └── recompilation-guide.md
├── generated/                       # ReXGlue codegen output (gitignored)
├── private/                         # Game files (gitignored)
│   ├── default.xex                  # Base version 0.0.0.1 executable
│   └── unpatched-game-full/         # Extracted disc contents
├── project/                         # Native executable and app hooks
├── scripts/                         # Build, launch, and profiling helpers
└── tools/rexglue-sdk/               # ReXGlue v0.10.0 submodule
```

## Key Facts (THP8-specific)

| Property | Value |
|----------|-------|
| Base address | `0x82000000` |
| Entry point | `0x823AB9A0` |
| Image size | 10.5 MB (0xA80000) |
| Code region | `0x82090000` - `0x826CD884` |
| Functions recompiled | 39,272 |
| Game engine | Neversoft (custom, NOT Unreal Engine 3) |
| Shader format | MATL container with D3D SM3.0 bytecode |
| Shaders found | 1,180 (in MaterialLibrary.bin.xen) |

## References

- [XenonRecomp](https://github.com/hedge-dev/XenonRecomp) — PPC → C++ recompiler
- [XenosRecomp](https://github.com/hedge-dev/XenosRecomp) — Xenos shader → HLSL recompiler
- [Unleashed Recompiled](https://github.com/hedge-dev/UnleashedRecomp) — Reference project (Sonic Unleashed)
- [Xenia](https://github.com/xenia-project/xenia) — Xbox 360 emulator (kernel/GPU reference)
- [docs/recompilation-guide.md](docs/recompilation-guide.md) — Detailed guide applicable to any Xbox 360 game

## Contributing and Support

Before opening an issue or pull request, read
[CONTRIBUTING.md](CONTRIBUTING.md). Use the provided issue forms and include
the requested platform, hardware, driver, build, and reproduction details.
Never attach or link to game files.

Security issues should be reported according to [SECURITY.md](SECURITY.md),
not through a public issue.

## License

ProjectRecomp's original code is available under the
[BSD 3-Clause License](LICENSE). This license applies only to material owned by
ProjectRecomp contributors. It does not grant rights to Tony Hawk's Project 8,
its assets, trademarks, or other third-party material.
