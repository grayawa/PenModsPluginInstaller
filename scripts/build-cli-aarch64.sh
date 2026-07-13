#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_MODE="${1:-debug}"
OUT_DIR="$ROOT_DIR/build/linux/arm64-v8a/$BUILD_MODE"
OUT_PATH="$OUT_DIR/penmods-plugin"

command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || {
  echo "Missing aarch64-linux-gnu-gcc. Install the PenMods glibc 2.27 cross toolchain first." >&2
  exit 1
}

mkdir -p "$OUT_DIR"
aarch64-linux-gnu-gcc \
  -std=c11 \
  -Wall \
  -O2 \
  "$ROOT_DIR/cli/penmods_plugin.c" \
  -o "$OUT_PATH"

echo "Built aarch64 CLI at: $OUT_PATH"
