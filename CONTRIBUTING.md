# Contributing to PenMods Plugin Installer

## Scope

This repository is only for the installer plugin itself.

- UI shell and plugin metadata
- registry fetch and local cache logic
- install/update/remove workflows
- local database schema

The separate PenMods Plugin Index repository remains the source of registry data.

## Current architecture

- `metadata.json`: native PenMods plugin metadata
- `main.qml`: installer interface
- `xmake.lua`: xmake build script for `libplugin_installer.so`
- `src/InstallerBackend.*`: network, SQLite, install queue, and install planning
- `src/PluginEntry.*`: registry entry parsing and QML mapping
- `data/schema.sql`: SQLite schema

## Immediate priorities

1. Replace placeholder release URLs with the real installer repository URL.
2. Connect and test the xmake build in the PenMods target toolchain.
3. Add download, unzip, and metadata inspection flow.
4. Sync installed state by native plugin `id`.
