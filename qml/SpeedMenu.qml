import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Util.js" as U

Popup {
    id: menu
    required property var appRoot
    signal chosen(string value)
    readonly property var currentModel: appRoot.catalog.find(m => m.model === appRoot.activeModel.model) || {}
    readonly property var options: [{id: "default"}].concat((currentModel.serviceTiers || []).filter(t => t.id && t.id !== "default"))
    width: 262
    height: options.length * 47 + 14
    padding: 7
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
        radius: 18
        color: Style.surface
        border.color: Style.border
    }
    contentItem: Column {
        Repeater {
            model: menu.options
            delegate: SamayaButton {
                id: option
                required property var modelData
                objectName: "speed-" + modelData.id
                width: menu.availableWidth
                height: 47
                text: U.speedLabel(modelData.id, modelData.name)
                readonly property string description: modelData.id === "default" ? "默认速度"
                    : modelData.id === "fast" || modelData.id === "priority" ? "更快响应，可能增加用量"
                    : modelData.id === "ultrafast" ? "优先缩短响应时间" : modelData.description || ""
                selected: (appRoot.activeModel.serviceTier || "default") === modelData.id
                enabled: appRoot.online && !appRoot.busy
                fill: selected ? Style.subtle : hovered ? Style.hover : "transparent"
                Accessible.name: text + "，" + description
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                contentItem: Item {
                    RowLayout {
                        spacing: 8
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Ink { text: option.text; font.pixelSize: 14; Layout.fillWidth: true }
                            Ink { text: option.description; font.pixelSize: 12; color: Style.muted; Layout.fillWidth: true }
                        }
                        Image {
                            objectName: "speedCheck"
                            visible: option.selected
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            sourceSize: Qt.size(32, 32)
                            source: "image://symbols/speed-check"
                        }
                    }
                }
                onClicked: { menu.close(); menu.chosen(modelData.id); }
            }
        }
    }
}
