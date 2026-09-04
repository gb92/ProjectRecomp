#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

from import_game import default_install_root


PROFILES = {
    "original": {"scale": 1, "anisotropy": 3},
    "1440p": {"scale": 2, "anisotropy": 5},
    "4k": {"scale": 3, "anisotropy": 5},
}


def default_build_dir():
    if os.name == "nt":
        return Path("tools/rexglue-sdk/out/win-amd64")
    return Path("tools/rexglue-sdk/out/linux-amd64")


def default_game_data_root():
    installed = default_install_root()
    if (installed / "default.xex").is_file():
        return installed
    return Path("private/unpatched-game-full")


def parse_size(value):
    match = re.fullmatch(r"([1-9][0-9]*)x([1-9][0-9]*)", value.lower())
    if not match:
        raise argparse.ArgumentTypeError("expected WIDTHxHEIGHT")
    return int(match.group(1)), int(match.group(2))


def main():
    parser = argparse.ArgumentParser(
        description="Launch THP8 with an internal-resolution graphics profile"
    )
    parser.add_argument("--profile", choices=PROFILES)
    parser.add_argument(
        "--fps",
        type=int,
        choices=(30, 60),
        default=30,
        help="Experimental THP8 frame-rate target",
    )
    parser.add_argument("--build-dir", type=Path, default=default_build_dir())
    parser.add_argument(
        "--game-data-root",
        type=Path,
        default=default_game_data_root(),
    )
    parser.add_argument("--cache-root", type=Path, default=Path("project/build/cache"))
    parser.add_argument("--internal-scale", type=int, choices=range(1, 9))
    parser.add_argument("--anisotropy", type=int, choices=range(-1, 6))
    parser.add_argument(
        "--game-render-resolution",
        choices=("original", "960x544", "1280x720"),
        help="Select one of THP8's built-in native render modes",
    )
    parser.add_argument(
        "--output-resolution",
        help="Guest and startup-window resolution preset, such as 4k or 2560x1440",
    )
    parser.add_argument("--window-size", type=parse_size, metavar="WIDTHxHEIGHT")
    parser.add_argument("--windowed", action="store_true")
    parser.add_argument(
        "--smooth-vsync",
        action="store_true",
        help="Keep the guest VSync worker runnable to reduce timer wakeup jitter",
    )
    parser.add_argument("--dry-run", action="store_true")

    if "--" in sys.argv:
        separator = sys.argv.index("--")
        args = parser.parse_args(sys.argv[1:separator])
        runtime_args = sys.argv[separator + 1 :]
    else:
        args = parser.parse_args()
        runtime_args = []

    executable_name = "thp8.exe" if os.name == "nt" else "thp8"
    executable = args.build_dir / executable_name
    if not executable.is_file():
        parser.error(f"THP8 executable not found: {executable}")

    command = [
        str(executable),
        f"--video_mode_refresh_rate={args.fps * 2}",
        "--game_data_root",
        str(args.game_data_root),
        "--cache_root",
        str(args.cache_root),
    ]
    if args.profile:
        profile = PROFILES[args.profile]
        command.extend(
            (
                f"--resolution_scale={profile['scale']}",
                f"--anisotropic_override={profile['anisotropy']}",
            )
        )
    if args.internal_scale is not None:
        command.append(f"--resolution_scale={args.internal_scale}")
    if args.anisotropy is not None:
        command.append(f"--anisotropic_override={args.anisotropy}")
    if args.game_render_resolution:
        command.append(
            f"--thp8_render_resolution={args.game_render_resolution}"
        )
    if args.output_resolution:
        command.append(f"--resolution={args.output_resolution}")
    if args.window_size:
        width, height = args.window_size
        command.extend((f"--window_width={width}", f"--window_height={height}"))
    if args.windowed:
        command.append("--fullscreen=false")
    if args.smooth_vsync:
        command.append("--gpu_vsync_busy_wait=true")
    command.extend(runtime_args)

    environment = os.environ.copy()
    display_command = [
        *command,
    ]
    print(" ".join(f'"{part}"' if " " in part else part for part in display_command))
    if args.dry_run:
        return 0
    return subprocess.run(command, check=False, env=environment).returncode


if __name__ == "__main__":
    raise SystemExit(main())
