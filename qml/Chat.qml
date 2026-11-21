import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Item {
    id: view
    required property var appRoot
    property alias composer: inputBox
    property int historyCount: 48
    readonly property var timeline: appRoot.tab === "对话" ? [] : U.timeline(appRoot.thread)
    readonly property var transcript: U.conversationTimeline(appRoot.thread)
    readonly property var visibleTranscript: {
        let start = Math.max(0, transcript.length - historyCount);
        while (start > 0 && !transcript[start].startsExchange)
            --start;
        return transcript.slice(start);
    }
    readonly property var disclosures: ({})
    readonly property var artifacts: {
        let out = [];
        for (let turn of appRoot.thread.turns || [])
            for (let it of turn.items || [])
                if (it.type === "fileChange")
                    for (let change of it.changes || [])
                        out.push(change);
        return out;
    }
    readonly property bool narrow: width < 640
    readonly property real readingGutter: Math.max(20, (width - 880) / 2)
    readonly property real readingWidth: Math.max(0, width - 2 * readingGutter)
    function clearTextSelection(item) {
        if ((item instanceof TextEdit || item instanceof TextInput) && item.selectedText.length)
            item.deselect();
        for (const child of item.children)
            clearTextSelection(child);
    }
    component SelectionBackground: MouseArea {
        z: -1
        acceptedButtons: Qt.LeftButton
        onClicked: view.clearTextSelection(view)
    }
    SelectionBackground { anchors.fill: parent }
    component HeaderAction: SamayaButton {
        typeSize: 13
        implicitHeight: 32
    }
    component ChatTab: HeaderAction {
        id: tabButton
        onClicked: view.appRoot.tab = text
        Rectangle {
            visible: view.appRoot.tab === tabButton.text
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: tabButton.labelPadding
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 0
            height: 2
            color: Style.ink
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            objectName: "chatHeader"
            Layout.fillWidth: true
            Layout.minimumHeight: appRoot.compact ? 40 : 48
            Layout.maximumHeight: Layout.minimumHeight
            Layout.leftMargin: appRoot.compact ? 44 : view.readingGutter
            Layout.rightMargin: appRoot.compact ? 12 : 24
            spacing: appRoot.compact ? 4 : 12
            Ink {
                Layout.fillWidth: true
                visible: !appRoot.compact
                text: appRoot.currentId ? U.title(appRoot.thread) : U.base(appRoot.cwd) + " / 新会话"
                font.weight: Font.Medium
                font.pixelSize: 18
            }
            Repeater {
                model: appRoot.compact ? [] : ["对话", "改动与产物"]
                delegate: ChatTab {
                    required property string modelData
                    text: modelData
                }
            }
            Item {
                visible: appRoot.compact
                Layout.fillWidth: true
            }
            HeaderAction {
                visible: appRoot.collapsed && !appRoot.compact
                glyph: "menu"
                hint: "展开侧栏"
                onClicked: appRoot.collapsed = false
            }
            Ink {
                visible: !view.narrow && !!appRoot.currentId
                text: U.status(appRoot.thread, ((appRoot.thread.turns || []).slice(-1))[0])
                Layout.maximumWidth: 120
                color: Style.muted
                font.pixelSize: 12
            }
            HeaderAction {
                visible: !view.narrow || appRoot.compact
                glyph: "bell"
                text: "待处理 " + appRoot.pending.length
                onClicked: appRoot.overview("待我处理")
            }
            HeaderAction {
                visible: !view.narrow || appRoot.compact
                glyph: "alert"
                hint: "连接与运行状态"
                onClicked: appRoot.nav("settings")
            }
            HeaderAction {
                id: conversationOptions
                objectName: "conversationOptions"
                glyph: "more"
                hint: "会话选项"
                onClicked: menu.open()
                SamayaMenu {
                    id: menu
                    x: conversationOptions.width - width
                    y: conversationOptions.height + 4
                    SamayaMenuItem {
                        objectName: "pinThreadMenuItem"
                        text: appRoot.pins.includes(appRoot.currentId) ? "取消置顶" : "置顶任务"
                        enabled: !!appRoot.currentId
                        onTriggered: appRoot.pin(appRoot.currentId)
                    }
                    SamayaMenuItem {
                        text: "管理工作区"
                        onTriggered: appRoot.recordsFor(appRoot.cwd)
                    }
                    SamayaMenuItem {
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
            objectName: "compactChatHeading"
            visible: appRoot.compact
            Layout.fillWidth: true
            Layout.minimumHeight: 68
            Layout.maximumHeight: 68
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Ink {
                    Layout.fillWidth: true
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    text: appRoot.currentId ? U.title(appRoot.thread) : U.base(appRoot.cwd) + " / 新会话"
                }
                Ink {
                    font.pixelSize: 12
                    Layout.maximumWidth: 120
                    color: Style.muted
                    text: appRoot.currentId ? U.status(appRoot.thread, (appRoot.thread.turns || []).slice(-1)[0]) : ""
                }
            }
            Row {
                Layout.preferredHeight: 32
                Repeater {
                    model: ["对话", "改动与产物"]
                    ChatTab {
                        required property string modelData
                        text: modelData
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
            contentHeight: body.implicitHeight + 24
            boundsBehavior: Flickable.StopAtBounds
            property bool following: true
            function followEnd() {
                if (following && height > 0)
                    contentY = Math.max(0, contentHeight - height);
            }
            function revealEarlier() {
                following = false;
                const previousY = contentY;
                const previousHeight = contentHeight;
                const selection = appRoot.selection;
                const first = body.children.find(item => item.objectName === "conversationRow"
                    && body.y + item.y + item.height > previousY);
                const key = first ? first.entry.key : "";
                const offset = first ? body.y + first.y - previousY : 0;
                const reveal = () => {
                    if (selection !== appRoot.selection || appRoot.tab !== "对话")
                        return;
                    view.historyCount += 48;
                    Qt.callLater(() => {
                        if (selection !== appRoot.selection || following)
                            return;
                        const item = body.children.find(row => row.objectName === "conversationRow" && row.entry.key === key);
                        const target = item ? body.y + item.y - offset : previousY + contentHeight - previousHeight;
                        contentY = Math.max(0, Math.min(contentHeight - height, target));
                    });
                };
                if (view.visibleTranscript.length >= view.transcript.length)
                    appRoot.older(reveal);
                else
                    reveal();
            }
            function preserveItem(item) {
                following = false;
                const selection = appRoot.selection;
                const offset = contentY - item.mapToItem(contentItem, 0, 0).y;
                Qt.callLater(() => {
                    if (!item || selection !== appRoot.selection || following)
                        return;
                    const anchor = item.mapToItem(contentItem, 0, 0).y;
                    const target = anchor + Math.min(offset, Math.max(0, item.height - 32));
                    const bounded = Math.max(0, Math.min(contentHeight - height, target));
                    if (Math.abs(contentY - bounded) > 0.1)
                        contentY = bounded;
                });
            }
            onMovementEnded: following = atYEnd
            // Set the offset during layout so the next frame shows the end of the new transcript.
            onContentHeightChanged: followEnd()
            onHeightChanged: followEnd()
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
                    scroll.cancelFlick();
                    scroll.following = true;
                    view.historyCount = 48;
                    scroll.followEnd();
                }
            }
            ScrollBar.vertical: ScrollBar {}
            SelectionBackground {
                width: scroll.width
                height: Math.max(scroll.height, scroll.contentHeight)
            }
            ColumnLayout {
                id: body
                objectName: "transcriptBody"
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
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
                    visible: appRoot.tab === "对话" && (!!appRoot.historyCursor || view.visibleTranscript.length < view.transcript.length)
                    enabled: !appRoot.loadingOlder
                    text: "加载更早的消息"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: scroll.revealEarlier()
                }
                Repeater {
                    model: StableRows {
                        source: appRoot.tab === "对话" ? view.visibleTranscript : []
                        keyFor: entry => entry.key
                    }
                    delegate: TranscriptItem {
                        required property QtObject row
                        objectName: "conversationRow"
                        entry: row.value
                        appRoot: view.appRoot
                        disclosureState: view.disclosures
                        Layout.fillWidth: true
                        Layout.topMargin: entry.extraTop
                        onTogglingTools: scroll.following = false
                        onResizing: item => scroll.preserveItem(item)
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
            objectName: "chatComposer"
            appRoot: view.appRoot
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(860, view.readingWidth)
            Layout.topMargin: 12
            Layout.bottomMargin: 20
        }
    }
}
