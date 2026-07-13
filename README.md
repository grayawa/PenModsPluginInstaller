# PenMods Plugin Installer

Standalone scaffold repository for a PenMods plugin installer plugin.

## Target layout

- Install location for managed plugins: `/userdisk/PenMods/plugins`
- Local installer data lives inside this plugin directory
- Registry source is the generated `plugins.json` payload from the separate
  PenMods Plugin Index repository

## Build on WSL Arch

Install the build toolchain once:

```bash
sudo pacman -Sy --needed base-devel xmake qt5-base qt5-declarative
```

Build the plugin:

```bash
xmake f -m debug
xmake
```

Package the plugin folder:

```bash
bash scripts/package.sh debug
```

The packaged plugin will be created at `package/plugin_installer`.

## Manual CLI

The package also includes `bin/penmods-plugin`, a small terminal installer that
can be added to `PATH` on-device:

```bash
penmods-plugin inspect ./plugin.zip
penmods-plugin install ./plugin.zip
penmods-plugin install ./plugin-folder
penmods-plugin list
```

It installs plugins into `/userdisk/PenMods/plugins`, verifies `metadata.json`
contains an `id`, and uses a temporary replacement path so a failed install does
not overwrite the existing plugin.

Build the device-compatible CLI with the same aarch64 glibc 2.27 toolchain used
by PenMods:

```bash
bash scripts/build-cli-aarch64.sh debug
```

The output is `build/linux/arm64-v8a/debug/penmods-plugin`; `package.sh` will
prefer this binary when it exists.

## Current scaffold

- `metadata.json`: native PenMods plugin metadata using the plugin package `id`
- `xmake.lua`: build script matching the example plugins
- `main.qml`: QML UI shell for search, install state, and plugin detail
- `src/InstallerBackend.*`: Qt/C++ backend registered from `init_plugin()`
- `src/PluginEntry.*`: registry entry adapter for QML and persistence
- `data/schema.sql`: SQLite schema for installer state

## Important note

The demo zip shows that native PenMods plugins currently declare both `main_qml`
and `main_so`. This plugin follows that shape: `main.qml` is the UI and
`libplugin_installer.so` registers `InstallerBackend` for QML through
`extern "C" void init_plugin()`.

## Seeded plugin ids

The bundled SQLite schema seeds two system entries into `installed_plugins`:

- `lyrecoul.penmods`
- `com.penmods.plugininstaller`

These ids are intended to match the registry ids used by the index website and
the native `metadata.json` ids used by packaged plugins.
