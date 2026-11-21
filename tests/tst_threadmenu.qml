import QtQuick
import QtTest
import "../qml" as UI

Item {
    id: fixture

    QtObject {
        id: desktop
        readonly property bool reducedMotion: true
        readonly property bool systemDark: false
        property var threads: []
        property var actions: []
        property var previews: []
        property string previewError: ""
        property string deleteError: ""
        signal appearanceChanged()
        signal lost()
        signal event(string method, var params)

        function setting(key, fallback) { return fallback }
        function save(key, value) {}
        function styleWindowFrame(window, dark, caption, text, border) {}
        function connectServer(done) { done({}, "") }
        function read(path, query, done) {
            if (path === "/account") {
                done({requiresOpenaiAuth: false}, "")
            } else if (path === "/monitor") {
                done({records: threads.filter(thread => !thread.parentId).map(thread => ({thread: thread}))}, "")
            } else if (path === "/threads") {
                done({data: threads}, "")
            } else if (path.startsWith("/threads/")) {
                const id = decodeURIComponent(path.split("/")[2])
                const thread = threads.find(summary => summary.id === id)
                if (path.endsWith("/cleanup-preview")) {
                    previews = previews.concat([id])
                    done({scope: threads.filter(summary => summary.id === id || summary.parentId === id),
                          digest: "preview-" + id}, previewError)
                } else
                    done({thread: Object.assign({turns: []}, thread)}, "")
            } else
                done({}, "")
        }
        function act(action, body, done) {
            actions = actions.concat([{action: action, body: body}])
            if (action === "command" && body.command === "rename") {
                threads = threads.map(summary => summary.id === body.threadId
                    ? Object.assign({}, summary, {name: body.args.value}) : summary)
            } else if (action === "delete") {
                if (deleteError) {
                    done({}, deleteError)
                    return
                }
                if (body.digest !== "preview-" + body.threadId) {
                    done({}, "预览已失效")
                    return
                }
                threads = threads.filter(summary => summary.id !== body.threadId && summary.parentId !== body.threadId)
            }
            done({result: {}}, "")
        }
    }

    Component { id: application; UI.Main { visible: false; width: 1040; height: 760 } }

    TestCase {
        name: "ThreadMenu"
        property var app

        function init() {
            const cwd = "D:/workspace"
            const status = {type: "idle"}
            desktop.threads = [{id: "first", name: "第一条对话", cwd: cwd, status: status},
                               {id: "second", name: "第二条对话", cwd: cwd, status: status},
                               {id: "child", parentId: "second", name: "子会话", cwd: cwd, status: status}]
            desktop.actions = []
            desktop.previews = []
            desktop.previewError = ""
            desktop.deleteError = ""
            app = createTemporaryObject(application, fixture)
            verify(app)
            app.visible = true
            tryCompare(app, "initialized", true)
        }
        function itemNamed(item, name) {
            if (item.objectName === name && item.visible)
                return item
            for (const child of item.children || []) {
                const match = itemNamed(child, name)
                if (match) return match
            }
            return null
        }
        function openContext(name, expectedId) {
            tryVerify(() => !!itemNamed(app.contentItem, name))
            mouseClick(itemNamed(app.contentItem, name), 20, 12, Qt.RightButton)
            const menu = findChild(app, "threadContextMenu")
            tryCompare(menu, "opened", true)
            compare(menu.targetThread.id, expectedId)
            return menu
        }
        function test_sidebarRenameUsesRightClickedThread() {
            tryVerify(() => !!itemNamed(app.contentItem, "sidebarThread-first"))
            mouseClick(itemNamed(app.contentItem, "sidebarThread-first"), 20, 12)
            tryCompare(app, "currentId", "first")

            const menu = openContext("sidebarThread-second", "second")
            compare(app.currentId, "first")
            mouseClick(findChild(menu, "renameThreadAction"))
            const sheet = findChild(app, "renameThreadSheet")
            tryCompare(sheet, "opened", true)
            const input = findChild(sheet, "threadNameInput")
            tryCompare(input, "activeFocus", true)
            compare(input.selectedText, "第二条对话")
            input.text = "   "
            keyClick(Qt.Key_Return)
            compare(desktop.actions.length, 0)
            input.text = "  新名称  "
            keyClick(Qt.Key_Return)
            tryCompare(sheet, "opened", false)
            compare(desktop.actions, [{action: "command", body: {
                threadId: "second", command: "rename", args: {value: "新名称"}
            }}])
            compare(app.rows.find(row => row.thread.id === "second").thread.name, "新名称")
            compare(app.currentId, "first")
            compare(app.thread.name, "第一条对话")
        }
        function test_overviewDeleteRequiresConfirmationAndRemovesItsScope() {
            const review = findChild(app, "threadCleanupReview")
            let menu = openContext("overviewThread-second", "second")
            mouseClick(findChild(menu, "deleteThreadAction"))
            tryCompare(review, "opened", true)
            compare(desktop.previews, ["second"])
            compare(desktop.actions.length, 0)
            mouseClick(findChild(review, "cancelThreadCleanup"))
            tryCompare(review, "opened", false)
            compare(desktop.actions.length, 0)

            desktop.deleteError = "会话已发生变化。"
            menu = openContext("overviewThread-second", "second")
            mouseClick(findChild(menu, "deleteThreadAction"))
            tryCompare(review, "opened", true)
            mouseClick(findChild(review, "confirmThreadCleanup"))
            compare(app.rows.map(row => row.thread.id), ["first", "second"])
            compare(app.notice, "second · 会话已发生变化。")

            desktop.deleteError = ""
            menu = openContext("overviewThread-second", "second")
            mouseClick(findChild(menu, "deleteThreadAction"))
            tryCompare(review, "opened", true)
            mouseClick(findChild(review, "confirmThreadCleanup"))
            compare(desktop.actions.length, 2)
            compare(desktop.actions[1], {action: "delete", body: {threadId: "second", digest: "preview-second"}})
            compare(desktop.threads.map(thread => thread.id), ["first"])
            compare(app.rows.map(row => row.thread.id), ["first"])
        }
        function test_deletingCurrentThreadChecksPreviewBeforeLeavingChat() {
            app.openThread("first")
            desktop.previewError = "会话仍在运行。"
            let menu = openContext("sidebarThread-first", "first")
            mouseClick(findChild(menu, "deleteThreadAction"))
            compare(app.notice, "first · 会话仍在运行。")
            compare(app.currentId, "first")
            compare(desktop.actions.length, 0)

            desktop.previewError = ""
            menu = openContext("sidebarThread-first", "first")
            mouseClick(findChild(menu, "deleteThreadAction"))
            const review = findChild(app, "threadCleanupReview")
            tryCompare(review, "opened", true)
            mouseClick(findChild(review, "confirmThreadCleanup"))
            compare(app.currentId, "")
            compare(app.page, "overview")
            compare(app.rows.map(row => row.thread.id), ["second"])
        }
        function test_recordsRightClickTargetsOneThread() {
            app.recordsFor("")
            const menu = openContext("recordThread-second", "second")
            compare(app.currentId, "")
            verify(findChild(menu, "deleteThreadAction").enabled)
        }
    }
}
