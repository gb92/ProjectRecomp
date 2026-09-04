#!/usr/bin/env python3

import argparse
import hashlib
import os
import shutil
import sys
import uuid
from pathlib import Path


SUPPORTED_XEX_SHA256 = (
    "cfc732340e55defda400e25f03231aa9bb65fd9545b618212f69a4952384a5dd"
)
INSTALL_MARKER = ".projectrecomp-game"
COPY_PROGRESS_INTERVAL = 256 * 1024 * 1024


class ImportFailure(Exception):
    pass


def default_install_root():
    if os.name == "nt":
        return Path.home() / "Games" / "ProjectRecomp"

    data_home = os.environ.get("XDG_DATA_HOME")
    if data_home:
        return Path(data_home) / "projectrecomp" / "game"
    return Path.home() / ".local" / "share" / "projectrecomp" / "game"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(4 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def find_root_file(source, expected_name):
    matches = [
        path
        for path in source.iterdir()
        if path.name.casefold() == expected_name.casefold()
    ]
    if not matches:
        raise ImportFailure(f"{expected_name} was not found in {source}")
    if len(matches) != 1 or matches[0].name != expected_name:
        raise ImportFailure(f"the extracted root must contain exactly {expected_name}")
    if matches[0].is_symlink() or not matches[0].is_file():
        raise ImportFailure(f"{expected_name} must be a regular file")
    return matches[0]


def validate_source(source):
    if not source.is_dir():
        raise ImportFailure(f"extracted game directory not found: {source}")

    xex_path = find_root_file(source, "default.xex")
    if any(path.name.casefold() == "default.xexp" for path in source.iterdir()):
        raise ImportFailure(
            "default.xexp is not supported; import the unpatched base game"
        )

    actual_hash = sha256_file(xex_path)
    if actual_hash != SUPPORTED_XEX_SHA256:
        raise ImportFailure(
            "unsupported default.xex\n"
            f"  expected SHA-256: {SUPPORTED_XEX_SHA256.upper()}\n"
            f"  actual SHA-256:   {actual_hash.upper()}"
        )
    return xex_path


def iter_source_entries(source):
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        if relative.parts[0].casefold() == "$systemupdate":
            continue
        if path.is_symlink():
            raise ImportFailure(f"symbolic links are not supported: {relative}")
        if not path.is_dir() and not path.is_file():
            raise ImportFailure(f"unsupported filesystem entry: {relative}")
        yield path, relative


def inspect_source(source):
    entries = list(iter_source_entries(source))
    files = [entry for entry in entries if entry[0].is_file()]
    return entries, len(files), sum(path.stat().st_size for path, _ in files)


def format_size(size):
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}"
        value /= 1024
    raise AssertionError("unreachable")


def ensure_safe_destination(destination, force):
    if not destination.exists():
        return
    if not force:
        raise ImportFailure(
            f"destination already exists: {destination}\n"
            "use --force to replace an existing ProjectRecomp import"
        )
    if not destination.is_dir() or not (destination / INSTALL_MARKER).is_file():
        raise ImportFailure(
            f"refusing to replace a directory not managed by this importer: "
            f"{destination}"
        )


def copy_game(source, staging, entries, total_size):
    copied = 0
    next_progress = COPY_PROGRESS_INTERVAL
    staging.mkdir()
    for path, relative in entries:
        target = staging / relative
        if path.is_dir():
            target.mkdir(exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied += path.stat().st_size
        if copied >= next_progress:
            print(f"Copied {format_size(copied)} of {format_size(total_size)}")
            next_progress += COPY_PROGRESS_INTERVAL


def promote_staging(staging, destination):
    backup = None
    if destination.exists():
        backup = destination.with_name(
            f".{destination.name}.backup-{uuid.uuid4().hex}"
        )
        destination.rename(backup)

    try:
        staging.rename(destination)
    except BaseException:
        if backup is not None and backup.exists() and not destination.exists():
            backup.rename(destination)
        raise

    if backup is not None:
        try:
            shutil.rmtree(backup)
        except OSError as error:
            print(
                f"Warning: could not remove previous import at {backup}: {error}",
                file=sys.stderr,
            )


def install_game(source, destination, force=False, dry_run=False):
    source = source.expanduser().resolve()
    destination = destination.expanduser().resolve()
    validate_source(source)

    if (
        destination == source
        or source in destination.parents
        or destination in source.parents
    ):
        raise ImportFailure("source and destination directories must not overlap")

    entries, file_count, total_size = inspect_source(source)
    print(f"Validated supported base game at {source}")
    print(f"Import size: {format_size(total_size)} across {file_count} files")
    print(f"Destination: {destination}")
    if dry_run:
        return

    destination.parent.mkdir(parents=True, exist_ok=True)
    ensure_safe_destination(destination, force)
    free_space = shutil.disk_usage(destination.parent).free
    if free_space < total_size:
        raise ImportFailure(
            f"not enough free space: need {format_size(total_size)}, "
            f"have {format_size(free_space)}"
        )

    staging = destination.with_name(
        f".{destination.name}.import-{uuid.uuid4().hex}"
    )
    try:
        copy_game(source, staging, entries, total_size)
        copied_xex = staging / "default.xex"
        if sha256_file(copied_xex) != SUPPORTED_XEX_SHA256:
            raise ImportFailure("copied default.xex failed verification")
        (staging / INSTALL_MARKER).write_text(
            f"xex_sha256={SUPPORTED_XEX_SHA256}\n", encoding="ascii"
        )
        promote_staging(staging, destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)

    print(f"Game import complete: {destination}")


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Validate and install an extracted Tony Hawk's Project 8 Xbox 360 "
            "disc for ProjectRecomp"
        )
    )
    parser.add_argument(
        "source",
        type=Path,
        help="extracted disc directory containing the supported default.xex",
    )
    parser.add_argument(
        "--destination",
        type=Path,
        default=default_install_root(),
        help="installed game directory (default: %(default)s)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace an existing import created by this tool",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and report what would be imported without copying files",
    )
    args = parser.parse_args()

    try:
        install_game(args.source, args.destination, args.force, args.dry_run)
    except (ImportFailure, OSError) as error:
        parser.exit(1, f"error: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
