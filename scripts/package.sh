#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_MODE="${1:-debug}"
LIB_PATH="$ROOT_DIR/build/linux/x86_64/$BUILD_MODE/libplugin_installer.so"
CLI_PATH="$ROOT_DIR/build/linux/arm64-v8a/$BUILD_MODE/penmods-plugin"
DEV_CLI_PATH="$ROOT_DIR/build/linux/x86_64/$BUILD_MODE/penmods_plugin"
OUT_DIR="$ROOT_DIR/package/plugin_installer"

if [[ ! -f "$LIB_PATH" ]]; then
  echo "Missing built library: $LIB_PATH" >&2
  echo "Run: xmake f -m $BUILD_MODE && xmake" >&2
  exit 1
fi

if [[ ! -f "$CLI_PATH" ]]; then
  if [[ -f "$DEV_CLI_PATH" ]]; then
    echo "Warning: missing aarch64 CLI, packaging host dev CLI instead: $DEV_CLI_PATH" >&2
    CLI_PATH="$DEV_CLI_PATH"
  else
    echo "Missing CLI binary: $CLI_PATH" >&2
    echo "Run: scripts/build-cli-aarch64.sh $BUILD_MODE" >&2
    exit 1
  fi
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/data" "$OUT_DIR/bin"

cp "$ROOT_DIR/metadata.json" "$OUT_DIR/metadata.json"
cp "$ROOT_DIR/main.qml" "$OUT_DIR/main.qml"
cp "$LIB_PATH" "$OUT_DIR/libplugin_installer.so"
cp "$CLI_PATH" "$OUT_DIR/bin/penmods-plugin"
cp "$ROOT_DIR/data/schema.sql" "$OUT_DIR/data/schema.sql"

if [[ -f "$ROOT_DIR/data/installer.db" ]]; then
  cp "$ROOT_DIR/data/installer.db" "$OUT_DIR/data/installer.db"
fi

echo "Packaged plugin at: $OUT_DIR"
