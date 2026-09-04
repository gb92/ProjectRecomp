# Contributing to ProjectRecomp

ProjectRecomp is an experimental static recompilation of the unpatched Xbox
360 release of Tony Hawk's Project 8. Contributions that improve correctness,
portability, performance, tooling, documentation, and legal game-file import
are welcome.

## No Game Files

This repository must not contain copyrighted game material. Do not commit,
attach, paste, or link to:

- Xbox 360 ISOs, XEX/XEXP files, extracted game assets, or save data
- Decrypted or decompressed executable images
- Large binary excerpts from the game
- Instructions or links intended to obtain the game without authorization

Use only a legally acquired copy for local development. Reports involving
modified files, title updates, or unsupported revisions may be closed because
the project targets the unmodified base executable revision `0.0.0.1`.

Small derived data required to describe a fix should be represented as
addresses, hashes, signatures, or reproducible tooling wherever possible.
Ask a maintainer before submitting any game-derived binary payload.

## Before Opening an Issue

1. Build or test the latest `main` revision.
2. Search existing issues for the same behavior.
3. Confirm the issue is specific to ProjectRecomp rather than a bug in the
   original Xbox 360 game.
4. Reproduce with an unmodified supported game copy and without third-party
   overlays or external frame limiters where practical.
5. Use the appropriate issue form and complete every required field.

Logs are welcome after reviewing them for personal paths or other sensitive
information. Never include game files in a diagnostic archive.

## Development Setup

Initialize submodules recursively and follow the build instructions in
[README.md](README.md). The detailed recompilation pipeline is documented in
[docs/recompilation-guide.md](docs/recompilation-guide.md).

Generated code, build outputs, caches, and files under `private/` must remain
untracked. ReXGlue changes must be submitted as ordered patches under the
active `patches/rexglue-v*/` directory rather than as a dirty submodule or an
unreviewed submodule revision change.

## Pull Requests

- Keep each pull request focused on one coherent change.
- Explain the user-visible behavior, implementation, and relevant tradeoffs.
- Link the issue being addressed when one exists.
- Add or update focused tests and documentation when behavior changes.
- Build the affected supported platforms when possible.
- Preserve cross-platform behavior; isolate platform-specific code behind the
  existing platform abstractions or compile-time guards.
- Do not include unrelated formatting, generated output, or local settings.

For runtime fixes, describe how the behavior was measured and include enough
detail for another contributor to reproduce it without receiving your game
files.

## Code Style

Follow the surrounding C++ and Python conventions. Prefer small,
well-contained changes, explicit error handling, existing helpers, and
comments only where the intent is not evident from the code.

## Licensing

ProjectRecomp is licensed under the
[BSD 3-Clause License](LICENSE). By submitting a contribution, you agree that
it will be distributed under those terms. You also affirm that you have the
right to contribute it and that it does not include unauthorized third-party
material.
