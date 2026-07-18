import QtQuick 2.12
import PenMods.PluginInstaller 1.0
import "qrc:/qml/commons"

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
    property string planText: backend.installPlanText(selectedPluginId)
    property string actionLabel: "安装"
    property string viewMode: "registry"
    property var currentPlugin: null

    InstallerBackend { id: backend }

    function refreshCurrentPlugin() {
        currentPlugin = null
        for (var i = 0; i < registryPlugins.length; i += 1) {
            if (registryPlugins[i].id === selectedPluginId) { currentPlugin = registryPlugins[i]; return }
        }
    }
    function selectedDistributionType() {
        if (!currentPlugin || !currentPlugin.distribution) return "unknown"
        return currentPlugin.distribution.type || "unknown"
    }
    function selectedDownloadText() {
        if (!currentPlugin) return "-"
        if (currentPlugin.download_url) return currentPlugin.download_url
        if (currentPlugin.distribution && currentPlugin.distribution.url) return currentPlugin.distribution.url
        return "-"
    }
    function applyFilter() {
        var q = searchText.toLowerCase()
        filteredPlugins = registryPlugins.filter(function(p) {
            if (!q) return true
            var h = [p.name, p.author, p.summary, p.id].join(" ").toLowerCase()
            return h.indexOf(q) !== -1
        })
        if (!selectedPluginId && filteredPlugins.length > 0) selectedPluginId = filteredPlugins[0].id
        refreshPlan()
    }
    function refreshRegistry() { backend.refreshRegistry(registryUrl) }
    function refreshPlan() {
        refreshCurrentPlugin()
        if (!selectedPluginId) { actionLabel = "安装"; planText = "从左侧选择一个插件以查看安装计划。"; return }
        if (backend.isInstalled(selectedPluginId)) { actionLabel = "卸载" }
        else { var m = backend.installMode(selectedPluginId); actionLabel = m === "handoff" ? "获取渠道" : (m === "core-update" ? "准备更新" : "安装") }
        planText = backend.installPlanText(selectedPluginId)
    }
    function runInstallAction() {
        if (!selectedPluginId) { statusText = "没有可安装的插件。"; return }
        if (backend.isInstalled(selectedPluginId)) { backend.uninstallPlugin(selectedPluginId); return }
        var m = backend.installMode(selectedPluginId)
        if (m === "core-update") { backend.prepareCoreUpdate(selectedPluginId); return }
        if (m === "handoff") { backend.openDistribution(selectedPluginId); return }
        backend.install(selectedPluginId)
    }
    function refreshInstalled() { installedList = backend.installedPlugins() }

    Component.onCompleted: { refreshRegistry(); refreshInstalled() }

    Connections {
        target: backend
        function onPluginsChanged() { root.registryPlugins = backend.plugins; root.applyFilter() }
        function onStatusTextChanged() { root.statusText = backend.statusText }
        function onInstallStateChanged() { root.refreshPlan(); root.refreshInstalled() }
        function onInstalledPluginsChanged() { root.refreshInstalled(); root.refreshPlan() }
    }

    // ── tab bar ──
    Row {
        id: tabBar
        anchors.top: parent.top; anchors.topMargin: 6
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
        height: 24; spacing: 6

        Rectangle {
            id: tabReg; width: 56; height: 24; radius: 4
            color: viewMode === "registry" ? "#2f6fed" : "#1a2330"
            Text { anchors.centerIn: parent; text: "注册表"; color: "#f5f7fa"; font.pixelSize: 10 }
            MouseArea { anchors.fill: parent; onClicked: { root.viewMode = "registry"; root.refreshPlan() } }
        }
        Rectangle {
            id: tabInst; width: 56; height: 24; radius: 4
            color: viewMode === "installed" ? "#2f6fed" : "#1a2330"
            Text { anchors.centerIn: parent; text: "已安装"; color: "#f5f7fa"; font.pixelSize: 10 }
            MouseArea { anchors.fill: parent; onClicked: { root.viewMode = "installed"; root.refreshInstalled() } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText; color: "#9cb0c5"; font.pixelSize: 9; elide: Text.ElideRight
        }
    }

    // ── search ──
    Rectangle {
        id: searchBox
        anchors.top: tabBar.bottom; anchors.topMargin: 6
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
        height: 26; color: "#111821"; radius: 4; border.color: "#243243"
        visible: viewMode === "registry"
        TextInput {
            id: searchInput
            anchors.fill: parent; anchors.margins: 4
            color: "#f5f7fa"; font.pixelSize: 11; clip: true; readOnly: true
            Text {
                anchors.fill: parent; text: "搜索插件"; color: "#555a65"
                font.pixelSize: 11; visible: !searchInput.text
            }
            onTextChanged: { root.searchText = text; root.applyFilter() }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                var comp = qmlCreateComponent("YInputPage")
                if (comp.status !== Component.Ready) return
                var incubator = comp.incubateObject(keyboardHelper.containerItem)
                if (incubator.status !== Component.Ready) {
                    incubator.onStatusChanged = function(s) {
                        if (s === Component.Ready) keyboardHelper.inputPageCreated(incubator.object)
                    }
                } else {
                    keyboardHelper.inputPageCreated(incubator.object)
                }
            }
        }
    }

    YPagePopHelper {
        id: keyboardHelper
        z: 99
        function inputPageCreated(page) {
            page.backButtonClicked.connect(function() { page.todoDestroy() })
            page.inputFinished.connect(function(content) {
                searchInput.text = content.trim()
                page.todoDestroy()
            })
            page.enterText(searchInput.text)
            page.show()
        }
    }

    // ── body ──
    Row {
        anchors.top: viewMode === "registry" ? searchBox.bottom : tabBar.bottom
        anchors.topMargin: 6
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
        anchors.bottom: parent.bottom; anchors.bottomMargin: 4
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
                            Text { anchors.centerIn: parent; text: "卸载"; color: "#f5f7fa"; font.pixelSize: 9 }
                            MouseArea { anchors.fill: parent; onClicked: { backend.uninstallPlugin(modelData.id) } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; visible: viewMode === "registry"
                        onClicked: { root.selectedPluginId = modelData.id; root.refreshPlan() }
                    }
                }
            }
        }

        // ── right: detail panel ──
        Rectangle {
            visible: viewMode === "registry"
            width: parent.width - 122; height: parent.height
            color: "#17202b"; radius: 8; border.color: "#243243"

            // title row
            Row {
                id: detailTitleRow
                anchors.top: parent.top; anchors.topMargin: 4
                anchors.left: parent.left; anchors.leftMargin: 5; anchors.right: parent.right; anchors.rightMargin: 5
                height: 14; spacing: 4
                Text {
                    text: root.currentPlugin ? root.currentPlugin.name : "未选择插件"
                    color: "#f5f7fa"; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight
                }
                Rectangle {
                    width: 36; height: 14; radius: 3; color: "#2f6fed"
                    visible: root.selectedPluginId !== "" && backend.isInstalled(root.selectedPluginId)
                    Text { anchors.centerIn: parent; text: "已安装"; color: "#f5f7fa"; font.pixelSize: 8 }
                }
            }

            // summary (1 line)
            Text {
                id: detailSummary
                anchors.top: detailTitleRow.bottom; anchors.topMargin: 1
                anchors.left: parent.left; anchors.leftMargin: 5; anchors.right: parent.right; anchors.rightMargin: 5
                color: "#9cb0c5"; font.pixelSize: 9; elide: Text.ElideRight; maximumLineCount: 1
                text: root.currentPlugin ? (root.currentPlugin.summary || root.currentPlugin.description || "") : "从索引中选择一个插件。"
            }

            // plan text (fills remaining space)
            Rectangle {
                id: planBox
                anchors.top: detailSummary.bottom; anchors.topMargin: 2
                anchors.left: parent.left; anchors.leftMargin: 5; anchors.right: parent.right; anchors.rightMargin: 5
                anchors.bottom: btnRow.top; anchors.bottomMargin: 2
                color: "#111821"; radius: 5; border.color: "#243243"
                Text {
                    anchors.fill: parent; anchors.margins: 2
                    color: "#d7e2f0"; font.pixelSize: 9; wrapMode: Text.WordWrap
                    text: root.planText
                }
            }

            // bottom buttons
            Row {
                id: btnRow
                anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                anchors.left: parent.left; anchors.leftMargin: 5; anchors.right: parent.right; anchors.rightMargin: 5
                height: 18; spacing: 4

                Rectangle {
                    width: parent.width / 2 - 2; height: 18; radius: 4; color: "#1d2b3a"; border.color: "#243243"
                    Text { anchors.centerIn: parent; text: "刷新"; color: "#f5f7fa"; font.pixelSize: 9 }
                    MouseArea { anchors.fill: parent; onClicked: root.refreshRegistry() }
                }
                Rectangle {
                    width: parent.width / 2 - 2; height: 18; radius: 4
                    property bool inst: backend.isInstalled(root.selectedPluginId)
                    color: root.currentPlugin ? (inst ? "#c0392b" : "#2f6fed") : "#1a2330"
                    border.color: "#243243"; opacity: root.currentPlugin ? 1 : 0.5
                    Text { anchors.centerIn: parent; text: root.actionLabel; color: "#f5f7fa"; font.pixelSize: 9 }
                    MouseArea { anchors.fill: parent; enabled: root.currentPlugin !== null; onClicked: root.runInstallAction() }
                }
            }
        }
    }
}
