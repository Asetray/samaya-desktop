import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Item {
    id: view
    required property var appRoot
    property alias composer: inputBox
    property int historyCount: 48
    readonly property var timeline: U.timeline(appRoot.thread)
    readonly property var artifacts: {
        let out = [];
        for (let turn of appRoot.thread.turns || [])
            for (let it of turn.items || [])
                if (it.type === "fileChange")
                    for (let change of it.changes || [])
                        out.push(change);
        return out;
    }
    readonly property bool narrow: width < 780
    readonly property real readingWidth: Math.min(880, width - (narrow ? 32 : 64))
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.leftMargin: appRoot.compact ? 44 : Math.max(16, (view.width - view.readingWidth) / 2)
            Layout.rightMargin: 12
            spacing: 4
            Ink {
                Layout.fillWidth: true
                visible: !appRoot.compact
                text: appRoot.currentId ? U.title(appRoot.thread) : U.base(appRoot.cwd) + " / 新会话"
                font.weight: Font.Medium
                font.pixelSize: 16
            }
            Repeater {
                model: appRoot.compact ? [] : ["对话", "改动与产物"]
                delegate: SamayaButton {
                    required property string modelData
                    text: modelData
                    typeSize: 12
                    onClicked: appRoot.tab = text
                    Rectangle {
                        visible: appRoot.tab === parent.text
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 22
                        height: 2
                        color: Style.ink
                    }
                }
            }
            Item {
                visible: appRoot.compact
                Layout.fillWidth: true
            }
            SamayaButton {
                visible: appRoot.collapsed && !appRoot.compact
                glyph: "menu"
                hint: "展开侧栏"
                onClicked: appRoot.collapsed = false
            }
            Ink {
                visible: !view.narrow && !!appRoot.currentId
                text: U.status(appRoot.thread, ((appRoot.thread.turns || []).slice(-1))[0])
                color: Style.muted
                font.pixelSize: 12
            }
            SamayaButton {
                visible: !view.narrow || appRoot.compact
                glyph: "bell"
                text: "待处理 " + appRoot.pending.length
                typeSize: 12
                onClicked: appRoot.overview("待我处理")
            }
            SamayaButton {
                visible: !view.narrow || appRoot.compact
                glyph: "alert"
                hint: "连接与运行状态"
                onClicked: appRoot.nav("settings")
            }
            SamayaButton {
                glyph: "more"
                hint: "会话选项"
                onClicked: menu.open()
                Menu {
                    id: menu
                    MenuItem {
                        text: appRoot.pins.includes(appRoot.currentId) ? "取消置顶" : "置顶任务"
                        enabled: !!appRoot.currentId
                        onTriggered: appRoot.pin(appRoot.currentId)
                    }
                    MenuItem {
                        text: "管理工作区"
                        onTriggered: appRoot.recordsFor(appRoot.cwd)
                    }
                    MenuItem {
                        text: "更改工作目录"
                        enabled: !!appRoot.currentId
                        onTriggered: {
                            const path = desktop.directory(appRoot.cwd);
                            if (path)
                                appRoot.act("workspace", {
                                    threadId: appRoot.currentId,
                                    cwd: path
                                }, () => appRoot.refreshThread(false));
                        }
                    }
                }
            }
        }
        ColumnLayout {
            visible: appRoot.compact
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Ink {
                    Layout.fillWidth: true
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    text: appRoot.currentId ? U.title(appRoot.thread) : U.base(appRoot.cwd) + " / 新会话"
                }
                Ink {
                    font.pixelSize: 12
                    color: Style.muted
                    text: appRoot.currentId ? U.status(appRoot.thread, (appRoot.thread.turns || []).slice(-1)[0]) : ""
                }
            }
            Row {
                Repeater {
                    model: ["对话", "改动与产物"]
                    SamayaButton {
                        required property string modelData
                        text: modelData
                        typeSize: 13
                        onClicked: appRoot.tab = text
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width - 24
                            height: 2
                            visible: parent.text === appRoot.tab
                            color: Style.ink
                        }
                    }
                }
            }
        }
        Flickable {
            id: scroll
            objectName: "transcriptScroll"
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight + 32
            boundsBehavior: Flickable.StopAtBounds
            property bool following: true
            onMovementEnded: following = atYEnd
            onContentHeightChanged: if (following && height > 0)
                Qt.callLater(() => {
                    if (scroll.following)
                        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
                })
            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const delta = event.pixelDelta.y || event.angleDelta.y;
                    const end = Math.max(0, scroll.contentHeight - scroll.height);
                    if (!delta || !end) {
                        event.accepted = false;
                        return;
                    }
                    scroll.cancelFlick();
                    // One wheel notch is 120 units. Precision devices already report pixels.
                    scroll.contentY = Math.min(end, Math.max(0, scroll.contentY - delta));
                    scroll.following = end - scroll.contentY < 1;
                    event.accepted = true;
                }
            }
            Connections {
                target: appRoot
                function onSelectionChanged() {
                    scroll.following = true;
                    view.historyCount = 48;
                }
            }
            ScrollBar.vertical: ScrollBar {}
            ColumnLayout {
                id: body
                anchors.horizontalCenter: parent.horizontalCenter
                width: view.readingWidth
                spacing: 16
                ColumnLayout {
                    visible: !appRoot.currentId
                    Layout.fillWidth: true
                    spacing: 8
                    Ink {
                        text: "新会话 · " + U.base(appRoot.cwd)
                        font.pixelSize: 20
                        font.weight: Font.Medium
                    }
                    Ink {
                        text: "写下这次要做的事。"
                        color: Style.muted
                    }
                    Ink {
                        text: appRoot.cwd
                        font.pixelSize: 12
                        color: Style.muted
                        Layout.fillWidth: true
                    }
                }
                SamayaButton {
                    visible: appRoot.tab === "对话" && (!!appRoot.historyCursor || view.timeline.length > view.historyCount)
                    enabled: !appRoot.loadingOlder
                    text: "加载更早的消息"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: {
                        const oldHeight = scroll.contentHeight;
                        scroll.following = false;
                        const reveal = () => {
                            view.historyCount += 48;
                            Qt.callLater(() => scroll.contentY = Math.max(0, scroll.contentHeight - oldHeight));
                        };
                        if (view.historyCount >= view.timeline.length)
                            appRoot.older(reveal);
                        else
                            reveal();
                    }
                }
                Repeater {
                    model: StableRows {
                        source: appRoot.tab === "对话" ? view.timeline.slice(-view.historyCount) : []
                        keyFor: entry => entry.key
                    }
                    delegate: TranscriptItem {
                        required property QtObject row
                        entry: row.value
                        appRoot: view.appRoot
                        Layout.fillWidth: true
                        onTogglingTools: scroll.following = false
                    }
                }
                Repeater {
                    model: appRoot.tab === "对话" ? appRoot.currentRequests : []
                    delegate: Approval {
                        required property var modelData
                        request: modelData
                        appRoot: view.appRoot
                        Layout.fillWidth: true
                    }
                }
                ColumnLayout {
                    visible: appRoot.tab !== "对话"
                    spacing: 16
                    Layout.fillWidth: true
                    Ink {
                        text: "产物"
                        font.weight: Font.Medium
                    }
                    Repeater {
                        model: view.artifacts
                        SamayaButton {
                            required property var modelData
                            text: modelData.path || ""
                            glyph: "search-file"
                            onClicked: desktop.saveArtifact(appRoot.currentId, modelData.path, (d, e) => appRoot.tell(e))
                        }
                    }
                    Ink {
                        visible: !view.artifacts.length
                        text: "暂无文件产物"
                        color: Style.muted
                    }
                    Rectangle {
                        height: 1
                        Layout.fillWidth: true
                        color: Style.border
                    }
                    Ink {
                        text: "改动"
                        font.weight: Font.Medium
                    }
                    Repeater {
                        model: view.artifacts
                        Ink {
                            required property var modelData
                            Layout.fillWidth: true
                            text: (modelData.path || "") + "　" + ((modelData.kind || {}).type || "")
                            color: Style.muted
                        }
                    }
                    Ink {
                        text: "执行记录"
                        font.weight: Font.Medium
                    }
                    Repeater {
                        model: StableRows {
                            source: appRoot.tab === "改动与产物" ? view.timeline.filter(e => e.kind === "tools") : []
                            keyFor: entry => entry.key
                        }
                        TranscriptItem {
                            required property QtObject row
                            entry: row.value
                            appRoot: view.appRoot
                            Layout.fillWidth: true
                            onTogglingTools: scroll.following = false
                        }
                    }
                }
            }
        }
        Rectangle {
            visible: appRoot.online && !!appRoot.thread.externalWriter
            Layout.fillWidth: true
            Layout.maximumWidth: view.readingWidth
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: writerBody.implicitHeight + 24
            color: Style.subtle
            radius: 8
            RowLayout {
                id: writerBody
                x: 12
                y: 12
                width: parent.width - 24
                Ink {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "这条会话由另一 Codex 实例使用。释放占用后可重试，也可以从模型菜单把设置应用到历史副本。"
                    color: Style.muted
                    font.pixelSize: 12
                }
                SamayaButton {
                    text: "重试"
                    enabled: !appRoot.busy
                    onClicked: appRoot.refreshThread(true)
                }
            }
        }
        Rectangle {
            visible: !appRoot.online && !!appRoot.currentId
            Layout.fillWidth: true
            Layout.maximumWidth: view.readingWidth
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: offline.implicitHeight + 24
            color: Style.surface
            border.color: Style.border
            radius: 8
            ColumnLayout {
                id: offline
                x: 16
                y: 12
                width: parent.width - 32
                Ink {
                    text: "连接中断 · 状态待确认"
                    font.pixelSize: 18
                }
                Ink {
                    Layout.fillWidth: true
                    color: Style.muted
                    text: "保留最后一次已知状态，连接恢复后可继续核对执行结果。"
                    wrapMode: Text.Wrap
                }
                SamayaButton {
                    kind: "primary"
                    text: "重新连接"
                    enabled: !appRoot.connecting
                    onClicked: appRoot.connectExisting()
                }
            }
        }
        Composer {
            id: inputBox
            appRoot: view.appRoot
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(860, view.readingWidth)
            Layout.bottomMargin: appRoot.compact ? 8 : 20
        }
    }
}
