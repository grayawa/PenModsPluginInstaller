import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import PenMods.PluginInstaller 1.0

Rectangle {
    id: root
    width: 320
    height: 170
    color: "#0f141b"

    property string registryUrl: "https://example.invalid/plugins.json"
    property var registryPlugins: backend.plugins
    property var filteredPlugins: []
    property string selectedPluginId: ""
    property string statusText: backend.statusText
    property string searchText: ""
    property string planText: backend.installPlanText(selectedPluginId)
    property string actionLabel: "安装"

    InstallerBackend {
        id: backend
    }

    function applyFilter() {
        var query = searchText.toLowerCase();
        filteredPlugins = registryPlugins.filter(function(plugin) {
            if (!query) {
                return true;
            }
            var haystack = [
                plugin.name,
                plugin.author,
                plugin.summary,
                plugin.id
            ].join(" ").toLowerCase();
            return haystack.indexOf(query) !== -1;
        });

        if (!selectedPluginId && filteredPlugins.length > 0) {
            selectedPluginId = filteredPlugins[0].id;
        }
        refreshPlan();
    }

    function selectedPlugin() {
        for (var i = 0; i < registryPlugins.length; i += 1) {
            if (registryPlugins[i].id === selectedPluginId) {
                return registryPlugins[i];
            }
        }
        return null;
    }

    function selectedDistributionType() {
        var plugin = selectedPlugin();
        if (!plugin || !plugin.distribution) {
            return "unknown";
        }
        return plugin.distribution.type || "unknown";
    }

    function selectedDownloadText() {
        var plugin = selectedPlugin();
        if (!plugin) {
            return "-";
        }
        if (plugin.download_url) {
            return plugin.download_url;
        }
        if (plugin.distribution && plugin.distribution.url) {
            return plugin.distribution.url;
        }
        return "-";
    }

    function refreshRegistry() {
        backend.refreshRegistry(registryUrl);
    }

    function refreshPlan() {
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
        if (!selectedPluginId) {
            statusText = "没有可安装的插件。";
            return;
        }
        var mode = backend.installMode(selectedPluginId);
        if (mode === "core-update") {
            backend.prepareCoreUpdate(selectedPluginId);
            return;
        }
        if (mode === "handoff") {
            backend.openDistribution(selectedPluginId);
            return;
        }
        backend.install(selectedPluginId);
    }

    Component.onCompleted: {
        refreshRegistry();
    }

    Connections {
        target: backend
        function onPluginsChanged() {
            root.registryPlugins = backend.plugins;
            root.applyFilter();
        }
        function onStatusTextChanged() {
            root.statusText = backend.statusText;
        }
        function onInstallStateChanged() {
            root.refreshPlan();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Label {
            text: "PenMods 插件安装器"
            color: "#f5f7fa"
            font.pixelSize: 16
            font.bold: true
            Layout.fillWidth: true
        }

        TextField {
            Layout.fillWidth: true
            placeholderText: "搜索插件"
            text: root.searchText
            onTextChanged: {
                root.searchText = text;
                root.applyFilter();
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            ListView {
                id: pluginList
                Layout.preferredWidth: 132
                Layout.fillHeight: true
                clip: true
                model: root.filteredPlugins
                delegate: Rectangle {
                    width: pluginList.width
                    height: 28
                    radius: 6
                    color: modelData.id === root.selectedPluginId ? "#2f6fed" : "#17202b"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        elide: Text.ElideRight
                        color: "#f5f7fa"
                        text: modelData.name
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selectedPluginId = modelData.id;
                            root.refreshPlan();
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "#17202b"
                border.color: "#243243"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Label {
                        Layout.fillWidth: true
                        text: root.selectedPlugin() ? root.selectedPlugin().name : "未选择插件"
                        color: "#f5f7fa"
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: "#9cb0c5"
                        text: root.selectedPlugin()
                            ? (root.selectedPlugin().summary || root.selectedPlugin().description || "")
                            : "从索引中选择一个插件以查看信息。"
                        font.pixelSize: 10
                    }

                    Label {
                        Layout.fillWidth: true
                        color: "#9cb0c5"
                        text: root.selectedPlugin()
                            ? ("ID: " + root.selectedPlugin().id)
                            : "ID: -"
                        font.pixelSize: 10
                    }

                    Label {
                        Layout.fillWidth: true
                        color: "#9cb0c5"
                        text: root.selectedPlugin()
                            ? ("下载: " + root.selectedDownloadText())
                            : "下载: -"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }

                    Label {
                        Layout.fillWidth: true
                        color: "#9cb0c5"
                        text: root.selectedPlugin()
                            ? ("渠道: " + root.selectedDistributionType())
                            : "渠道: -"
                        font.pixelSize: 10
                    }

                    TextArea {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readOnly: true
                        wrapMode: TextEdit.Wrap
                        color: "#d7e2f0"
                        text: root.planText
                        font.pixelSize: 10
                        background: Rectangle {
                            color: "#111821"
                            radius: 6
                            border.color: "#243243"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Button {
                            Layout.fillWidth: true
                            text: "刷新索引"
                            onClicked: root.refreshRegistry()
                        }

                        Button {
                            Layout.fillWidth: true
                            enabled: root.selectedPlugin() !== null
                            text: root.actionLabel
                            onClicked: root.runInstallAction()
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.statusText
            color: "#9cb0c5"
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
