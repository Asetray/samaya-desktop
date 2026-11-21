import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Item {
    id: line
    required property var entry
    required property var appRoot
    property var disclosureState: ({})
    property bool expanded: false
    signal togglingTools()
    signal resizing(Item item)
    implicitHeight: presentation.item ? presentation.item.implicitHeight : 0
    Loader {
        id: presentation
        anchors.fill: parent
        sourceComponent: {
            switch (entry.kind) {
            case "userMessage": return user;
            case "tools": return tools;
            case "process": return process;
            case "time": return timestamp;
            case "userShell":
            case "error": return notice;
            default: return agent;
            }
        }
    }
    Component {
        id: process
        WorkProcess {
            entry: line.entry
            appRoot: line.appRoot
            disclosureState: line.disclosureState
            onResizing: item => line.resizing(item)
        }
    }
    Component {
        id: timestamp
        Item {
            objectName: "conversationTime"
            implicitHeight: 20
            Ink {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                color: Style.muted
                text: U.conversationTime(line.entry.at)
            }
        }
    }
    Component {
        id: notice
        Ink {
            text: U.messageText(line.entry.item)
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: 14
        }
    }
    Component {
        id: user
        UserMessage {
            item: line.entry.item
            appRoot: line.appRoot
            onResizing: line.resizing(line)
        }
    }
    Component {
        id: agent
        ColumnLayout {
            spacing: 8
            TextEdit {
                id: replyText
                objectName: "replyBody"
                property bool readyForLayout: false
                property bool formatting: false
                readonly property int hoveredLinkPosition: linkPointer.hovered && hoveredLink
                    ? positionAt(linkPointer.point.position.x, linkPointer.point.position.y, TextEdit.CursorOnCharacter)
                    : -1
                function updateLinkHover() {
                    if (readyForLayout)
                        desktop.setReplyLinkHover(textDocument, hoveredLinkPosition);
                }
                function updateFormatting() {
                    if (!readyForLayout || formatting)
                        return;
                    formatting = true;
                    desktop.styleReply(textDocument, Style.link, Style.linkHover, Style.hover);
                    updateLinkHover();
                    formatting = false;
                }
                Layout.fillWidth: true
                text: U.messageText(line.entry.item)
                textFormat: TextEdit.MarkdownText
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: true
                font.family: Style.family
                font.pixelSize: 16
                color: Style.ink
                selectedTextColor: Style.ink
                selectionColor: Style.textSelection
                HoverHandler {
                    id: linkPointer
                    objectName: "replyLinkHover"
                    cursorShape: replyText.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
                }
                onHoveredLinkPositionChanged: updateLinkHover()
                onLinkActivated: link => {
                    if (!desktop.openReplyLink(link, line.appRoot.cwd || ""))
                        line.appRoot.tell("无法打开此链接。");
                }
                onSelectedTextChanged: desktop.repaintReplySelection(textDocument)
                onTextChanged: updateFormatting()
                Component.onCompleted: {
                    readyForLayout = true;
                    updateFormatting();
                }
                Connections {
                    target: Style
                    function onLinkChanged() { replyText.updateFormatting() }
                }
            }
            SamayaButton {
                objectName: "copyReply"
                visible: line.entry.copyText !== undefined
                Layout.alignment: Qt.AlignLeft
                implicitHeight: 32
                foreground: Style.muted
                glyph: confirmation.running ? "wm-check" : "copy"
                hint: confirmation.running ? "已复制" : "复制本轮回复"
                Accessible.name: "复制本轮回复"
                onClicked: {
                    desktop.copy(line.entry.copyText)
                    confirmation.restart()
                }
                Timer {
                    id: confirmation
                    interval: 2000
                }
            }
        }
    }
    Component {
        id: tools
        ColumnLayout {
            spacing: 6
            SamayaButton {
                activeWork: line.entry.turn === "inProgress"
                glyph: line.entry.turn === "inProgress" ? "model-spinner" : "tool-completed"
                typeSize: 13
                foreground: Style.muted
                text: (line.entry.turn === "inProgress" ? "执行中 · " : "完成 ") + line.entry.items.length + " 次工具调用"
                trailingGlyph: line.expanded ? "wm-down" : "chevron"
                Accessible.description: line.expanded ? "已展开" : "已收起"
                onClicked: {
                    line.togglingTools()
                    line.expanded = !line.expanded
                }
            }
            Repeater {
                model: StableRows {
                    source: line.expanded ? line.entry.items : []
                    keyFor: (item, index) => item.id || index
                }
                delegate: ColumnLayout {
                    required property QtObject row
                    readonly property var modelData: row.value
                    Layout.fillWidth: true
                    Ink {
                        text: modelData.command || modelData.name || modelData.type
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        font.weight: Font.Medium
                    }
                    TextEdit {
                        text: U.messageText(modelData)
                        readOnly: true
                        selectByMouse: true
                        Layout.fillWidth: true
                        wrapMode: TextEdit.Wrap
                        font.family: "Cascadia Mono"
                        font.pixelSize: 13
                        color: Style.muted
                    }
                }
            }
        }
    }
}
