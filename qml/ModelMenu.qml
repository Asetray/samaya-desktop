import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Popup {
    id: menu
    required property var appRoot
    required property string modelLabel
    required property bool editable
    property bool listOpen: false
    signal speedRequested
    readonly property var models: appRoot.catalog
    readonly property var recommended: models.find(model => model.isDefault)
    readonly property var entries: recommended ? [{model: recommended.model, displayName: "默认", shortcut: true}].concat(models) : models
    readonly property var current: appRoot.activeModel
    readonly property var selected: models.find(model => model.model === current.model)
    readonly property var efforts: selected?.effortOptions || []
    readonly property string defaultEffort: selected?.defaultReasoningEffort || selected?.defaultEffort || ""
    readonly property int effortIndex: efforts.findIndex(entry => entry.value === current.reasoningEffort)
    readonly property int shownIndex: slider.pressed ? Math.round(slider.value) : effortIndex
    readonly property string shownEffort: efforts[shownIndex]?.value || current.reasoningEffort || ""

    function showList() {
        listOpen = true;
        list.positionViewAtBeginning();
        Qt.callLater(() => modelHeading.forceActiveFocus(Qt.OtherFocusReason));
    }
    function showEffort() {
        listOpen = false;
        Qt.callLater(() => effortHeading.forceActiveFocus(Qt.OtherFocusReason));
    }
    function applyEffort(index) {
        const value = efforts[index]?.value;
        if (editable && value && value !== current.reasoningEffort)
            appRoot.modelSetting("reasoning", value);
    }

    width: 260
    height: listOpen ? Math.min(42 + 28 * models.length + (recommended ? 48 : 0) + (models.length ? 0 : 28),
                               Math.max(106, appRoot.height * 0.55))
                     : 118
    padding: listOpen ? 6 : 13
    topPadding: listOpen ? 10 : 13
    bottomPadding: listOpen ? 8 : 13
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: listOpen ? showList() : showEffort()
    background: Rectangle {
        radius: menu.listOpen ? 14 : 18
        color: Style.surface
        border.color: Style.border
    }
    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            visible: !menu.listOpen
            spacing: 12
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                SamayaButton {
                    objectName: "speedSelector"
                    width: 28
                    height: 32
                    x: -7
                    anchors.verticalCenter: parent.verticalCenter
                    hint: "响应速度 · " + U.speedLabel(menu.current.serviceTier)
                    enabled: menu.editable
                    contentItem: Item {
                        Image {
                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13
                            height: 18
                            sourceSize: Qt.size(26, 36)
                            source: Style.symbol("reasoning-lightning", Style.link)
                        }
                    }
                    onClicked: menu.speedRequested()
                }
                SamayaButton {
                    id: effortHeading
                    objectName: "modelListButton"
                    anchors.fill: parent
                    anchors.leftMargin: 21
                    anchors.rightMargin: 36
                    hint: "选择模型"
                    contentItem: Item {
                        Column {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: 2
                            Ink {
                                width: parent.width
                                height: 20
                                horizontalAlignment: Text.AlignHCenter
                                text: (U.effortLabel(menu.shownEffort) || "推理强度") + "  ›"
                                color: Style.link
                            }
                            Ink {
                                width: parent.width
                                height: 20
                                horizontalAlignment: Text.AlignHCenter
                                text: menu.modelLabel
                                font.pixelSize: 12
                                color: Style.muted
                            }
                        }
                    }
                    onClicked: menu.showList()
                }
                SamayaButton {
                    id: resetEffort
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 32
                    text: "↶"
                    typeSize: 20
                    foreground: Style.muted
                    hint: "重置为模型默认强度"
                    Accessible.name: hint
                    enabled: menu.editable && !!menu.defaultEffort && menu.defaultEffort !== menu.current.reasoningEffort
                    contentItem: Ink {
                        text: resetEffort.text
                        font.family: "Segoe UI Symbol"
                        font.pixelSize: resetEffort.typeSize
                        color: resetEffort.foreground
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideNone
                    }
                    onClicked: menu.applyEffort(menu.efforts.findIndex(entry => entry.value === menu.defaultEffort))
                }
            }
            Slider {
                id: slider
                objectName: "reasoningSlider"
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                visible: menu.efforts.length > 0
                enabled: menu.editable && menu.efforts.length > 1
                padding: 2
                readonly property int stopSize: 24
                readonly property real firstStopCenter: leftPadding + stopSize / 2
                readonly property real distanceBetweenStops: (availableWidth - stopSize) / Math.max(1, menu.efforts.length - 1)
                readonly property real selectedCenter: firstStopCenter + Math.max(0, menu.shownIndex) * distanceBetweenStops
                from: 0
                to: Math.max(1, menu.efforts.length - 1)
                stepSize: 1
                snapMode: Slider.SnapAlways
                value: Math.max(0, menu.effortIndex)
                Accessible.name: "推理强度 · " + U.effortLabel(menu.shownEffort)
                onMoved: if (!pressed) menu.applyEffort(Math.round(value))
                onPressedChanged: if (!pressed) menu.applyEffort(Math.round(value))
                background: Rectangle {
                    radius: height / 2
                    color: Style.subtle
                    border.width: slider.visualFocus ? 1 : 0
                    border.color: Style.focus
                    Rectangle {
                        objectName: "reasoningProgress"
                        visible: menu.shownIndex >= 0
                        width: Math.max(slider.stopSize, slider.selectedCenter)
                        height: parent.height
                        radius: height / 2
                        color: Style.primary
                        opacity: 0.25
                    }
                    Repeater {
                        model: menu.efforts
                        Image {
                            required property int index
                            objectName: "reasoningStop-" + index
                            visible: index !== menu.shownIndex
                            width: slider.stopSize
                            height: slider.stopSize
                            x: slider.firstStopCenter + slider.distanceBetweenStops * index - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            sourceSize: Qt.size(48, 48)
                            source: Style.symbol("effort-stop", Style.quiet)
                        }
                    }
                }
                handle: Rectangle {
                    objectName: "reasoningHandle"
                    x: slider.selectedCenter - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: slider.stopSize
                    implicitHeight: slider.stopSize
                    visible: menu.shownIndex >= 0
                    radius: 12
                    color: Style.ink
                }
            }
            Ink {
                visible: !slider.visible
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                text: menu.selected ? "此模型没有可调节的推理强度" : "请选择可用模型"
                color: Style.muted
                font.pixelSize: 12
            }
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: menu.listOpen
            SamayaButton {
                id: modelHeading
                Layout.fillWidth: true
                implicitHeight: 24
                text: "选择模型"
                alignLeft: true
                foreground: Style.muted
                hint: "返回推理强度"
                Keys.onDownPressed: if (list.count) list.focusRow(0);
                onClicked: menu.showEffort()
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: menu.entries
                boundsBehavior: Flickable.StopAtBounds
                function focusRow(index) {
                    currentIndex = Math.max(0, Math.min(count - 1, index));
                    positionViewAtIndex(currentIndex, ListView.Contain);
                    Qt.callLater(() => currentItem?.forceActiveFocus(Qt.TabFocusReason));
                }
                ScrollBar.vertical: ScrollBar {}
                delegate: SamayaButton {
                    id: row
                    required property var modelData
                    required property int index
                    objectName: modelData.shortcut ? "model-option-default" : "model-option-" + modelData.model
                    width: ListView.view.width
                    height: modelData.shortcut ? 48 : 28
                    text: modelData.displayName || modelData.model
                    selected: !modelData.shortcut && menu.current.model === modelData.model
                    fill: hovered ? Style.hover : "transparent"
                    enabled: menu.editable
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: selected
                    Keys.onUpPressed: index > 0 ? list.focusRow(index - 1) : modelHeading.forceActiveFocus(Qt.TabFocusReason)
                    Keys.onDownPressed: list.focusRow(index + 1)
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                            list.focusRow(event.key === Qt.Key_Home ? 0 : list.count - 1);
                            event.accepted = true;
                        }
                    }
                    Keys.onLeftPressed: menu.showEffort()
                    contentItem: RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Ink { Layout.fillWidth: true; Layout.preferredHeight: 20; text: row.text }
                            Ink {
                                visible: !!row.modelData.shortcut
                                Layout.fillWidth: true
                                Layout.preferredHeight: 16
                                text: "推荐模型集"
                                color: Style.muted
                                font.pixelSize: 12
                            }
                        }
                        Ink { visible: row.selected; text: "✓" }
                    }
                    onClicked: {
                        if (menu.current.model === modelData.model)
                            menu.showEffort();
                        else
                            menu.appRoot.modelSetting("model", modelData.model, () => {
                                if (menu.opened)
                                    menu.showEffort();
                            });
                    }
                }
            }
            Ink {
                Layout.fillWidth: true
                visible: list.count === 0
                text: "暂无可用模型"
                color: Style.muted
                leftPadding: 10
            }
        }
    }
}
