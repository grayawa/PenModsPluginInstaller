import QtQuick 2.12
import PenMods.PluginInstaller 1.0

Rectangle {
    id: root
    width: 320
    height: 170
    color: "#0f141b"

    signal backButtonClicked()

    property string registryUrl: "https://grayawa.github.io/PenModsPluginIndex/data/plugins.json"
    property var registryPlugins: backend.plugins
    property var filteredPlugins: []
    property var installedList: backend.installedPlugins()
    property string selectedPluginId: ""
    property string statusText: backend.statusText
    property string searchText: ""
    property string planText: backend.installPlanText(selectedPluginId)
    property string actionLabel: "安装"
    property string viewMode: "registry"
    property var currentPlugin: null

    InstallerBackend { id: backend }

    function refreshCurrentPlugin() {
        currentPlugin = null;
        for (var i = 0; i < registryPlugins.length; i += 1) {
            if (registryPlugins[i].id === selectedPluginId) {
                currentPlugin = registryPlugins[i];
                return;
            }
        }
    }

    function selectedDistributionType() {
        if (!currentPlugin || !currentPlugin.distribution) return "unknown";
        return currentPlugin.distribution.type || "unknown";
    }

    function selectedDownloadText() {
        if (!currentPlugin) return "-";
        if (currentPlugin.download_url) return currentPlugin.download_url;
        if (currentPlugin.distribution && currentPlugin.distribution.url) return currentPlugin.distribution.url;
        return "-";
    }

    function applyFilter() {
        var query = searchText.toLowerCase();
        filteredPlugins = registryPlugins.filter(function(p) {
            if (!query) return true;
            var h = [p.name, p.author, p.summary, p.id].join(" ").toLowerCase();
            return h.indexOf(query) !== -1;
        });
        if (!selectedPluginId && filteredPlugins.length > 0)
            selectedPluginId = filteredPlugins[0].id;
        refreshPlan();
    }

    function refreshRegistry() {
        backend.refreshRegistry(registryUrl);
    }

    function refreshPlan() {
        refreshCurrentPlugin();
        if (!selectedPluginId) {
            actionLabel = "安装";
            planText = "从左侧选择一个插件以查看安装计划。";
            return;
        }
        if (backend.isInstalled(selectedPluginId)) {
            actionLabel = "卸载";
        } else {
            var mode = backend.installMode(selectedPluginId);
            actionLabel = mode === "handoff" ? "获取渠道" : (mode === "core-update" ? "准备更新" : "安装");
        }
        planText = backend.installPlanText(selectedPluginId);
    }

    function runInstallAction() {
        if (!selectedPluginId) { statusText = "没有可安装的插件。"; return; }
        if (backend.isInstalled(selectedPluginId)) {
            backend.uninstallPlugin(selectedPluginId);
            return;
        }
        var mode = backend.installMode(selectedPluginId);
        if (mode === "core-update") { backend.prepareCoreUpdate(selectedPluginId); return; }
        if (mode === "handoff") { backend.openDistribution(selectedPluginId); return; }
        backend.install(selectedPluginId);
    }

    function refreshInstalled() {
        installedList = backend.installedPlugins();
    }

    Component.onCompleted: { refreshRegistry(); refreshInstalled(); }

    Connections {
        target: backend
        function onPluginsChanged() { root.registryPlugins = backend.plugins; root.applyFilter(); }
        function onStatusTextChanged() { root.statusText = backend.statusText; }
        function onInstallStateChanged() { root.refreshPlan(); root.refreshInstalled(); }
        function onInstalledPluginsChanged() { root.refreshInstalled(); root.refreshPlan(); }
    }

    // ── title ──
    Rectangle {
        id: titleBar
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 28; color: "#17202b"

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: parent.right; anchors.rightMargin: 8
            spacing: 6

            Rectangle {
                width: Math.max(54, titleTab0.width + 12); height: 20; radius: 4
                color: viewMode === "registry" ? "#2f6fed" : "#1a2330"
                Text {
                    id: titleTab0; anchors.centerIn: parent
                    text: "注册表"; color: "#f5f7fa"; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.viewMode = "registry"; root.refreshPlan(); }
                }
            }
            Rectangle {
                width: Math.max(54, titleTab1.width + 12); height: 20; radius: 4
                color: viewMode === "installed" ? "#2f6fed" : "#1a2330"
                Text {
                    id: titleTab1; anchors.centerIn: parent
                    text: "已安装"; color: "#f5f7fa"; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.viewMode = "installed"; root.refreshInstalled(); }
                }
            }
            Text {
                text: root.statusText; color: "#9cb0c5"; font.pixelSize: 10
                elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── search ──
    Rectangle {
        id: searchBox
        anchors.top: titleBar.bottom; anchors.topMargin: 6
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
        height: 24; color: "#111821"; radius: 4; border.color: "#243243"
        visible: viewMode === "registry"
        TextInput {
            id: searchInput
            anchors.fill: parent; anchors.margins: 4
            color: "#f5f7fa"; font.pixelSize: 11; clip: true
            Text {
                anchors.fill: parent; text: "搜索插件"; color: "#555a65"
                font.pixelSize: 11; visible: !searchInput.text
            }
            onTextChanged: { root.searchText = text; root.applyFilter(); }
        }
    }

    // ── body ──
    Row {
        anchors.top: viewMode === "registry" ? searchBox.bottom : titleBar.bottom
        anchors.topMargin: 6
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
        spacing: 6

        // ── left: plugin list ──
        Rectangle {
            width: viewMode === "registry" ? 116 : parent.width
            height: parent.height; color: "#17202b"; radius: 6; clip: true

            ListView {
                id: pluginList; anchors.fill: parent; anchors.margins: 2
                model: viewMode === "registry" ? root.filteredPlugins : root.installedList
                delegate: Rectangle {
                    width: pluginList.width; height: 26; radius: 4
                    color: (viewMode === "registry" && modelData.id === root.selectedPluginId) ? "#2f6fed" : "transparent"
                    Row {
                        anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 4; spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: viewMode === "installed" ? parent.width - 50 : parent.width - 14
                            elide: Text.ElideRight
                            text: viewMode === "registry" ? modelData.name : (modelData.name || modelData.id)
                            color: "#f5f7fa"; font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: viewMode === "registry" && backend.isInstalled(modelData.id)
                            text: "✓"; color: "#4ade80"; font.pixelSize: 11; font.bold: true
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter; width: 40; height: 18; radius: 3
                            visible: viewMode === "installed"; color: "#c0392b"
                            Text {
                                anchors.centerIn: parent; text: "卸载"; color: "#f5f7fa"; font.pixelSize: 9
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { backend.uninstallPlugin(modelData.id); }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        visible: viewMode === "registry"
                        onClicked: { root.selectedPluginId = modelData.id; root.refreshPlan(); }
                    }
                }
            }
        }

        // ── right: detail (registry only) ──
        Rectangle {
            visible: viewMode === "registry"
            width: parent.width - 122; height: parent.height
            color: "#17202b"; radius: 8; border.color: "#243243"

            Column {
                anchors.fill: parent; anchors.margins: 6; spacing: 4

                Row {
                    width: parent.width; spacing: 6
                    Text {
                        elide: Text.ElideRight
                        text: root.currentPlugin ? root.currentPlugin.name : "未选择插件"
                        color: "#f5f7fa"; font.pixelSize: 13; font.bold: true
                    }
                    Rectangle {
                        width: instTag.width + 10; height: 16; radius: 3; color: "#2f6fed"
                        visible: root.selectedPluginId !== "" && backend.isInstalled(root.selectedPluginId)
                        Text {
                            id: instTag; anchors.centerIn: parent
                            text: "已安装"; color: "#f5f7fa"; font.pixelSize: 9
                        }
                    }
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    color: "#9cb0c5"; font.pixelSize: 10
                    text: root.currentPlugin
                        ? (root.currentPlugin.summary || root.currentPlugin.description || "")
                        : "从索引中选择一个插件以查看信息。"
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    color: "#9cb0c5"; font.pixelSize: 10
                    text: root.currentPlugin ? ("ID: " + root.currentPlugin.id) : "ID: -"
                }
                Text {
                    width: parent.width; elide: Text.ElideMiddle
                    color: "#9cb0c5"; font.pixelSize: 10
                    text: root.currentPlugin ? ("下载: " + root.selectedDownloadText()) : "下载: -"
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    color: "#9cb0c5"; font.pixelSize: 10
                    text: root.currentPlugin ? ("渠道: " + root.selectedDistributionType()) : "渠道: -"
                }

                Rectangle {
                    width: parent.width; height: parent.height - 140
                    color: "#111821"; radius: 6; border.color: "#243243"
                    Text {
                        anchors.fill: parent; anchors.margins: 4
                        color: "#d7e2f0"; font.pixelSize: 10; wrapMode: Text.WordWrap
                        text: root.planText
                    }
                }

                Row {
                    width: parent.width; spacing: 6
                    Rectangle {
                        width: parent.width / 2 - 3; height: 24; radius: 6; color: "#1d2b3a"; border.color: "#243243"
                        Text {
                            anchors.centerIn: parent
                            text: "刷新索引"; color: "#f5f7fa"; font.pixelSize: 10
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.refreshRegistry()
                        }
                    }
                    Rectangle {
                        width: parent.width / 2 - 3; height: 24; radius: 6
                        color: root.currentPlugin ? (backend.isInstalled(root.selectedPluginId) ? "#c0392b" : "#2f6fed") : "#1a2330"
                        border.color: "#243243"; opacity: root.currentPlugin ? 1 : 0.5
                        Text {
                            anchors.centerIn: parent
                            text: root.actionLabel; color: "#f5f7fa"; font.pixelSize: 10
                        }
                        MouseArea {
                            anchors.fill: parent; enabled: root.currentPlugin !== null
                            onClicked: root.runInstallAction()
                        }
                    }
                }
            }
        }
    }
}
