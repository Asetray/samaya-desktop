import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Item {
    id: view
    required property var appRoot
    property string project: ""
    property string state: "全部状态"
    property var folded: ({})
    property var more: ({})
    function waiting(id) {
        return appRoot.pending.some(r => r.params.threadId === id);
    }
    function groups() {
        const search = filter.text.trim().toLowerCase();
        return U.grouped(appRoot.rows.filter(r => {
            const t = r.thread;
            if (project && t.cwd !== project)
                return false;
            if (appRoot.scope === "待我处理" && !waiting(t.id) || appRoot.scope === "置顶任务" && !appRoot.pins.includes(t.id))
                return false;
            if (state === "运行中" && !U.active(t) || state === "待处理" && !waiting(t.id) || state === "已结束" && U.active(t))
                return false;
            return !search || (t.cwd + " " + U.title(t)).toLowerCase().includes(search);
        }));
    }
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        y: appRoot.initialized ? 24 : 64
        width: Math.min(912, parent.width - (appRoot.compact ? 40 : 72))
        height: parent.height - y - 20
        spacing: 14
        Ink {
            text: appRoot.scope
            font.pixelSize: appRoot.compact ? 26 : 32
            font.weight: Font.Medium
            Layout.leftMargin: appRoot.compact ? 22 : 0
        }
        Column {
            visible: !appRoot.online || !appRoot.initialized
            spacing: 4
            Ink {
                text: appRoot.problem ? "连接已断开" : "正在取得全局会话状态…"
                font.pixelSize: 18
                font.weight: Font.Medium
            }
            Ink {
                text: appRoot.problem || "正在建立连接，请稍候。"
                color: Style.muted
                width: view.width * 0.75
                wrapMode: Text.Wrap
            }
            SamayaButton {
                visible: !!appRoot.problem
                kind: "outline"
                text: "重新连接"
                onClicked: appRoot.connectExisting()
            }
        }
        RowLayout {
            visible: appRoot.online && appRoot.initialized
            Layout.fillWidth: true
            spacing: 12
            Field {
                id: filter
                Layout.preferredWidth: 280
                Layout.fillWidth: appRoot.compact
                Layout.minimumWidth: 70
                searchIcon: true
                placeholderText: "搜索工作区名称或路径"
            }
            SamayaButton {
                visible: !appRoot.compact
                text: (view.project ? U.base(view.project) : "所有项目") + " ﹀"
                kind: "outline"
                onClicked: projectMenu.open()
                Menu {
                    id: projectMenu
                    MenuItem {
                        text: "所有项目"
                        onTriggered: view.project = ""
                    }
                    Instantiator {
                        model: appRoot.groups
                        delegate: MenuItem {
                            required property var modelData
                            text: U.base(modelData.path)
                            onTriggered: view.project = modelData.path
                        }
                        onObjectAdded: (i, o) => projectMenu.insertItem(i + 1, o)
                        onObjectRemoved: (i, o) => projectMenu.removeItem(o)
                    }
                }
            }
            SamayaButton {
                visible: !appRoot.compact
                kind: "outline"
                text: view.state + " ﹀"
                onClicked: states.open()
                Menu {
                    id: states
                    Repeater {
                        model: ["全部状态", "运行中", "待处理", "已结束"]
                        MenuItem {
                            required property string modelData
                            text: modelData
                            onTriggered: view.state = text
                        }
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                visible: !appRoot.compact
            }
            SamayaButton {
                text: "新任务"
                glyph: "plus"
                kind: "primary"
                implicitHeight: 40
                onClicked: appRoot.newThread("")
            }
        }
        RowLayout {
            visible: appRoot.online && appRoot.initialized
            Layout.fillWidth: true
            Layout.topMargin: 9
            Ink {
                text: appRoot.scope === "任务总览" ? "最近活跃的工作区" : appRoot.scope
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.fillWidth: true
            }
            Ink {
                text: list.count + " 个工作区"
                font.pixelSize: 12
                color: Style.quiet
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 20
            clip: true
            spacing: 16
            visible: appRoot.online && appRoot.initialized
            HoverHandler { id: listPointer }
            model: StableRows {
                source: view.groups()
                keyFor: group => group.path
                holdOrder: listPointer.hovered
            }
            ScrollBar.vertical: ScrollBar {}
            delegate: Column {
                id: group
                required property QtObject row
                readonly property var modelData: row.value
                width: list.width - 12
                spacing: 0
                Rectangle {
                    color: view.folded[group.modelData.path] ? Style.selected : "transparent"
                    radius: 8
                    width: parent.width
                    height: 64
                    TapHandler {
                        onTapped: {
                            let f = Object.assign({}, view.folded);
                            f[group.modelData.path] = !f[group.modelData.path];
                            view.folded = f;
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        Image {
                            source: Style.symbol(view.folded[group.modelData.path] ? "chevron" : "wm-down", Style.muted)
                            sourceSize: Qt.size(16, 16)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Ink {
                                text: U.base(group.modelData.path)
                                font.pixelSize: 18
                                font.weight: Font.Medium
                                Layout.fillWidth: true
                            }
                            Ink {
                                text: group.modelData.path
                                font.pixelSize: 12
                                color: Style.muted
                                Layout.fillWidth: true
                            }
                        }
                        Ink {
                            visible: !appRoot.compact
                            font.pixelSize: 12
                            color: Style.muted
                            text: group.modelData.rows.length + " 个任务"
                        }
                        SamayaButton {
                            glyph: "plus"
                            text: appRoot.compact ? "" : "新建会话"
                            hint: "新建会话"
                            typeSize: 12
                            onClicked: appRoot.newThread(group.modelData.path)
                        }
                    }
                }
                Repeater {
                    model: StableRows {
                        source: view.folded[group.modelData.path] ? [] : group.modelData.rows
                        keyFor: record => record.thread.id
                        limit: view.more[group.modelData.path] ? -1 : 5
                        holdOrder: listPointer.hovered
                    }
                    delegate: Rectangle {
                        id: r
                        required property QtObject row
                        readonly property var modelData: row.value
                        width: group.width
                        height: 64
                        radius: 8
                        color: view.waiting(modelData.thread.id) || U.active(modelData.thread) ? Style.subtle : hover.hovered ? Style.hover : "transparent"
                        HoverHandler {
                            id: hover
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Style.border
                        }
                        BreathingBorder {
                            anchors.fill: parent
                            visible: view.waiting(r.modelData.thread.id)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Ink {
                                    Layout.fillWidth: true
                                    text: U.title(r.modelData.thread)
                                }
                                Ink {
                                    Layout.fillWidth: true
                                    color: Style.muted
                                    font.pixelSize: 12
                                    text: U.base(group.modelData.path) + " · " + (view.waiting(r.modelData.thread.id) ? "待我处理" : U.status(r.modelData.thread, r.modelData.turn))
                                }
                            }
                            SamayaButton {
                                kind: "outline"
                                typeSize: 12
                                implicitHeight: 32
                                text: view.waiting(r.modelData.thread.id) ? "查看请求" : "进入对话"
                                onClicked: appRoot.openThread(r.modelData.thread.id)
                            }
                        }
                    }
                }
                SamayaButton {
                    visible: !view.folded[group.modelData.path] && group.modelData.rows.length > 5
                    text: view.more[group.modelData.path] ? "收起" : "再展开 " + (group.modelData.rows.length - 5) + " 个任务"
                    onClicked: {
                        let m = Object.assign({}, view.more);
                        m[group.modelData.path] = !m[group.modelData.path];
                        view.more = m;
                    }
                }
            }
            Ink {
                visible: list.count === 0
                text: "没有符合条件的对话。"
                color: Style.muted
            }
        }
        Item {
            visible: !appRoot.online || !appRoot.initialized
            Layout.fillHeight: true
        }
    }
}
