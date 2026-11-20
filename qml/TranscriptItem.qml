import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

ColumnLayout {
    id: line
    required property var entry
    required property var appRoot
    property bool expanded: false
    signal togglingTools()
    spacing: 6
    Loader {
        Layout.fillWidth: true
        sourceComponent: entry.kind === "userMessage" ? user : entry.kind === "tools" ? tools : agent
    }
    Component {
        id: user
        Item {
            implicitHeight: bubble.height
            Rectangle {
                id: bubble
                anchors.right: parent.right
                width: Math.min(parent.width, Math.max(150, parent.width * (appRoot.compact ? 0.88 : 0.62)))
                height: userBody.implicitHeight + 22
                radius: 12
                color: Style.subtle
                ColumnLayout {
                    id: userBody
                    x: 16
                    y: 11
                    width: parent.width - 32
                    spacing: 6
                    Repeater {
                        model: line.entry.item.content || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Ink {
                                visible: modelData.type === "text"
                                Layout.fillWidth: true
                                text: modelData.text || ""
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                font.pixelSize: 16
                                lineHeight: 1.45
                            }
                            Image {
                                visible: modelData.type === "image" && !!modelData.url
                                source: visible ? modelData.url : ""
                                fillMode: Image.PreserveAspectFit
                                Layout.maximumHeight: 160
                                Layout.fillWidth: true
                                TapHandler {
                                    onTapped: appRoot.previewImage = parent.source
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: agent
        ColumnLayout {
            spacing: 8
            TextEdit {
                id: replyText
                objectName: "replyBody"
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
                selectionColor: Style.selected
                Component.onCompleted: desktop.styleReplyLinks(textDocument, Style.link)
                Connections {
                    target: Style
                    function onLinkChanged() { desktop.styleReplyLinks(replyText.textDocument, Style.link) }
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
