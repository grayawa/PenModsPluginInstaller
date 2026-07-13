# TODO

- Wire `registryUrl` to the real published `plugins.json`.
- Compare registry dependencies and capabilities before queuing installs. (done)
- Queue missing required dependencies before installing the requested plugin. (done)
- Add standalone terminal installer binary for manual installs. (done)
- Add package download and checksum verification in C++.
- Add archive extraction and temp cleanup in C++.
- Add `libPenMods.so` copy flow for core updates.
- Add restart handoff after core update.
- Read packaged `metadata.json` before install.
- Compare installed version with registry version for update prompts.
- Surface restricted Telegram distribution as a handoff flow instead of direct install.
