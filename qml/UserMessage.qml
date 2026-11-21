import QtQuick
import QtQuick.Controls.Basic
import "Util.js" as U

Item {
    id: message
    required property var item
    required property var appRoot
    signal resizing()

    readonly property string plainText: U.messageText(item)
    readonly property real widthLimit: Math.min(544, width * 0.88)
    readonly property var images: Array.from(item.content || []).filter(part => part.type === "image" && part.url)
    readonly property var imageRows: {
        const perRow = widthLimit >= 416 ? 2 : 1;
        const rows = [];
        for (let i = 0; i < images.length; i += perRow)
            rows.push(images.slice(i, i + perRow));
        return rows;
    }
    implicitHeight: content.implicitHeight

    Column {
        id: content
        anchors.right: parent.right
        width: message.widthLimit
        spacing: 8

        Repeater {
            model: message.imageRows
            delegate: Row {
                id: imageRow
                required property var modelData
                readonly property real widthLimit: (content.width - spacing * (modelData.length - 1)) / modelData.length
                anchors.right: parent.right
                spacing: 8
                Repeater {
                    model: imageRow.modelData
                    delegate: Rectangle {
                        required property var modelData
                        readonly property real fitScale: picture.status === Image.Ready
                            && picture.implicitWidth > 0 && picture.implicitHeight > 0
                            ? Math.min(1, imageRow.widthLimit / picture.implicitWidth, 240 / picture.implicitHeight)
                            : 0
                        width: fitScale > 0 ? picture.implicitWidth * fitScale : Math.min(imageRow.widthLimit, 160)
                        height: fitScale > 0 ? picture.implicitHeight * fitScale : 72
                        radius: 8
                        color: Style.subtle
                        Image {
                            id: picture
                            objectName: "userMessageImage"
                            anchors.fill: parent
                            source: modelData.url
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                        }
                        Ink {
                            anchors.centerIn: parent
                            visible: picture.status === Image.Error
                            color: Style.muted
                            text: "图片无法加载"
                        }
                        TapHandler {
                            enabled: picture.status === Image.Ready
                            onTapped: message.appRoot.previewImage = picture.source
                        }
                    }
                }
            }
        }

        Rectangle {
            id: bubble
            objectName: "userMessageBubble"
            readonly property int horizontalPadding: 16
            // Fixed line boxes leave more space above the visible Noto Sans SC glyphs.
            readonly property int topPadding: 8
            readonly property int bottomPadding: 12
            // A message with many short, explicit lines must still fit the expand control.
            readonly property bool hasManyLines: message.plainText.split(/\r\n|[\r\n\u2028\u2029]/, 7).length > 6
            readonly property real minimumTextWidth: hasManyLines ? expandLabel.advanceWidth + toggle.labelMargins : 0
            visible: message.plainText.length > 0
            anchors.right: parent.right
            width: Math.min(content.width, Math.ceil(Math.max(userText.implicitWidth, minimumTextWidth)) + 2 * horizontalPadding)
            height: bubbleBody.implicitHeight + topPadding + bottomPadding
            radius: 12
            color: Style.subtle

            TextMetrics {
                id: expandLabel
                text: "展开全文"
                font.family: Style.family
                font.pixelSize: toggle.typeSize
            }
            Column {
                id: bubbleBody
                x: bubble.horizontalPadding
                y: bubble.topPadding
                width: Math.max(0, parent.width - 2 * bubble.horizontalPadding)
                spacing: 8
                Item {
                    objectName: "userMessageViewport"
                    width: parent.width
                    height: toggle.visible && !toggle.expanded ? Math.min(userText.contentHeight, 168) : userText.contentHeight
                    clip: true
                    TextEdit {
                        id: userText
                        objectName: "userMessageText"
                        property bool readyForLayout: false
                        property bool formatting: false

                        function updateLineHeight() {
                            if (!readyForLayout || formatting)
                                return;
                            formatting = true;
                            desktop.styleUserMessage(textDocument);
                            formatting = false;
                        }

                        width: parent.width
                        height: contentHeight
                        text: message.plainText
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        persistentSelection: true
                        font.family: Style.family
                        font.pixelSize: 16
                        color: Style.ink
                        selectedTextColor: Style.ink
                        selectionColor: Style.textSelection
                        onTextChanged: Qt.callLater(updateLineHeight)
                        Component.onCompleted: {
                            readyForLayout = true;
                            Qt.callLater(updateLineHeight);
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: point => userMenu.popup(point.position.x, point.position.y)
                        }
                        SamayaMenu {
                            id: userMenu
                            objectName: "userMessageMenu"
                            implicitWidth: 176
                            SamayaMenuItem {
                                objectName: "copyUserSelection"
                                text: "复制所选内容"
                                enabled: userText.selectedText.length > 0
                                onTriggered: userText.copy()
                            }
                            SamayaMenuItem {
                                objectName: "copyUserMessage"
                                text: "复制整条消息"
                                onTriggered: desktop.copy(message.plainText)
                            }
                        }
                    }
                }
                SamayaButton {
                    id: toggle
                    objectName: "userMessageToggle"
                    property bool expanded: false
                    visible: userText.lineCount > 6
                    width: Math.min(parent.width, implicitWidth)
                    alignLeft: true
                    labelPadding: 0
                    implicitHeight: 32
                    typeSize: 12
                    foreground: Style.muted
                    text: expanded ? "收起" : expandLabel.text
                    trailingGlyph: "wm-down"
                    trailingGlyphRotation: expanded ? 180 : 0
                    Accessible.description: expanded ? "收起用户消息全文" : "展开用户消息全文"
                    onClicked: {
                        message.resizing();
                        expanded = !expanded;
                    }
                }
            }
        }
    }
}
