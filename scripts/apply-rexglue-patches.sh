#!/usr/bin/env bash
set -euo pipefail

readonly expected_commit="4c1350847bb2bbc5fbf4272c78731632fccce8ab"
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly project_root="$(cd -- "${script_dir}/.." && pwd)"
readonly patch_dir="${project_root}/patches/rexglue-v0.10.0"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/rexglue-sdk" >&2
  exit 2
fi

readonly sdk_dir="$(cd -- "$1" && pwd)"
actual_commit="$(git -C "${sdk_dir}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${expected_commit}" ]]; then
  echo "Expected ReXGlue ${expected_commit}, found ${actual_commit}" >&2
  exit 1
fi

patches=("${patch_dir}"/*.patch)

applied=0
existing=0
for patch in "${patches[@]}"; do
  if git -C "${sdk_dir}" apply --check "${patch}" 2>/dev/null; then
    git -C "${sdk_dir}" apply "${patch}"
    ((applied += 1))
  elif git -C "${sdk_dir}" apply --reverse --check "${patch}" 2>/dev/null; then
    ((existing += 1))
  else
    echo "Patch conflicts with ReXGlue source: $(basename "${patch}")" >&2
    exit 1
  fi
done

echo "ReXGlue patches ready (${applied} applied, ${existing} already present)."
