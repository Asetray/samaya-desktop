import QtQuick
import QtTest
import "../qml" as UI
import "../qml/Util.js" as U

Item {
    id: scene
    width: 800
    height: 650

    QtObject {
        id: desktop
        readonly property bool reducedMotion: true
        property string copied: ""
        property int selectionRepaints: 0
        property var openedReplyLinks: []
        property string replyLinkWorkspace: ""
        property bool replyLinkOpens: true
        property int hoveredReplyPosition: -1
        function copy(value) { copied = value }
        function openReplyLink(url, workspace) {
            openedReplyLinks = openedReplyLinks.concat([url])
            replyLinkWorkspace = workspace
            return replyLinkOpens
        }
        function styleReply(document, color, hoverColor, hoverBackground) {}
        function setReplyLinkHover(document, position) { hoveredReplyPosition = position }
        function repaintReplySelection(document) { ++selectionRepaints }
    }
    Component {
        id: message
        UI.TranscriptItem { height: implicitHeight }
    }
    TestCase {
        name: "ReplyCopy"
        when: windowShown

        function reply(text, phase) {
            return {type: "agentMessage", text: text, phase: phase}
        }
        function targets(turns) {
            return U.timeline({turns: turns}).filter(entry => entry.copyText !== undefined)
        }
        function test_boundariesAndMarkdown() {
            const first = "第一段。\n这一行保留两个空格。  \n下一行。"
            const code = "```cpp\n  return 42;\n```"
            const result = targets([{items: [
                {type: "userMessage"}, reply("进度", "commentary"), reply(first),
                {type: "commandExecution", output: "命令输出"}, {type: "plan", text: "计划"},
                reply(code, "final_answer"), {type: "userMessage"}, reply("第二个问题的回答")
            ], error: {message: "错误"}}, {items: [reply("下一轮")]},
                {items: [reply("仅有进度", "commentary"), reply("  ")]}])
            compare(result.length, 3)
            compare(result[0].item.text, code)
            compare(result[0].copyText, first + "\n\n" + code)
            compare(result[1].copyText, "第二个问题的回答")
            compare(result[2].copyText, "下一轮")
        }
        function test_selectingAfterTableRequestsRepaint() {
            const paragraph = "只选中表格下方的文字。"
            const markdown = "| 主题 | 颜色 |\n| --- | --- |\n| 苍渊 | 深蓝 |\n\n" + paragraph
            const row = createTemporaryObject(message, scene, {
                width: 420, entry: {kind: "agentMessage", item: reply(markdown)}, appRoot: {compact: false}
            })
            verify(row)
            const body = findChild(row, "replyBody")
            const start = body.getText(0, body.length).indexOf(paragraph)
            verify(start > 0)
            const before = desktop.selectionRepaints
            body.select(start, start + paragraph.length)
            compare(body.selectedText, paragraph)
            verify(desktop.selectionRepaints > before)
        }
        function test_replyLinkHoverClickAndDrag() {
            const url = "https://example.test/reference#rendering"
            const caption = "Qt 重绘实现"
            const duplicate = "同址参考"
            const markdown = "参考 [" + caption + "](" + url + ") 和 [" + duplicate + "](" + url + ")。"
            let notice = ""
            const row = createTemporaryObject(message, scene, {
                width: 420, entry: {kind: "agentMessage", item: reply(markdown)},
                appRoot: {compact: false, tell: message => { notice = message }}
            })
            verify(row)
            const body = findChild(row, "replyBody")
            const start = body.getText(0, body.length).indexOf(caption)
            verify(start >= 0)
            const first = body.positionToRectangle(start + 1)
            const last = body.positionToRectangle(start + caption.length - 1)
            const y = first.y + first.height / 2
            compare(body.linkAt(first.x + 1, y), url)
            desktop.openedReplyLinks = []
            desktop.replyLinkOpens = true

            const hover = findChild(body, "replyLinkHover")
            verify(hover)
            mouseMove(body, first.x + 1, y)
            tryCompare(hover, "hovered", true)
            tryCompare(hover, "cursorShape", Qt.PointingHandCursor)
            tryVerify(() => desktop.hoveredReplyPosition >= start && desktop.hoveredReplyPosition < start + caption.length)
            const duplicateStart = body.getText(0, body.length).indexOf(duplicate)
            const duplicatePoint = body.positionToRectangle(duplicateStart + 1)
            mouseMove(body, duplicatePoint.x + 1, duplicatePoint.y + duplicatePoint.height / 2)
            tryVerify(() => desktop.hoveredReplyPosition >= duplicateStart
                && desktop.hoveredReplyPosition < duplicateStart + duplicate.length)
            compare(desktop.openedReplyLinks, [])
            mouseMove(body, 2, y)
            tryCompare(hover, "cursorShape", Qt.IBeamCursor)
            tryCompare(desktop, "hoveredReplyPosition", -1)

            mouseClick(body, first.x + 1, y)
            compare(desktop.openedReplyLinks, [url])

            mouseDrag(body, first.x + 1, y, last.x - first.x, 0)
            verify(body.selectedText.length > 0)
            compare(desktop.openedReplyLinks, [url])

            body.deselect()
            desktop.replyLinkOpens = false
            mouseClick(body, first.x + 1, y)
            compare(notice, "无法打开此链接。")
        }
        function test_replyFileLinkClick_data() {
            return [
                {tag: "drivePath", href: "C:/Samaya/dist/samaya-desktop-0.3.6-win-x64-setup.exe"},
                {tag: "markdownPath", href: "/C:/Release%20Files/Samaya.zip"},
                {tag: "fileUrl", href: "file:///C:/Release%20Files/SHA256SUMS.txt"},
                {tag: "folder", href: "C:/Release%20Files/"},
                {tag: "sourceLine", href: "src/desktop.cpp:135"}
            ]
        }
        function test_replyFileLinkClick(data) {
            let notice = ""
            const caption = "发行文件"
            const row = createTemporaryObject(message, scene, {
                width: 420, entry: {kind: "agentMessage", item: reply("[" + caption + "](" + data.href + ")")},
                appRoot: {compact: false, cwd: "C:/Samaya", tell: text => { notice = text }}
            })
            verify(row)
            const body = findChild(row, "replyBody")
            const point = body.positionToRectangle(1)
            const y = point.y + point.height / 2
            compare(body.linkAt(point.x + 1, y), data.href)

            desktop.openedReplyLinks = []
            desktop.replyLinkOpens = true
            mouseClick(body, point.x + 1, y)
            compare(desktop.openedReplyLinks, [data.href])
            compare(desktop.replyLinkWorkspace, "C:/Samaya")
            compare(notice, "")
        }
        function test_streamingAndHistorySlice() {
            const items = [reply("开头")]
            for (let i = 0; i < 50; i++)
                items.push(reply("进度 " + i, "commentary"))
            items.push(reply("流"))
            const thread = {turns: [{items: items, status: "inProgress"}]}
            compare(U.timeline(thread).slice(-48).pop().copyText, "开头\n\n流")
            items[items.length - 1].text += "式回复"
            compare(U.timeline(thread).pop().copyText, "开头\n\n流式回复")
        }
        function test_conversationExchanges() {
            const at = 1760000000
            const user = (id, ms) => ({id, type: "userMessage", samayaTiming: {startedAtMs: ms}})
            const rows = U.conversationTimeline({id: "thread", turns: [{
                id: "turn", status: "completed", startedAt: at, completedAt: at + 3700,
                items: [user("one"), {type: "reasoning", id: "hidden"},
                    reply("进度", "commentary"), {id: "cmd1", type: "commandExecution"},
                    {id: "cmd2", type: "commandExecution", exitCode: 1},
                    reply("第一段", "final_answer"), user("two", (at + 3660) * 1000),
                    reply("第二段", "final_answer")]
            }]})
            compare(rows.map(row => row.kind), ["time", "userMessage", "process", "agentMessage",
                "time", "userMessage", "process", "agentMessage"])
            compare(rows[2].toolCount, 2)
            compare(rows[2].rows.length, 2)
            compare(rows[2].failures, 1)
            compare(rows[2].rows[1].items.length, 2)
            compare(rows[3].copyText, "第一段")
            compare(rows[7].copyText, "第二段")
            verify(rows[4].startsExchange)
        }
        function test_hoverAndClick_data() {
            return [{tag: "wide", lineWidth: 620, compact: false},
                    {tag: "narrow", lineWidth: 244, compact: true}]
        }
        function test_hoverAndClick(data) {
            const paragraph = "可以逐字选中这段回复，鼠标悬停时它的换行位置应当保持稳定。".repeat(4)
            const entries = U.timeline({turns: [{items: [reply("第一段"), reply(paragraph)]}]})
            const row = createTemporaryObject(message, scene, {
                x: 30, y: 36, width: data.lineWidth, entry: entries[1], appRoot: {compact: data.compact}
            })
            verify(row !== null)
            const body = findChild(row, "replyBody")
            const action = findChild(row, "copyReply")
            verify(body && action)
            mouseMove(scene, 5, 5)
            tryVerify(() => body.width === data.lineWidth && body.lineCount > 1
                      && body.height === body.contentHeight && action.visible)
            function geometry() {
                const origin = body.mapToItem(scene, 0, 0)
                return [origin.x, origin.y, body.width, body.height, body.lineCount, row.height,
                        action.y, body.positionToRectangle(Math.floor(paragraph.length / 2))].join("|")
            }
            const baseline = geometry()
            verify(action.y >= body.y + body.height)
            mouseMove(body, 12, 12)
            wait(30)
            compare(geometry(), baseline)
            mouseMove(action, 10, 10)
            tryCompare(action, "hovered", true)
            wait(650) // Allow the delayed tooltip to open.
            compare(geometry(), baseline)
            desktop.copied = ""
            mouseClick(action, 10, 10, Qt.LeftButton)
            compare(desktop.copied, "第一段\n\n" + paragraph)
            compare(action.hint, "已复制")
            mouseMove(scene, 5, 5)
            tryCompare(action, "hovered", false)
            tryCompare(action, "glyph", "copy", 3000)
            compare(geometry(), baseline)
            row.entry = entries[0]
            tryCompare(action, "visible", false)
        }
    }
}
