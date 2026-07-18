import QtQuick 2.12
import PenMods.PluginInstaller 1.0
import "qrc:/qml/commons"

Rectangle {
    id: root
    width: 320; height: 170; color: "#0f141b"
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
        currentPlugin = null
        for (var i = 0; i < registryPlugins.length; i += 1)
            if (registryPlugins[i].id === selectedPluginId) { currentPlugin = registryPlugins[i]; return }
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
        filteredPlugins = (q === "") ? registryPlugins : registryPlugins.filter(function(p) {
            var h = [p.name, p.author, p.summary, p.id].join(" ").toLowerCase()
            return h.indexOf(q) !== -1
        })
        if (filteredPlugins.length > 0 && !backend.isInstalled(filteredPlugins[0].id))
            for (var k = 0; k < filteredPlugins.length; k += 1)
                if (!selectedPluginId || filteredPlugins[k].id === selectedPluginId) { selectedPluginId = filteredPlugins[k].id; break }
        refreshPlan()
    }
    function refreshRegistry() { backend.refreshRegistry(registryUrl) }
    function refreshPlan() {
        refreshCurrentPlugin()
        if (!selectedPluginId) { actionLabel = "安装"; planText = "从左侧选择一个插件以查看安装计划。"; return }
        if (backend.isInstalled(selectedPluginId)) actionLabel = "卸载"
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
    function showKeyboard() {
        var comp = qmlCreateComponent("YInputPage")
        if (comp.status !== Component.Ready) return
        var inc = comp.incubateObject(keyboardHelper.containerItem)
        if (inc.status !== Component.Ready) {
            inc.onStatusChanged = function(s) { if (s === Component.Ready) keyboardHelper.inputPageCreated(inc.object) }
        } else {
            keyboardHelper.inputPageCreated(inc.object)
        }
    }

    Component.onCompleted: { refreshRegistry(); refreshInstalled() }

    Connections {
        target: backend
        function onPluginsChanged() { root.registryPlugins = backend.plugins; root.applyFilter() }
        function onStatusTextChanged() { root.statusText = backend.statusText }
        function onInstallStateChanged() { root.refreshPlan(); root.refreshInstalled() }
        function onInstalledPluginsChanged() { root.refreshInstalled(); root.refreshPlan() }
    }

    YPagePopHelper {
        id: keyboardHelper; z: 99
        function inputPageCreated(page) {
            page.backButtonClicked.connect(function() { page.todoDestroy() })
            page.inputFinished.connect(function(content) {
                root.searchText = content.trim()
                root.applyFilter()
                page.todoDestroy()
            })
            page.enterText(root.searchText)
            page.show()
        }
    }

    // ═══════════ layout ═══════════

    // ── left tab column ──
    Column {
        id: leftTabs
        anchors.top: parent.top; anchors.topMargin: 4; anchors.left: parent.left; anchors.leftMargin: 4
        width: 48; spacing: 4

        Rectangle {
            width: 48; height: 28; radius: 4
            color: viewMode === "registry" ? "#2f6fed" : "#1a2330"
            Text { anchors.centerIn: parent; text: "注册表"; color: "#f5f7fa"; font.pixelSize: 10 }
            MouseArea { anchors.fill: parent; onClicked: { root.viewMode = "registry"; root.refreshPlan() } }
        }
        Rectangle {
            width: 48; height: 28; radius: 4
            color: viewMode === "installed" ? "#2f6fed" : "#1a2330"
            Text { anchors.centerIn: parent; text: "已安装"; color: "#f5f7fa"; font.pixelSize: 10 }
            MouseArea { anchors.fill: parent; onClicked: { root.viewMode = "installed"; root.refreshInstalled() } }
        }
    }

    // ── search bar ──
    Rectangle {
        id: searchBox
        anchors.top: parent.top; anchors.topMargin: 4
        anchors.left: leftTabs.right; anchors.leftMargin: 4; anchors.right: parent.right; anchors.rightMargin: 4
        height: 26; color: "#111821"; radius: 4; border.color: "#243243"
        visible: viewMode === "registry"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 6; anchors.right: parent.right; anchors.rightMargin: 6
            color: root.searchText ? "#f5f7fa" : "#555a65"; font.pixelSize: 11; elide: Text.ElideRight
            text: root.searchText || "搜索插件"
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.showKeyboard()
        }
    }

    // ── body ──
    Row {
        anchors.top: viewMode === "registry" ? searchBox.bottom : leftTabs.top
        anchors.topMargin: viewMode === "registry" ? 4 : 0
        anchors.left: viewMode === "registry" ? leftTabs.right : leftTabs.left
        anchors.leftMargin: 4
        anchors.right: parent.right; anchors.rightMargin: 4
        anchors.bottom: parent.bottom; anchors.bottomMargin: 4
        spacing: 4

        // ── left: plugin list ──
        Rectangle {
            width: viewMode === "registry" ? 114 : (parent.width > 0 ? parent.width : 260)
            height: parent.height; color: "#17202b"; radius: 6; clip: true

            ListView {
                id: pluginList; anchors.fill: parent; anchors.margins: 2
                model: viewMode === "registry" ? root.filteredPlugins : root.installedList
                delegate: Rectangle {
                    width: pluginList.width; height: 24; radius: 4
                    color: (viewMode === "registry" && modelData.id === root.selectedPluginId) ? "#2f6fed" : "transparent"
                    Row {
                        anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 3; spacing: 3
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: viewMode === "installed" ? parent.width - 48 : parent.width - 14
                            elide: Text.ElideRight
                            text: viewMode === "registry" ? modelData.name : (modelData.name || modelData.id)
                            color: "#f5f7fa"; font.pixelSize: 10
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: viewMode === "registry" && backend.isInstalled(modelData.id)
                            text: "✓"; color: "#4ade80"; font.pixelSize: 10; font.bold: true
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter; width: 38; height: 16; radius: 3
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

        // ── right: detail (registry only) ──
        Rectangle {
            visible: viewMode === "registry"
            width: parent.width - 118; height: parent.height
            color: "#17202b"; radius: 6; border.color: "#243243"

            Rectangle {
                id: detailTitle
                anchors.top: parent.top; anchors.topMargin: 4
                anchors.left: parent.left; anchors.leftMargin: 5; anchors.right: parent.right; anchors.rightMargin: 5
                height: 14; color: "transparent"
                Row { spacing: 4
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
            }

            Text {
                id: detailSummary
                anchors.top: detailTitle.bottom; anchors.topMargin: 1
                anchors.left: parent.left; anchors.leftMargin: 5; anchors.right: parent.right; anchors.rightMargin: 5
                color: "#9cb0c5"; font.pixelSize: 9; elide: Text.ElideRight; maximumLineCount: 1
                text: root.currentPlugin ? (root.currentPlugin.summary || root.currentPlugin.description || "") : "从索引中选择一个插件。"
            }

            Flickable {
                id: planFlick
                anchors.top: detailSummary.bottom; anchors.topMargin: 2
                anchors.left: parent.left; anchors.leftMargin: 5; anchors.right: parent.right; anchors.rightMargin: 5
                anchors.bottom: btnRow.top; anchors.bottomMargin: 2
                clip: true; contentWidth: width; contentHeight: planTextInner.height + 4
                Rectangle {
                    width: parent.width; height: Math.max(parent.height, planTextInner.height + 4)
                    color: "#111821"; radius: 5; border.color: "#243243"
                    Text {
                        id: planTextInner
                        anchors.left: parent.left; anchors.leftMargin: 3; anchors.right: parent.right; anchors.rightMargin: 3
                        anchors.top: parent.top; anchors.topMargin: 3
                        color: "#d7e2f0"; font.pixelSize: 9; wrapMode: Text.WordWrap
                        text: root.planText
                    }
                }
            }

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
                    property bool i: backend.isInstalled(root.selectedPluginId)
                    color: root.currentPlugin ? (i ? "#c0392b" : "#2f6fed") : "#1a2330"
                    border.color: "#243243"; opacity: root.currentPlugin ? 1 : 0.5
                    Text { anchors.centerIn: parent; text: root.actionLabel; color: "#f5f7fa"; font.pixelSize: 9 }
                    MouseArea { anchors.fill: parent; enabled: root.currentPlugin !== null; onClicked: root.runInstallAction() }
                }
            }
        }
    }
}
