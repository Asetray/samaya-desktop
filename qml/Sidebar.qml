import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Rectangle {
    id: rail
    required property var appRoot
    signal search
    property bool allProjects: false
    property var expanded: ({})
    color: Style.rail
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Image {
                source: Style.symbol("samaya-symbol", Style.ink)
                sourceSize: Qt.size(48, 48)
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
            }
            Ink {
                text: "Samaya"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.fillWidth: true
            }
            SamayaButton {
                glyph: "menu"
                hint: "收起侧栏"
                onClicked: appRoot.compact ? appRoot.drawer = false : appRoot.collapsed = true
            }
        }
        Item {
            Layout.preferredHeight: 6
        }
        Repeater {
            model: [["搜索任务与项目", "search"], ["任务总览", "panels-top-left"], ["置顶任务", "pin"], ["待我处理", "inbox"]]
            delegate: SamayaButton {
                required property var modelData
                Layout.fillWidth: true
                alignLeft: true
                glyph: modelData[1]
                text: modelData[0]
                Layout.bottomMargin: modelData[1] === "search" ? 12 : 0
                selected: appRoot.page === "overview" && appRoot.scope === text
                onClicked: modelData[1] === "search" ? rail.search() : appRoot.overview(text)
                Ink {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 12
                    color: Style.muted
                    text: parent.text === "待我处理" && appRoot.pending.length ? appRoot.pending.length : ""
                }
            }
        }
        Ink {
            text: "工作区"
            font.pixelSize: 12
            color: Style.muted
            Layout.topMargin: 12
            Layout.bottomMargin: 2
        }
        ListView {
            id: projects
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            HoverHandler { id: projectPointer }
            model: StableRows {
                source: appRoot.groups
                keyFor: group => group.path
                limit: rail.allProjects ? -1 : 4
                holdOrder: projectPointer.hovered
            }
            footer: SamayaButton {
                visible: appRoot.groups.length > 4
                height: visible ? 32 : 0
                text: rail.allProjects ? "收起工作区" : "更多工作区 · " + (appRoot.groups.length - 4)
                onClicked: rail.allProjects = !rail.allProjects
            }
            ScrollBar.vertical: ScrollBar {}
            delegate: Column {
                id: g
                required property QtObject row
                readonly property var modelData: row.value
                required property int index
                width: projects.width
                spacing: 4
                property bool opened: rail.expanded[modelData.path] === undefined ? index === 0 : !!rail.expanded[modelData.path]
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 8
                    color: g.opened ? Style.selected : Style.rail
                    RowLayout {
                        anchors.fill: parent
                        spacing: 0
                        SamayaButton {
                            Layout.fillWidth: true
                            alignLeft: true
                            glyph: g.opened ? "wm-down" : "chevron"
                            text: U.base(g.modelData.path)
                            onClicked: {
                                const map = Object.assign({}, rail.expanded);
                                map[g.modelData.path] = !g.opened;
                                rail.expanded = map;
                            }
                        }
                        Ink {
                            font.pixelSize: 12
                            color: Style.muted
                            text: {
                                const n = g.modelData.rows.filter(r => U.active(r.thread)).length;
                                return n ? "运行中 " + n : "";
                            }
                        }
                        SamayaButton {
                            glyph: "plus"
                            hint: "新会话"
                            onClicked: appRoot.newThread(g.modelData.path)
                        }
                        SamayaButton {
                            glyph: "more"
                            hint: "管理工作区"
                            onClicked: appRoot.recordsFor(g.modelData.path)
                        }
                    }
                }
                Repeater {
                    model: StableRows {
                        source: g.opened ? g.modelData.rows : []
                        keyFor: record => record.thread.id
                        limit: 5
                        holdOrder: projectPointer.hovered
                    }
                    delegate: SamayaButton {
                        required property QtObject row
                        x: 20
                        width: g.width - 28
                        alignLeft: true
                        text: U.title(row.value.thread)
                        selected: appRoot.page === "chat" && appRoot.currentId === row.value.thread.id
                        onClicked: appRoot.openThread(row.value.thread.id)
                    }
                }
            }
        }
        SamayaButton {
            Layout.fillWidth: true
            alignLeft: true
            glyph: "history"
            text: "记录管理"
            selected: appRoot.page === "records"
            onClicked: appRoot.recordsFor("")
        }
        SamayaButton {
            Layout.fillWidth: true
            alignLeft: true
            glyph: "settings"
            text: "设置与连接"
            selected: appRoot.page === "settings" || appRoot.page === "usage"
            onClicked: appRoot.nav("settings")
        }
        Ink {
            font.pixelSize: 12
            color: Style.quiet
            text: appRoot.online ? "已连接 Codex" : appRoot.connecting ? "正在连接 Codex" : "连接已断开"
        }
    }
}
