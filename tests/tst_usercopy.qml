import QtQuick
import QtTest
import "../qml" as UI

Item {
    id: scene
    width: 1000
    height: 700

    QtObject {
        id: desktop
        function styleUserMessage(document) {}
        function copy(value) {
            clipboardRelay.text = value
            clipboardRelay.selectAll()
            clipboardRelay.copy()
        }
    }
    TextEdit { id: clipboardRelay; visible: false }
    TextEdit { id: pasteTarget; x: 900; width: 80; height: 500 }
    QtObject {
        id: app
        readonly property bool compact: false
        property url previewImage
    }
    Flickable {
        id: scroll
        width: 880
        height: 500
        contentWidth: width
        contentHeight: 900
        clip: true
        UI.TranscriptItem {
            id: row
            width: parent.width
            height: implicitHeight
            appRoot: app
            entry: ({kind: "userMessage", item: {type: "userMessage", content: []}})
        }
    }
    TestCase {
        name: "UserMessageCopy"
        when: windowShown

        function showContent(content) {
            row.entry = {kind: "userMessage", item: {type: "userMessage", content: content}}
            scroll.contentY = 0
            wait(80)
            return findChild(row, "userMessageText")
        }
        function pasteClipboard() {
            pasteTarget.text = ""
            pasteTarget.forceActiveFocus()
            keyClick(Qt.Key_V, Qt.ControlModifier)
            return pasteTarget.text
        }
        function test_mouseSelectionAndCopy() {
            const text = "你现在正在使用的套接字是哪一个?"
            const body = showContent([{type: "text", text: text}])
            verify(body && body.readOnly && body.selectByMouse)
            const start = body.positionToRectangle(2)
            const end = body.positionToRectangle(9)
            mousePress(body, start.x + 1, start.y + start.height / 2, Qt.LeftButton)
            mouseMove(body, end.x + 1, end.y + end.height / 2, 80, Qt.LeftButton)
            mouseRelease(body, end.x + 1, end.y + end.height / 2, Qt.LeftButton)
            compare(body.selectedText, text.slice(2, 9))
            compare(scroll.contentY, 0)
            keyClick(Qt.Key_C, Qt.ControlModifier)
            compare(pasteClipboard(), text.slice(2, 9))
        }
        function test_copyPreservesPlainText() {
            const text = "你  好\n  C:\\test\\x & <tag>  \n\n行尾\n"
            const body = showContent([{type: "text", text: text}])
            body.forceActiveFocus()
            keyClick(Qt.Key_A, Qt.ControlModifier)
            keyClick(Qt.Key_C, Qt.ControlModifier)
            compare(pasteClipboard(), text)
        }
        function test_contextMenu() {
            const first = "第一段文字"
            const last = "第二段  & <内容>"
            const body = showContent([{type: "text", text: first}, {type: "image"},
                                      {type: "text", text: last}])
            const menu = findChild(body, "userMessageMenu")
            const copyPart = findChild(menu, "copyUserSelection")
            const copyAll = findChild(menu, "copyUserMessage")
            verify(menu && copyPart && copyAll)
            mouseClick(body, 12, 12, Qt.RightButton)
            tryCompare(menu, "visible", true)
            verify(copyAll.enabled && !copyPart.enabled)
            mouseClick(copyAll, copyAll.width / 2, copyAll.height / 2, Qt.LeftButton)
            compare(pasteClipboard(), first + "\n" + last)

            body.forceActiveFocus()
            body.select(1, 4)
            mouseClick(body, 12, 12, Qt.RightButton)
            tryCompare(menu, "visible", true)
            verify(copyPart.enabled)
            mouseClick(copyPart, copyPart.width / 2, copyPart.height / 2, Qt.LeftButton)
            compare(pasteClipboard(), first.slice(1, 4))
        }
        function test_collapsedMessageCopiesCompleteText() {
            const text = Array.from({length: 12}, (_, index) => "第 " + (index + 1) + " 行  ").join("\n")
            const body = showContent([{type: "text", text: text}])
            const viewport = findChild(row, "userMessageViewport")
            const toggle = findChild(row, "userMessageToggle")
            tryVerify(() => toggle.visible && viewport.height <= 168 && viewport.height < body.contentHeight)
            mouseClick(body, 12, 12, Qt.RightButton)
            const menu = findChild(body, "userMessageMenu")
            tryCompare(menu, "visible", true)
            const copy = findChild(menu, "copyUserMessage")
            mouseClick(copy, copy.width / 2, copy.height / 2, Qt.LeftButton)
            compare(pasteClipboard(), text)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
            tryCompare(viewport, "height", Math.ceil(body.contentHeight))
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
            tryVerify(() => viewport.height < body.contentHeight)
        }
        function test_imagesAboveTextAndPreview() {
            const url = Qt.resolvedUrl("../assets/samaya-symbol.svg")
            app.previewImage = ""
            showContent([{type: "text", text: "附图"}, {type: "image", url: url}])
            const thumbnail = findChild(row, "userMessageImage")
            const bubble = findChild(row, "userMessageBubble")
            tryCompare(thumbnail, "status", Image.Ready)
            compare(thumbnail.width, thumbnail.implicitWidth)
            compare(thumbnail.mapToItem(row, thumbnail.width, 0).x, row.width)
            verify(thumbnail.mapToItem(row, 0, thumbnail.height).y < bubble.mapToItem(row, 0, 0).y)
            mouseClick(thumbnail, thumbnail.width / 2, thumbnail.height / 2)
            compare(app.previewImage.toString(), url.toString())
            showContent([{type: "image", url: url}])
            tryVerify(() => !findChild(row, "userMessageBubble").visible)
        }
        function test_imagePreviewLimits_data() {
            return [{tag: "wide screenshot", sourceWidth: 1040, sourceHeight: 130, width: 544, height: 68},
                    {tag: "tall image", sourceWidth: 300, sourceHeight: 900, width: 80, height: 240}]
        }
        function test_imagePreviewLimits(data) {
            const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + data.sourceWidth + '" height="'
                + data.sourceHeight + '"><rect width="100%" height="100%" fill="navy"/></svg>'
            showContent([{type: "image", url: "data:image/svg+xml;base64," + Qt.btoa(svg)}])
            const image = findChild(row, "userMessageImage")
            tryCompare(image, "status", Image.Ready)
            compare(image.width, data.width)
            compare(image.height, data.height)
            compare(image.mapToItem(row, image.width, 0).x, row.width)
        }
        function test_bubbleWidthFollowsText() {
            const shortText = "每次工作要分批提交"
            const body = showContent([{type: "text", text: shortText}])
            const bubble = findChild(row, "userMessageBubble")
            compare(body.lineCount, 1)
            verify(bubble.width < 250)
            verify(bubble.width >= body.positionToRectangle(shortText.length).x + 32)
            compare(bubble.mapToItem(row, bubble.width, 0).x, row.width)

            showContent([{type: "text", text: "短\n最长一行"}])
            compare(body.lineCount, 2)
            verify(bubble.width < 140)

            showContent([{type: "text", text: "https://example.invalid/" + "%E5%AF%B9%E8%AF%9D".repeat(20)}])
            compare(bubble.width, 544)
            verify(body.lineCount > 1)
            compare(bubble.mapToItem(row, bubble.width, 0).x, row.width)
        }
        function test_shortLinesKeepExpandControlReadable() {
            showContent([{type: "text", text: "小\n字\n也\n可\n以\n展\n开\n看"}])
            const bubble = findChild(row, "userMessageBubble")
            const toggle = findChild(row, "userMessageToggle")
            verify(toggle.visible && toggle.width >= toggle.implicitWidth)
            const width = bubble.width
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
            tryCompare(toggle, "expanded", true)
            compare(bubble.width, width)
        }
    }
}
