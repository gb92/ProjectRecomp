# Agent Instructions for ProjectRecomp

## Project Overview

ProjectRecomp statically recompiles the unpatched Xbox 360 release of Tony
Hawk's Project 8 with ReXGlue. It currently boots through Career and reaches
gameplay on Windows and Linux.

The repository does not include the game. Never commit, attach, paste, or link
to ISOs, XEX/XEXP files, extracted assets, saves, caches, or decrypted images.
Development requires a legally acquired copy using base executable revision
`0.0.0.1`; title updates are unsupported.

## Active Architecture

- `project/` contains the native executable, THP8-specific hooks, menus, and
  build definition.
- `generated/` contains ReXGlue PPC codegen output and is intentionally
  gitignored.
- `tools/rexglue-sdk/` is the pinned ReXGlue submodule.
- `patches/rexglue-v0.10.0/` contains the ordered patches applied to ReXGlue
  during CMake configuration.
- `config/THP8_rexglue.toml` is the active codegen manifest.
- `private/` contains local game files and is gitignored except for its
  README.
- `scripts/run_thp8.py` launches development builds.

Do not reintroduce the obsolete standalone `runtime/` or tracked `ppc/`
prototype trees.

## Build Workflow

Initialize submodules recursively, build the pinned ReXGlue SDK, generate
`generated/` from the supported base XEX, then configure `project/`. Follow
the current commands in `README.md`; `docs/recompilation-guide.md` documents
the general recompilation pipeline.

ReXGlue patches must:

- Apply sequentially to the pinned commit declared in `project/CMakeLists.txt`.
- Be reproducible from a clean submodule checkout.
- Be submitted as patch files rather than dirty submodule contents.
- Preserve Windows and Linux behavior unless a limitation is explicit.

## Platform Requirements

- Windows 10/11 x86-64 with Direct3D 12 is the primary target.
- Linux x86-64 with Vulkan is experimental.
- x86-64 builds target the `x86-64-v2` instruction set.
- Linux ARM64 and macOS are not currently supported.
- Use existing ReXGlue platform abstractions and compile-time guards for
  platform-specific behavior.

## Contribution Requirements

Read `CONTRIBUTING.md` before changing public-facing behavior. Keep changes
focused, update directly related documentation, and run the smallest relevant
build or validation command. Never add generated code, build artifacts, local
configuration, or private game material.
