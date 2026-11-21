import QtQuick
import QtTest
import "../qml" as UI

Item {
    id: fixture
    QtObject {
        id: desktop
        property var storedPins
        property var requests: ({})
        readonly property bool reducedMotion: true
        readonly property bool systemDark: false
        signal appearanceChanged()
        signal lost()
        signal event(string method, var params)
        function setting(key, fallback) {
            return key === "workspace/pins" ? storedPins : fallback
        }
        function save(key, value) {
            if (key === "workspace/pins")
                storedPins = value
        }
        function styleWindowFrame(window, dark, caption, text, border) {}
        function styleReply(document, color, hoverColor, hoverBackground) {}
        function setReplyLinkHover(document, position) {}
        function repaintReplySelection(document) {}
        function styleUserMessage(document) {}
        function connectServer(done) { done({}, "") }
        function read(path, query, done) {
            if (query.subscribe)
                requests[path] = done
            else
                done({}, "")
        }
        function reply(id, error, turnCount = 1) {
            const path = "/threads/" + id
            const done = requests[path]
            delete requests[path]
            const turns = Array.from({length: turnCount}, (_, i) => {
                const key = i ? id + "-" + i : id
                return {id: key + "-turn", status: "completed", items: [
                    {id: key + "-reply", type: "agentMessage", text: key}
                ]}
            })
            done({
                thread: {id: id, cwd: "D:/workspace", turns: turns},
                historyCursor: id + "-cursor"
            }, error || "")
        }
    }
    Component {
        id: application
        UI.Main { visible: false; width: 1040; height: 700 }
    }
    TestCase {
        name: "ThreadNavigation"
        property var app
        function init() {
            desktop.storedPins = undefined
            desktop.requests = {}
            app = createTemporaryObject(application, fixture)
            verify(app)
        }
        function test_switchKeepsPreviousConversationUntilLatestReply() {
            app.openThread("first")
            desktop.reply("first")
            compare(app.thread.turns[0].items[0].id, "first-reply")
            const selection = app.selection
            app.openThread("slow")
            wait(200)
            compare(app.currentId, "first")
            compare(app.historyCursor, "first-cursor")
            compare(app.thread.turns[0].items[0].id, "first-reply")
            compare(app.selection, selection)
            verify(app.showOpeningThread)

            app.openThread("latest")
            desktop.reply("latest")
            compare(app.currentId, "latest")
            compare(app.thread.turns[0].items[0].id, "latest-reply")
            compare(app.historyCursor, "latest-cursor")
            compare(app.selection, selection + 1)
            desktop.reply("slow")
            compare(app.currentId, "latest")
            compare(app.thread.turns[0].items[0].id, "latest-reply")
        }
        function test_failedOrCancelledSwitchKeepsCurrentConversation() {
            app.openThread("first")
            desktop.reply("first")
            app.openThread("failed")
            desktop.reply("failed", "读取失败")
            compare(app.currentId, "first")
            compare(app.openingThreadId, "")
            compare(app.notice, "读取失败")

            app.openThread("cancelled")
            app.nav("overview")
            desktop.reply("cancelled")
            compare(app.page, "overview")
            compare(app.currentId, "first")
        }
        function test_clickingBlankConversationSpaceClearsTextSelection() {
            app.visible = true
            app.openThread("first")
            desktop.reply("first")
            const first = app.thread.turns[0]
            const user = {id: "user", type: "userMessage", content: [{type: "text", text: "我的消息"}]}
            app.thread = Object.assign({}, app.thread, {turns: [Object.assign({}, first, {items: [user].concat(first.items)})]})
            const scroll = findChild(app, "transcriptScroll")
            verify(waitForRendering(scroll))
            const rows = findChild(app, "transcriptBody").children.filter(item => item.objectName === "conversationRow")
            const outgoing = findChild(rows.find(row => row.entry.kind === "userMessage"), "userMessageText")
            const reply = findChild(rows.find(row => row.entry.kind === "agentMessage"), "replyBody")
            const draft = findChild(app, "composer")
            draft.text = "保留草稿"
            for (const edit of [outgoing, reply, draft]) {
                edit.selectAll()
                verify(edit.selectedText.length > 0)
            }
            mouseClick(scroll, 5, scroll.height / 2, Qt.RightButton)
            verify(reply.selectedText.length > 0)
            mouseClick(scroll, 5, scroll.height / 2)
            for (const edit of [outgoing, reply, draft])
                compare(edit.selectedText, "")
            compare(draft.text, "保留草稿")
            compare(app.currentId, "first")

            const start = outgoing.positionToRectangle(0)
            const end = outgoing.positionToRectangle(3)
            mouseDrag(outgoing, start.x + 1, start.y + start.height / 2, end.x - start.x, 0)
            verify(outgoing.selectedText.length > 0)

            const composer = findChild(app, "chatComposer")
            const gutter = composer.mapToItem(app.contentItem, -10, composer.height / 2)
            mouseClick(app, gutter.x, gutter.y)
            compare(outgoing.selectedText, "")
        }
        function test_firstRenderedFrameIsAtEndOfDestination_data() {
            return [
                {tag: "shortToLong", from: 1, to: 30},
                {tag: "longToShort", from: 30, to: 1}
            ]
        }
        function test_firstRenderedFrameIsAtEndOfDestination(data) {
            app.visible = true
            app.openThread("first")
            desktop.reply("first", "", data.from)
            const scroll = findChild(app, "transcriptScroll")
            verify(scroll)
            verify(waitForRendering(scroll))
            const before = Math.max(0, scroll.contentHeight - scroll.height)
            compare(Math.round(scroll.contentY), Math.round(before))

            const frames = []
            const recordFrame = () => {
                if (app.currentId === "second")
                    frames.push({y: scroll.contentY, end: Math.max(0, scroll.contentHeight - scroll.height)})
            }
            app.frameSwapped.connect(recordFrame)
            try {
                app.openThread("second")
                desktop.reply("second", "", data.to)
                tryVerify(() => frames.length > 0)
                verify(Math.abs(frames[0].end - before) > 1, "The incoming conversation should have a different scroll range")
                compare(Math.round(frames[0].y), Math.round(frames[0].end))
            } finally {
                app.frameSwapped.disconnect(recordFrame)
            }
        }
        function test_pinMenuRecoversFromInvalidStorageAndPersists() {
            app.openThread("first")
            desktop.reply("first")
            const pinMenu = findChild(app, "pinThreadMenuItem")
            verify(pinMenu)
            compare(pinMenu.text, "置顶任务")
            pinMenu.triggered()
            compare(pinMenu.text, "取消置顶")
            compare(JSON.parse(desktop.storedPins), ["first"])

            const reopened = createTemporaryObject(application, fixture)
            reopened.openThread("first")
            desktop.reply("first")
            const reopenedPinMenu = findChild(reopened, "pinThreadMenuItem")
            verify(reopenedPinMenu)
            compare(reopenedPinMenu.text, "取消置顶")
            reopenedPinMenu.triggered()
            compare(reopenedPinMenu.text, "置顶任务")
            compare(JSON.parse(desktop.storedPins), [])
        }
    }
}
