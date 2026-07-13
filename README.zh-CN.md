# PenMods 插件安装器

PenMods Plugin Installer 是一个原生 PenMods 插件，用来读取 PenMods
Plugin Index、准备插件安装、用 SQLite 记录安装状态，并提供一个类似
`apt install ./xxx.zip` 的终端手动安装工具。

这个仓库目前包含两部分：

- 运行在 PenMods 里的 QML + Qt/C++ 原生插件界面。
- 运行在终端里的 `penmods-plugin` 手动安装命令。

## 当前状态

已经实现：

- 拉取 registry，并把插件条目缓存到本地 SQLite。
- 展示安装计划。
- 安装前做依赖和 capability 预检查。
- 缺少 required dependency 时写入依赖队列。
- 对 Telegram / 受限分发插件记录 handoff 状态。
- 为 PenMods 本体更新生成计划，目标路径是 `/userdata/PenMods/libPenMods.so`。
- SQLite 表：registry cache、installed plugins、install queue、dependency queue、core updates。
- 独立终端命令 `penmods-plugin`，可从本地插件目录或 zip 包安装。
- GitHub Actions CI，检查 Qt 插件、打包结构和 aarch64 CLI。

还没实现：

- 在 Qt 后端里自动下载插件包。
- 在 Qt 后端里解压插件包。
- queued install worker 的实际执行流程。
- queued worker 里的 `metadata.json` 校验。
- PenMods 本体 `libPenMods.so` 的实际复制和重启交接。

## 路径约定

- 普通插件安装目录：`/userdisk/PenMods/plugins`
- PenMods 本体 so：`/userdata/PenMods/libPenMods.so`
- 安装器本地数据：`/userdisk/PenMods/plugins/plugin_installer/data`
- Registry 来源：PenMods Plugin Index 生成的 `plugins.json`

## 构建

在 Arch 或 WSL Arch 上安装构建依赖：

```bash
sudo pacman -Sy --needed base-devel xmake qt5-base qt5-declarative
```

构建 Qt 插件和宿主机开发用 CLI：

```bash
xmake f -m debug
xmake
```

用 PenMods 同款 glibc 2.27 交叉工具链构建设备用 aarch64 CLI：

```bash
bash scripts/build-cli-aarch64.sh debug
```

打包插件目录：

```bash
bash scripts/package.sh debug
```

打包结果在：

```text
package/plugin_installer
```

如果存在 `build/linux/arm64-v8a/debug/penmods-plugin`，`package.sh` 会优先把
这个设备可运行版本放进包里，而不是宿主机 x86_64 开发版。

## 终端手动安装器

包里包含 `bin/penmods-plugin`，可以在设备上加入 `PATH` 后使用：

```bash
penmods-plugin inspect ./plugin.zip
penmods-plugin install ./plugin.zip
penmods-plugin install ./plugin-folder
penmods-plugin list
```

它会读取 `metadata.json`，要求存在插件 `id`，并安装到：

```text
/userdisk/PenMods/plugins/<sanitized-id>
```

安装时会使用 `.new` / `.bak` 临时替换路径，尽量保证安装失败时不会覆盖已有插件。

当前设备版 CLI 是 aarch64 ELF，实际只要求 `GLIBC_2.17`，可以在 PenMods 的
glibc 2.27 环境中运行。

## 原生插件结构

本插件遵循当前 PenMods 原生插件格式：

- `metadata.json`
- `main.qml`
- `libplugin_installer.so`

`libplugin_installer.so` 导出 `extern "C" void init_plugin()`，并把
`InstallerBackend` 注册为 QML 模块 `PenMods.PluginInstaller 1.0`。

## 预置 ID

SQLite schema 会预置两个系统条目：

- `lyrecoul.penmods`
- `com.penmods.plugininstaller`

这些 ID 应当和 registry 里的 ID、原生插件 `metadata.json.id` 保持一致。

## CI

GitHub Actions 会检查：

- Qt 插件 shared library 是否能构建。
- 宿主机开发用 CLI 是否能构建。
- aarch64 / glibc 2.27 兼容 CLI 是否能构建。
- 打包目录结构是否完整。
- `bin/penmods-plugin` 是否为 ARM aarch64。
- CLI 的 GLIBC symbol version 是否兼容。

打包后的 `package/plugin_installer` 会作为 workflow artifact 上传。

## 相关链接

- PenMods 本体：https://github.com/Lyrecoul/PenMods
- 本仓库：https://github.com/grayawa/PenModsPluginInstaller
