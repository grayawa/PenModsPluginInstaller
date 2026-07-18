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
    property string selectedPluginId: ""
    property string statusText: backend.statusText
    property string searchText: ""
    property string planText: backend.installPlanText(selectedPluginId)
    property string actionLabel: "安装"
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
        var mode = backend.installMode(selectedPluginId);
        actionLabel = mode === "handoff" ? "获取渠道" : (mode === "core-update" ? "准备更新" : "安装");
        planText = backend.installPlanText(selectedPluginId);
    }

    function runInstallAction() {
        if (!selectedPluginId) { statusText = "没有可安装的插件。"; return; }
        var mode = backend.installMode(selectedPluginId);
        if (mode === "core-update") { backend.prepareCoreUpdate(selectedPluginId); return; }
        if (mode === "handoff") { backend.openDistribution(selectedPluginId); return; }
        backend.install(selectedPluginId);
    }

    Component.onCompleted: { refreshRegistry(); }

    Connections {
        target: backend
        function onPluginsChanged() { root.registryPlugins = backend.plugins; root.applyFilter(); }
        function onStatusTextChanged() { root.statusText = backend.statusText; }
        function onInstallStateChanged() { root.refreshPlan(); }
    }

    // ── title ──
    Rectangle {
        id: titleBar
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 28; color: "#17202b"
        Text {
            anchors.centerIn: parent
            text: "插件安装器"; color: "#f5f7fa"
            font.pixelSize: 14; font.bold: true
        }
    }

    // ── search ──
    Rectangle {
        id: searchBox
        anchors.top: titleBar.bottom; anchors.topMargin: 6
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
        height: 24; color: "#111821"; radius: 4; border.color: "#243243"
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
        anchors.top: searchBox.bottom; anchors.topMargin: 6
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
        anchors.bottom: bottomBar.top; anchors.bottomMargin: 6
        spacing: 6

        // ── left: plugin list ──
        Rectangle {
            width: 116; height: parent.height; color: "#17202b"; radius: 6; clip: true
            ListView {
                id: pluginList; anchors.fill: parent; anchors.margins: 2
                model: root.filteredPlugins
                delegate: Rectangle {
                    width: pluginList.width; height: 26; radius: 4
                    color: modelData.id === root.selectedPluginId ? "#2f6fed" : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 6
                        anchors.right: parent.right; anchors.rightMargin: 4; elide: Text.ElideRight
                        text: modelData.name; color: "#f5f7fa"; font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.selectedPluginId = modelData.id; root.refreshPlan(); }
                    }
                }
            }
        }

        // ── right: detail ──
        Rectangle {
            width: parent.width - 122; height: parent.height
            color: "#17202b"; radius: 8; border.color: "#243243"

            Column {
                anchors.fill: parent; anchors.margins: 6; spacing: 4

                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: root.currentPlugin ? root.currentPlugin.name : "未选择插件"
                    color: "#f5f7fa"; font.pixelSize: 13; font.bold: true
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
                        color: root.currentPlugin ? "#2f6fed" : "#1a2330"; border.color: "#243243"
                        opacity: root.currentPlugin ? 1 : 0.5
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

    // ── bottom status ──
    Rectangle {
        id: bottomBar
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        height: 18; color: "#17202b"
        Text {
            anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10
            anchors.right: parent.right; anchors.rightMargin: 10; elide: Text.ElideRight
            text: root.statusText; color: "#9cb0c5"; font.pixelSize: 10
        }
    }
}
