# Place your game files here

This directory is gitignored. You need to provide your own legally-owned copies.

No game executable, ISO, extracted asset, title update, save file, or cache
file belongs in Git. Do not attach these files to project issues or pull
requests.

## Required Files

| File | How to obtain |
|------|--------------|
| `default.xex` | Extract from your Xbox 360 disc (the main executable) |
| `default.xexp` | Unsupported; title updates are intentionally not used because they enforce an internal 30 FPS cap |

The supported base `default.xex` has SHA-256
`CFC732340E55DEFDA400E25F03231AA9BB65FD9545B618212F69A4952384A5DD`.
For a normal installation, validate and copy an extracted disc with
`python scripts/import_game.py "path/to/extracted/disc"`.

## Generated Files

| File | How to generate |
|------|-----------------|
| `disc_extract/` | `extract-xiso -d private/disc_extract "private/Your Game.iso"` |
