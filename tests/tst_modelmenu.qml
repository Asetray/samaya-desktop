import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../qml" as UI

Item {
    id: scene
    width: 1000
    height: 650

    QtObject {
        id: desktop
        readonly property bool reducedMotion: true
    }
    QtObject {
        id: app
        property bool online: true
        property bool busy: false
        property bool compact: false
        readonly property int width: scene.width
        readonly property int height: scene.height
        property int selection: 0
        property string currentId: "thread"
        property string openingThreadId: ""
        property string cwd: "D:/workspace"
        property var thread: ({})
        property var drafts: ({})
        property var selectionSettings: ({})
        readonly property var modelOptions: [{
            model: "test-model", displayName: "Test model", defaultReasoningEffort: "medium",
            effortOptions: [{value: "low"}, {value: "medium"}, {value: "high"}, {value: "xhigh"}],
            serviceTiers: [{id: "fast"}]
        }, {model: "other-model", displayName: "Other model", effortOptions: [{value: "low"}],
            serviceTiers: [{id: "fast"}]}]
        property var catalog: modelOptions
        property var activeModel: ({ model: "test-model", reasoningEffort: "low", serviceTier: "default" })
        property int saveCount: 0
        property string request: ""
        property string requestedCommand: ""
        property var applied
        property var settled
        property int modelReads: 0
        property bool delayModelRead: false
        property var completeModelRead

        function models(ready, failed) {
            ++modelReads
            if (delayModelRead)
                completeModelRead = ready
            else
                ready()
        }
        function modelSetting(command, value, applied, finished) {
            if (busy)
                return false
            saveCount++
            request = value
            requestedCommand = command
            app.applied = applied
            settled = finished
            busy = true
            return true
        }
        function finish(accepted) {
            busy = false
            if (accepted) {
                const key = ({model: "model", fast: "serviceTier", reasoning: "reasoningEffort"})[requestedCommand]
                activeModel = Object.assign({}, activeModel, {[key]: request})
                if (applied) applied()
            }
            if (settled) settled()
        }
    }
    UI.Composer {
        id: composer
        width: 660
        height: implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        appRoot: app
    }
    TestCase {
        name: "ModelMenu"
        when: windowShown

        function init() {
            app.busy = false
            app.saveCount = 0
            app.request = ""
            app.requestedCommand = ""
            app.thread = {}
            app.openingThreadId = ""
            app.delayModelRead = false
            app.compact = false
            findChild(composer, "speedMenu").close()
            app.activeModel = {model: "test-model", reasoningEffort: "low", serviceTier: "default"}
            const menu = findChild(composer, "modelMenu")
            if (menu.opened)
                menu.close()
            const button = findChild(composer, "modelSelector")
            mouseClick(button, button.width / 2, button.height / 2)
            tryCompare(menu, "opened", true)
        }
        function test_dragStaysAtRequestedStopWhileSaving() {
            const menu = findChild(composer, "modelMenu")
            const slider = findChild(menu, "reasoningSlider")
            const y = slider.height / 2
            const x = slider.firstStopCenter + slider.distanceBetweenStops * 2
            mousePress(slider, slider.firstStopCenter, y, Qt.LeftButton)
            mouseMove(slider, x, y, 65, Qt.LeftButton)
            tryCompare(menu, "shownEffort", "high")
            compare(app.saveCount, 0)
            mouseRelease(slider, x, y, Qt.LeftButton)
            tryCompare(app, "saveCount", 1)
            compare(findChild(composer, "modelSelector").background.color, UI.Style.selected)
            compare(app.activeModel.reasoningEffort, "low")
            compare(menu.shownEffort, "high")
            const handle = findChild(slider, "reasoningHandle")
            const pendingPosition = handle.x
            const stop = findChild(slider, "reasoningStop-0")
            app.activeModel = Object.assign({}, app.activeModel)
            wait(150)
            verify(menu.opened)
            compare(menu.shownEffort, "high")
            compare(handle.x, pendingPosition)
            verify(findChild(slider, "reasoningStop-0") === stop)
            app.finish(true)
            compare(menu.requestedEffort, "")
            compare(menu.shownEffort, "high")
            compare(handle.x, pendingPosition)
            compare(app.saveCount, 1)
        }
        function test_keyboardFailureReturnsToConfirmedStop() {
            const menu = findChild(composer, "modelMenu")
            const slider = findChild(menu, "reasoningSlider")
            tryVerify(() => findChild(menu, "modelListButton").activeFocus)
            slider.forceActiveFocus(Qt.TabFocusReason)
            tryCompare(slider, "activeFocus", true)
            keyClick(Qt.Key_Right)
            tryCompare(app, "saveCount", 1)
            compare(menu.shownEffort, "medium")
            app.finish(false)
            compare(menu.requestedEffort, "")
            compare(menu.shownEffort, "low")
            compare(menu.opened, true)
        }
        function test_hoverButtons_data() {
            return [{tag: "vallum", dark: false}, {tag: "abyssus", dark: true}]
        }
        function test_speedClickDoesNotMoveToolbarOrReopenOnClose() {
            const menu = findChild(composer, "modelMenu")
            const speed = findChild(composer, "speedMenu")
            const lightning = findChild(composer, "composerSpeedSelector")
            const button = findChild(composer, "modelSelector")
            menu.close()
            tryCompare(menu, "visible", false)
            ++app.selection
            app.delayModelRead = true
            const reads = app.modelReads
            const toolbarState = () => [button.mapToItem(scene, 0, 0).x, button.width,
                                        lightning.mapToItem(scene, 0, 0).x].join(",")
            const original = toolbarState()
            const clickSpeed = () => mouseClick(lightning, lightning.width / 2, lightning.height / 2)
            clickSpeed()
            compare(app.modelReads, reads + 1)
            verify(composer.speedLoading)
            verify(!composer.modelLoading)
            verify(!speed.visible)
            compare(toolbarState(), original)
            app.completeModelRead()
            tryCompare(speed, "opened", true)
            compare(toolbarState(), original)
            clickSpeed()
            tryCompare(speed, "visible", false)
            clickSpeed()
            tryCompare(speed, "opened", true)
            compare(app.modelReads, reads + 1)
            compare(toolbarState(), original)
        }
        function test_speedSwitchFromModelPanelKeepsFocus_data() {
            return [{tag: "wide", compact: false}, {tag: "compact", compact: true}]
        }
        function test_speedSwitchFromModelPanelKeepsFocus(data) {
            app.compact = data.compact
            const menu = findChild(composer, "modelMenu")
            const speed = findChild(composer, "speedMenu")
            const lightning = findChild(menu, "speedSelector")
            mouseClick(lightning, lightning.width / 2, lightning.height / 2)
            tryCompare(speed, "opened", true)
            tryCompare(menu, "visible", false)
            verify(speed.activeFocus)
        }
        function test_runningTurnCanEditNextTurnSettings() {
            const model = findChild(composer, "modelMenu")
            const speed = findChild(composer, "speedMenu")
            const toggle = findChild(composer, "modelSelector")
            model.close()
            const turn = {id: "running-turn", status: "inProgress"}
            app.thread = {turns: [turn]}
            mouseClick(toggle)
            tryCompare(model, "opened", true)
            mouseClick(findChild(model, "modelListButton"))
            tryCompare(model, "listOpen", true)
            tryVerify(() => scene.Window.window.activeFocusItem?.text === "选择模型")
            keyClick(Qt.Key_Down)
            tryVerify(() => scene.Window.window.activeFocusItem?.text === "Test model")
            keyClick(Qt.Key_Down)
            tryVerify(() => scene.Window.window.activeFocusItem?.text === "Other model")
            keyClick(Qt.Key_Space)
            compare(app.requestedCommand, "model")
            compare(app.request, "other-model")
            compare(app.activeModel.model, "test-model")
            app.finish(true)
            compare(app.activeModel.model, "other-model")

            mouseClick(findChild(model, "speedSelector"))
            tryCompare(speed, "opened", true)
            const fast = speed.contentItem.children.find(item => item.objectName === "speed-fast")
            verify(fast)
            mouseClick(fast)
            compare(app.requestedCommand, "fast")
            compare(app.request, "fast")
            compare(app.activeModel.serviceTier, "default")
            app.finish(true)
            compare(app.activeModel.serviceTier, "fast")
            compare(app.thread.turns[0], turn)
            verify(composer.running)
        }
        function test_hoverButtons(data) {
            UI.Style.dark = data.dark
            const menu = findChild(composer, "modelMenu")
            const button = findChild(composer, "modelSelector")
            const outerSpeed = findChild(composer, "composerSpeedSelector")
            const innerSpeed = findChild(menu, "speedSelector")
            const mode = findChild(composer, "modeSelector")
            const outerIcon = findChild(outerSpeed, "speedLightning")
            const innerIcon = findChild(innerSpeed, "speedLightning")
            compare(mode.height, button.height)
            compare(outerSpeed.height, button.height)
            compare(outerSpeed.width, outerSpeed.height)
            compare(mode.mapToItem(scene, 0, 0).y, button.mapToItem(scene, 0, 0).y)
            compare(outerSpeed.mapToItem(scene, 0, 0).y, button.mapToItem(scene, 0, 0).y)
            compare(outerSpeed.background.radius, 8)
            compare(outerSpeed.mapToItem(scene, 0, 0).x - mode.mapToItem(scene, mode.width, 0).x, 2)
            verify(outerIcon.source.toString().includes("/speed-lightning-outline/"))
            verify(innerIcon.source.toString().includes("/speed-lightning-outline/"))
            menu.close()
            tryCompare(menu, "visible", false)
            const original = button.mapToItem(scene, 0, 0)
            mouseMove(button, button.width / 2, button.height / 2)
            tryCompare(button, "hovered", true)
            compare(button.background.color, UI.Style.hover)
            compare(button.mapToItem(scene, 0, 0), original)
            mouseMove(outerSpeed, outerSpeed.width / 2, outerSpeed.height / 2)
            tryCompare(outerSpeed, "hovered", true)
            compare(outerSpeed.background.color, UI.Style.hover)
            wait(600)
            verify(!outerSpeed.ToolTip.visible)
            mouseClick(button, button.width / 2, button.height / 2)
            tryCompare(menu, "opened", true)
            compare(button.background.color, UI.Style.selected)
            mouseMove(innerSpeed, innerSpeed.width / 2, innerSpeed.height / 2)
            tryCompare(innerSpeed, "hovered", true)
            compare(innerSpeed.width, innerSpeed.height)
            compare(innerSpeed.background.color, UI.Style.hover)
            wait(600)
            verify(!innerSpeed.ToolTip.visible)
            verify(menu.opened)
            app.activeModel = Object.assign({}, app.activeModel, {serviceTier: "fast"})
            verify(outerIcon.source.toString().includes("/speed-lightning/"))
            verify(innerIcon.source.toString().includes("/speed-lightning/"))
        }
    }
}
