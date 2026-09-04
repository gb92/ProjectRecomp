# ProjectRecomp ReXGlue Workflow

This document explains how Tony Hawk's Project 8 was brought up on
[ReXGlue](https://github.com/rexglue/rexglue-sdk), how the current source tree
fits together, and how to reproduce the generated code and native runtime.

ProjectRecomp does not distribute the game executable or game assets. You must
provide an extracted Xbox 360 retail disc. Only the unpatched base executable is
supported:

| Property | Value |
|----------|-------|
| Title | Tony Hawk's Project 8 |
| Platform | Xbox 360 |
| Executable revision | `0.0.0.1` |
| `default.xex` size | 8,237,056 bytes |
| `default.xex` SHA-256 | `CFC732340E55DEFDA400E25F03231AA9BB65FD9545B618212F69A4952384A5DD` |
| Image base | `0x82000000` |
| Entry point | `0x823AB9A0` |

Title updates are intentionally unsupported. THP8's known title update imposes
an internal 30 FPS cap, and ReXGlue automatically applies a `default.xexp`
located beside `default.xex`. Remove or rename that file before code generation
or launch.

## 1. What ReXGlue Provides

Static recompilation converts the title's PowerPC code to native C++ ahead of
time. The generated code still expects an Xbox 360 execution environment.
ReXGlue supplies that environment:

- XEX loading and guest-memory management
- Xbox kernel and XAM services
- virtual file-system mappings such as `game:\`
- threads, events, critical sections, and TLS
- SDL input and audio
- XMA decoding
- Xenos command processing and runtime shader translation
- Direct3D 12 and Vulkan presentation
- configuration, logging, and host UI support

The active project therefore consists of three layers:

1. **Generated guest code** in `generated/`, produced from the user's XEX.
2. **ReXGlue** in `tools/rexglue-sdk/`, pinned to a known commit and patched
   reproducibly.
3. **THP8 integration code** in `project/`, which configures ReXGlue and
   overrides selected guest functions.

The former hand-written runtime, checked-in XenonRecomp output, XenosRecomp
workspace, and one-time XEX-analysis helpers are not part of the current build.

## 2. Repository Layout

```text
ProjectRecomp/
├── config/
│   └── THP8_rexglue.toml       # ReXGlue codegen manifest
├── generated/                  # Codegen output; ignored by Git
├── patches/
│   └── rexglue-v0.10.0/        # Ordered SDK compatibility patches
├── private/                    # User-owned game files; ignored by Git
│   └── unpatched-game-full/
│       ├── default.xex
│       └── DATA/
├── project/
│   ├── assets/                 # Project-authored QB replacements
│   ├── src/                    # ReXGlue app and guest overrides
│   └── CMakeLists.txt
├── scripts/
│   ├── apply-rexglue-patches.sh
│   ├── import_game.py
│   └── run_thp8.py
└── tools/
    └── rexglue-sdk/             # The only required submodule
```

`generated/` is intentionally excluded from Git because it is large and is
derived from copyrighted input. A source build requires the contributor to run
codegen against their own supported XEX.

## 3. Prepare the Game

Extract your legally acquired Xbox 360 disc with a tool such as
[`extract-xiso`](https://github.com/XboxDev/extract-xiso) or
[`xdvdfs`](https://crates.io/crates/xdvdfs-cli). For development, use this
layout:

```text
private/unpatched-game-full/
├── default.xex
└── DATA/
```

Do not place `default.xexp` beside the executable. Validate the extracted game
with the project importer:

```bash
python scripts/import_game.py private/unpatched-game-full --dry-run
```

The normal end-user importer copies game data to a per-user library. Codegen,
however, uses the development path declared in `config/THP8_rexglue.toml`.

## 4. Build the Pinned ReXGlue SDK

Initialize the only required submodule:

```bash
git submodule update --init --recursive tools/rexglue-sdk
```

The project currently pins ReXGlue commit
`4c1350847bb2bbc5fbf4272c78731632fccce8ab`. The same commit is recorded in
`project/CMakeLists.txt` and `scripts/apply-rexglue-patches.sh`; a mismatch is a
hard error.

On Linux:

```bash
cmake --preset linux-amd64 -S tools/rexglue-sdk
cmake --build tools/rexglue-sdk/out/build/linux-amd64 \
  --config Release --target install -j8
```

On Windows, run the equivalent `win-amd64` preset from a Visual Studio 2022
x64 developer environment:

```powershell
cmake --preset win-amd64 -S tools\rexglue-sdk
cmake --build tools\rexglue-sdk\out\build\win-amd64 `
  --config Release --target install -j8
```

Clang is required for the project build. The current Windows build is known to
work with Clang 19 and the Visual Studio 2022 v143 toolset.

## 5. Understand the ReXGlue Manifest

`config/THP8_rexglue.toml` is the canonical description of the guest image.
Its important sections are:

### Project and paths

```toml
[project]
name = "thp8"
sdk_version = "0.10.0"

[entrypoint]
file_path = "../private/unpatched-game-full/default.xex"
out_directory_path = "../generated"
```

Paths are relative to the manifest. The project name determines generated
filenames and the native module name.

### Register-local optimization

The manifest currently uses conservative settings: PowerPC state remains in
`PPCContext` rather than being aggressively promoted to C++ locals. This keeps
behavior predictable while function boundaries and runtime behavior are still
being validated.

Optimization flags change generated calling assumptions. Treat changes to
`*_as_local`, `skip_*`, or exception-handler generation as ABI changes and
regenerate all output.

### Analysis controls

```toml
[entrypoint.analysis]
max_jump_extension = 65536
data_region_threshold = 16
```

ReXGlue discovers code and jump targets automatically. These values let the
analyzer follow THP8's larger control-flow regions without treating embedded
data as executable code too aggressively.

### Explicit function boundaries

```toml
[entrypoint.functions]
0x8241F518 = {}
0x8241FE90 = { parent = 0x8241F8D0 }
0x8237B458 = { end = 0x8237B48C }
```

The table records boundaries that automatic analysis cannot infer reliably:

- `{}` declares a standalone function entry.
- `parent` declares a callable entry inside a larger discovered function.
- `end` constrains a function whose inferred extent overlaps data or another
  function.

This table replaced the old workflow of maintaining separate XenonAnalyse
jump-table files. Entries were accumulated by correlating runtime failures,
ReXGlue logs, generated call sites, and disassembly of the supported base XEX.

When adding an entry:

1. Confirm the address against the supported unpatched XEX.
2. Determine whether it is a real function, an internal entry point, or a
   bounded fragment.
3. Add the narrowest correct declaration.
4. Regenerate all code.
5. Rebuild and exercise the path that exposed the missing boundary.

Do not copy addresses from a patched executable. Title updates move functions
and invalidate native overrides.

## 6. Generate the Guest Code

After installing the SDK, run:

```bash
tools/rexglue-sdk/out/install/linux-amd64/bin/rexglue \
  codegen config/THP8_rexglue.toml
```

On Windows:

```powershell
tools\rexglue-sdk\out\install\win-amd64\bin\rexglue.exe `
  codegen config\THP8_rexglue.toml
```

Codegen writes:

```text
generated/
├── sources.cmake          # Complete source list consumed by project CMake
├── thp8_pch.h             # PPC context, image constants, and memory helpers
├── thp8_init.cpp/.h       # Image metadata and module initialization
├── thp8_register.cpp      # Guest-function registration
├── thp8_funcs.N.h         # Generated declarations
└── thp8_recomp.N.cpp      # Recompiled PowerPC functions
```

Codegen also records dependency, partition, and output-stamp metadata used to
make subsequent runs deterministic and incremental.

Never hand-edit generated files. Make analyzer changes in
`config/THP8_rexglue.toml`, make runtime behavior changes in `project/src/`,
then rerun codegen.

ReXGlue's `PPCContext` is part of its runtime ABI. Output from the historical
standalone XenonRecomp pipeline cannot be mixed with this generated tree.

## 7. Apply the Project's ReXGlue Patch Stack

ProjectRecomp carries an ordered patch stack in `patches/rexglue-v0.10.0/`.
The patches contain fixes and hooks that are not yet available in the pinned
SDK, including:

- local-content and file-delete correctness
- project-side ImGui context access
- POSIX shared-memory, wait, memory-map, and write-watch improvements
- VSync and frame-metric corrections
- incremental GPU read-pointer updates
- configured function-chunk handling
- performance-counter CSV wiring
- separation of guest vblank timing from host VSync

`project/CMakeLists.txt` verifies the SDK commit and applies each patch in
filename order during configuration. It accepts either a pristine SDK or one
with the complete patch already applied. A conflicting partial state stops the
configure step.

The patch stack can also be applied explicitly on Unix:

```bash
scripts/apply-rexglue-patches.sh tools/rexglue-sdk
```

Because patches are applied in place, `git status` may show
`tools/rexglue-sdk` as modified after configuration. Do not commit those
submodule worktree changes; commit changes to the corresponding patch file.

When updating the ReXGlue pin:

1. Start from a clean submodule checkout.
2. Update the expected commit in `.gitmodules`/the gitlink,
   `project/CMakeLists.txt`, and `scripts/apply-rexglue-patches.sh`.
3. Rebase or regenerate every required patch against the new commit.
4. Apply the complete stack to a pristine checkout.
5. Regenerate the guest code.
6. Build and perform startup-to-gameplay validation on Windows and Linux.

## 8. Integrate Generated Code with the Native App

`project/CMakeLists.txt` performs the active integration:

1. Verify and patch the pinned ReXGlue source.
2. Add ReXGlue with `add_subdirectory`.
3. require `generated/sources.cmake`.
4. Build `thp8` from the native app plus `${GENERATED_SOURCES}`.
5. Link `rex::runtime`, ImGui, and the Xenos GPU plugin.
6. Package the executable, ReXGlue DLLs, and app-local Visual C++ runtime files
   on Windows.

Configuration fails with an actionable message if codegen has not been run.

The app entry point is deliberately small:

```cpp
#include "thp8_init.h"
#include "thp8_app.h"

REX_DEFINE_APP(thp8, THP8App::Create)
```

`THP8App` derives from `rex::ReXApp` and configures title-specific behavior:

- `OnPreSetup` selects the `xenos` GPU plugin.
- `OnConfigurePaths` locates imported or developer game data.
- `OnPostSetup` and `OnShutdown` manage title-specific host UI state.
- `OnLoadXexImage` keeps the standard `default.xex` path.

The runtime search order supports:

1. executable-adjacent `game/`
2. executable-adjacent `game_data/`
3. the platform's installed-game library
4. the executable directory
5. `private/unpatched-game-full/` for development

## 9. Override Guest Functions Safely

Generated guest functions use:

```cpp
extern "C" REX_FUNC(sub_8235F2A8);
```

The macro provides a `PPCContext& ctx` and guest-memory base pointer. Arguments
and return values follow the PowerPC ABI through `ctx.r3` onward.

To wrap a generated function, declare its generated implementation with the
`__imp__` prefix, then provide the public symbol:

```cpp
extern "C" REX_FUNC(__imp__sub_8235F2A8);

extern "C" REX_FUNC(sub_8235F2A8) {
    REX_FUNC_PROLOGUE();
    const uint32_t output = ctx.r3.u32;
    __imp__sub_8235F2A8(ctx, base);
    // Apply the narrowly scoped title fix.
}
```

Use ReXGlue's endian-aware guest-memory helpers:

```cpp
const uint32_t value = REX_LOAD_U32(guest_address);
REX_STORE_U32(guest_address, value);
```

Do not dereference guest addresses as host pointers or assume little-endian
layout. Keep overrides tied to the exact supported XEX revision and document
the behavior that requires each hook.

`project/src/stubs.cpp` contains historical patched-build experiments and is
intentionally excluded from the target. Active unpatched-build overrides live
in `project/src/thp8_app.cpp`.

## 10. THP8-Specific Bring-Up Work

ReXGlue supplied the platform runtime, but reaching a polished game still
required title-specific integration:

### Function discovery

Automatic analysis missed several call targets and internal entries. Runtime
failures were traced back to disassembly, then fixed with explicit
`[entrypoint.functions]` declarations. One incorrect function extent required
an explicit `end`.

### Main-menu and options integration

THP8's menus are QB scripts loaded through a guest script cache. ProjectRecomp
wraps the cache lookup, recognizes the expected retail payload, and substitutes
project-authored scripts embedded at build time. Native command references are
resolved from the live guest symbol table rather than hard-coded as host
addresses.

This approach preserves the retail menu flow while adding:

- a reliable Quit action
- a Graphics entry in the existing Options menu
- a host-side ImGui settings dialog

### Rendering and loading UI

Guest-function wrappers select known THP8 render descriptors and adjust loading
screen geometry. Only modes backed by valid retail descriptors are exposed.
ReXGlue's internal resolution scaling remains integer-based; arbitrary output
window scaling is separate.

### Timing

THP8 normally renders every other 60 Hz guest vblank. Project-specific ReXGlue
patches separate guest timing from host presentation so VSync can control
tearing without silently changing guest timing. Experimental 60 FPS operation
uses a 120 Hz guest video mode and still requires game-wide validation.

### Shaders

No generated shader source or shader cache is checked into this repository.
ReXGlue's Xenos plugin translates the game's shaders at runtime and maintains
its own cache. The old XenosRecomp submodule and empty `shaders/` workspace were
therefore removed.

## 11. Configure and Build ProjectRecomp

After codegen, configure the native project.

Linux:

```bash
cmake -S project -B project/build -G Ninja \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build project/build -j8
```

Windows, from a Visual Studio x64 developer environment:

```powershell
cmake -S project -B project\build -G Ninja `
  -DCMAKE_C_COMPILER=clang `
  -DCMAKE_CXX_COMPILER=clang++ `
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build project\build -j8
```

The project targets the `x86-64-v2` architecture baseline. Windows binaries use
the dynamic MSVC runtime because allocations cross executable/DLL boundaries.
The installer stages the matching release CRT DLLs app-locally.

## 12. Run and Debug

Launch through the helper:

```bash
scripts/run_thp8.py --profile original
```

Or run the executable directly:

```bash
project/build/thp8 \
  --game_data_root private/unpatched-game-full \
  --gpu_plugin xenos \
  --fullscreen=false
```

Useful debugging rules:

- A missing `generated/sources.cmake` means codegen has not run.
- A function-registration or invalid-call failure usually means analysis missed
  a target or split a function incorrectly.
- A failure after changing XEX revision usually means generated addresses and
  native overrides no longer match.
- A ReXGlue patch conflict means the submodule is at the wrong commit or is
  partially modified.
- Missing game files should be fixed through `--game_data_root` or the importer,
  not by copying assets into the source tree.
- Persistent graphics values live in `thp8.toml`; explicit command-line values
  take precedence.
- ReXGlue logs are the first place to inspect GPU, audio, VFS, and guest-module
  startup failures.

When diagnosing a new guest crash:

1. Reproduce with the supported unpatched XEX.
2. Record the guest address and surrounding generated function.
3. Compare it with XEX disassembly.
4. Fix analysis in the manifest or add a narrow native override.
5. Regenerate if the manifest changed.
6. Rebuild and retest the original path.

Avoid patching generated C++ directly; those changes disappear on the next
codegen run and hide the real analyzer or integration issue.

## 13. Build a Windows Release

Install [Inno Setup 7](https://jrsoftware.org/isinfo.php), then run:

```powershell
scripts\build_release.ps1
```

The script:

1. builds the configured project
2. installs only the `ProjectRecomp` CMake component into a staging directory
3. includes the ReXGlue runtime, Xenos GPU plugin, release VC runtime DLLs,
   third-party licenses, and documentation
4. compiles the game-free installer
5. clones the selected commit and every recursive submodule into a clean
   staging tree
6. creates complete corresponding-source ZIP and tar.gz archives
7. writes SHA-256 checksums for all release artifacts

The setup wizard asks the user for an extracted disc directory, validates the
exact base XEX, and imports the game data separately from the application.
Uninstalling the runtime does not delete the user's imported game.

The source archives are required release assets. GitHub's automatically
generated source archives omit submodule contents and are not a substitute.

## 14. Historical Migration

ProjectRecomp began with standalone XenonRecomp output and a small custom
runtime containing hundreds of kernel stubs. That prototype was useful for
proving the XEX analysis and identifying game-specific behavior, but it did not
provide a complete graphics, audio, threading, or platform layer.

The migration to ReXGlue retained the useful analysis results:

- known function and internal-entry boundaries
- corrected function extents
- title-specific native overrides
- menu and rendering discoveries

It replaced:

- checked-in `ppc/` output with ReXGlue codegen
- the custom `runtime/` with `rex::ReXApp`
- standalone shader experiments with the Xenos runtime plugin
- one-off analysis submodules and scripts with the manifest's explicit function
  table

For new work, treat `config/THP8_rexglue.toml`, `project/`, the ReXGlue patch
stack, and this document as the authoritative workflow.

## References

- [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk)
- [Xenia](https://github.com/xenia-project/xenia) for Xbox 360 behavioral
  references
- [Free60](https://free60.org/) for community hardware documentation
- [extract-xiso](https://github.com/XboxDev/extract-xiso)
- [xdvdfs](https://crates.io/crates/xdvdfs-cli)
