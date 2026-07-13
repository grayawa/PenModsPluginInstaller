# Architecture Notes

## Goals

- Use the registry `id` and native plugin `metadata.json.id` as the same primary key.
- Install managed plugins into `/userdisk/PenMods/plugins/<folder>`.
- Cache registry entries locally for offline inspection and update checks.
- Keep QML as the UI layer only. Network, filesystem, unzip, and SQLite work
  must live in `libplugin_installer.so`.

## Data model

`registry_cache`
- stores the last fetched registry snapshot per plugin id

`installed_plugins`
- stores installed plugin id, folder name, installed version, status, and source metadata

`install_queue`
- records pending or completed install/update/remove actions

## Planned plugin install flow

1. Fetch registry JSON from PenMods Plugin Index.
2. Resolve the selected registry entry by plugin id.
3. Download the release package or open the gated distribution channel.
4. Extract the package to a temp directory.
5. Read the package `metadata.json`.
6. Confirm `metadata.json.id` matches the selected registry id.
7. Move the package into `/userdisk/PenMods/plugins/<folder>`.
8. Upsert `installed_plugins` with the installed version and metadata snapshot.

## Planned core update flow

PenMods core is `/userdata/PenMods/libPenMods.so`, so it does not need the same
directory install flow as regular plugins.

1. Resolve the `kind: core` registry entry.
2. Download or obtain the new `libPenMods.so`.
3. Copy it to `/userdata/PenMods/libPenMods.so`.
4. Write a `core_updates` record.
5. Restart PenMods so the new library is loaded.

## Known blocker

The entry point is aligned with the examples: `extern "C" void init_plugin()`
registers `InstallerBackend` as `PenMods.PluginInstaller 1.0`. The remaining
work is implementing direct file operations in C++: package download, archive
extraction, metadata verification, core library copy, and restart handoff.
