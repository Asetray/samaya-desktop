import QtQuick
import QtTest
import "../qml" as UI
import "../qml/Util.js" as U

Item {
    id: scene
    width: 1050
    height: 720
    QtObject {
        id: desktop
        readonly property bool reducedMotion: false
        function styleReply(document, color, hoverColor, hoverBackground) {}
        function setReplyLinkHover(document, position) {}
        function repaintReplySelection(document) {}
        function styleUserMessage(document) {}
    }
    QtObject {
        id: app
        property var rows: []
        readonly property var groups: U.grouped(rows)
        property var thread: ({})
        property string currentId: "a"
        property string lastOpened: ""
        property int opens: 0
        property int selection: 0
        property var pending: []
        property var currentRequests: []
        property var pins: []
        property var activeModel: ({})
        property var drafts: ({})
        property var selectionSettings: ({})
        property var catalog: []
        property bool busy: false
        property bool compact: false
        property bool collapsed: false
        property bool drawer: false
        property bool online: true
        property bool connecting: false
        property bool loadingOlder: false
        property string historyCursor: ""
        property string page: "chat"
        property string scope: "任务总览"
        property string tab: "对话"
        property string cwd: "D:/workspace"
        property int width: scene.width
        property int height: scene.height
        function openThread(id) { lastOpened = id; opens++; currentId = id }
    }
    UI.Sidebar { id: sidebar; width: 250; height: parent.height; appRoot: app }
    UI.Chat { id: chat; x: sidebar.width; width: parent.width - x; height: parent.height; appRoot: app }

    TestCase {
        name: "RefreshHover"
        when: windowShown

        function button(parent, prefix) {
            if (!parent.visible) return null
            if (typeof parent.clicked === "function" && typeof parent.text === "string" && parent.text.startsWith(prefix))
                return parent
            for (const item of parent.children || []) {
                const found = button(item, prefix)
                if (found) return found
            }
            return null
        }
        function records(ids) {
            return ids.map(id => ({thread: {id: id, name: "会话 " + id, cwd: app.cwd}}))
        }
        function snapshot(count, tail) {
            const items = [{id: "progress", type: "agentMessage", phase: "commentary", text: "正在检查"}]
            for (let i = 0; i < count; ++i)
                items.push({id: "tool-" + i, type: "commandExecution", command: "step " + i, aggregatedOutput: "output"})
            items.push({id: "answer", type: "agentMessage", text: tail})
            return {id: "a", turns: [{id: "turn-1", status: "completed", items: items}]}
        }
        function init() {
            mouseMove(scene, scene.width - 2, 2)
            app.rows = records(["a", "b", "c", "d", "e", "f"])
            app.thread = snapshot(25, "初始回答")
            app.currentId = "a"
            app.opens = 0
            app.tab = "对话"
            wait(60)
        }
        function test_sidebarPressDuringRefresh() {
            const item = button(sidebar, "会话 b")
            verify(item)
            const point = item.mapToItem(scene, 3, item.height / 2)
            mouseMove(scene, point.x, point.y)
            tryCompare(item, "hovered", true)
            compare(item.background.color, UI.Style.railHover)
            mousePress(scene, point.x, point.y)
            app.rows = records(["f", "a", "b", "c", "d", "e"])
            wait(40)
            verify(item && button(sidebar, "会话 b") === item, "Monitor refresh replaced the pressed sidebar button")
            compare(item.mapToItem(scene, 3, item.height / 2), point)
            verify(item.hovered && item.pressed)
            mouseRelease(scene, point.x, point.y)
            compare(app.lastOpened, "b")
            compare(app.opens, 1)
            mouseMove(scene, chat.x + 5, 2)
            tryVerify(() => button(sidebar, "会话 f").y < item.y)
        }
        function test_removedSidebarThreadDoesNotOpenNeighbour() {
            const item = button(sidebar, "会话 b")
            verify(item)
            const point = item.mapToItem(scene, 10, item.height / 2)
            mouseMove(scene, point.x, point.y)
            mousePress(scene, point.x, point.y)
            app.rows = records(["a", "c", "d", "e", "f"])
            wait(40)
            verify(!button(sidebar, "会话 b"))
            mouseRelease(scene, point.x, point.y)
            compare(app.opens, 0)
        }
        function test_toolPressDuringRefresh_data() {
            return [{tag: "conversation", tab: "对话"}, {tag: "artifacts", tab: "改动与产物"}]
        }
        function test_toolPressDuringRefresh(data) {
            app.tab = data.tab
            wait(60)
            const conversation = data.tab === "对话"
            const item = conversation ? findChild(chat, "workProcessToggle") : button(chat, "完成 25")
            verify(item)
            const targetX = conversation ? 3 : item.width - 3
            const point = item.mapToItem(scene, targetX, 3)
            mouseMove(scene, point.x, point.y)
            tryCompare(item, "hovered", true)
            compare(item.background.color, UI.Style.hover)
            const hovered = grabImage(item)
            for (let i = 0; i < 6; ++i) {
                app.thread = snapshot(25, "悬停刷新 " + i)
                wait(18)
                verify(hovered.equals(grabImage(item)), "Tool button pixels changed while the pointer was stationary")
            }
            mousePress(scene, point.x, point.y)
            for (let i = 0; i < 6; ++i) {
                app.thread = snapshot(25, "流式更新 " + i)
                wait(16)
            }
            const current = conversation ? findChild(chat, "workProcessToggle") : button(chat, "完成 25")
            verify(current === item, "Live updates replaced the pressed tool button")
            verify(item.hovered && item.pressed)
            mouseRelease(scene, point.x, point.y)
            if (conversation)
                tryCompare(item, "trailingGlyphRotation", 90)
            else
                tryCompare(item, "trailingGlyph", "wm-down")
            app.thread = snapshot(26, "最终回答")
            tryVerify(() => conversation ? findChild(chat, "workProcessCount").text.includes("26 次活动")
                && item.trailingGlyphRotation === 90
                : item.text.startsWith("完成 26") && item.trailingGlyph === "wm-down")
            wait(50)
            compare(item.mapToItem(scene, targetX, 3), point)
            if (conversation)
                mouseMove(scene, point.x + 1, point.y)
            tryCompare(item, "hovered", true)
            mouseClick(scene, point.x, point.y)
            if (conversation)
                tryCompare(item, "trailingGlyphRotation", 0)
            else
                tryCompare(item, "trailingGlyph", "chevron")
        }
        function test_historyPrependKeepsVisibleMessage() {
            const turns = []
            for (let i = 0; i < 60; ++i) {
                turns.push({id: "turn-" + i, status: "completed", items: [
                    {id: "user-" + i, type: "userMessage", content: [{type: "text", text: "历史消息 " + i}]}
                ]})
            }
            app.thread = {id: "a", turns: turns}
            const scroll = findChild(chat, "transcriptScroll")
            scroll.following = false
            tryVerify(() => !!button(chat, "加载更早的消息"))
            scroll.contentY = 0
            const anchor = findChild(chat, "conversationRow")
            compare(anchor.entry.item.id, "user-12")
            const offset = anchor.mapToItem(scroll, 0, 0).y
            const load = button(chat, "加载更早的消息")
            mouseClick(load, load.width / 2, load.height / 2)
            tryCompare(chat, "historyCount", 96)
            tryVerify(() => Math.abs(anchor.mapToItem(scroll, 0, 0).y - offset) <= 1)
            compare(findChild(chat, "conversationRow").entry.item.id, "user-0")
        }
        function cleanup() {
            mouseRelease(scene, scene.width - 2, 2)
        }
    }
}
